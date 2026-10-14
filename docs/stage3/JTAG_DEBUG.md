# 独立 RISC-V JTAG 调试

更新：2026-10-15。当前状态是 **RTL + OpenOCD/GDB 仿真通过，TD 时序通过，实板尚未验证**。用户目前没有独立 USB-JTAG 调试器；不能把本页结果表述为已经在真实 FPGA 上完成调试。本轮没有配置 FPGA、使用 COM3 或烧写 Flash。GitHub 同步源码和文档，构建产物、依赖及完整验收日志留在本地 `build/`。

离线准备和完整套件复验已结束；实板阶段 **等待外部硬件**，总目标尚未完成。下一步需要独立调试器和正确接线，不能用重复仿真替代实板验收。

## 目标和两条 JTAG 链路

本轮要求：不借用安路配置 JTAG 的用户扫描链，而是在 RISC-V CPU 电路里加入标准调试模块，把四根调试信号接到 FPGA 普通 I/O；电脑可向 64 KiB RAM 下载程序，并暂停、继续、单步和查看寄存器。

```text
配置电路：TD -> AL-Link Mini -> EF2 专用配置 JTAG -> FPGA 位流
调试软件：GDB -> OpenOCD -> 独立 USB-JTAG -> H3 普通 I/O
                                    -> CPU 的 TAP/DTM -> DMI -> DM -> VexRiscv
                                                                  -> Wishbone -> RAM
```

它们是两套不同的信号和用途。AL-Link Mini 仍可用于配置 FPGA，让新电路存在于板上；之后下载 C 程序和单步使用第二条链路，不通过安路用户扫描链。本方案不依赖历史 `EF2_PHY_CONFIG` 私有 IR，不使用 ChipWatcher。**CPU 的 JTAG 不是自动存在的：需要先配置含调试电路的新位流。**

## 基础名词和程序下载原理

| 名词 | 在本项目中的含义 |
| --- | --- |
| TCK / TMS / TDI / TDO | 调试时钟、扫描状态选择、电脑到 CPU 数据、CPU 到电脑数据。它们是物理信号，需要硬件调试器驱动。 |
| TAP | 管理扫描状态和指令选择的 JTAG 电路。不是 FPGA 厂商的配置 TAP，而是本轮生成的 CPU 调试 TAP。 |
| DTM | 把 JTAG 扫描请求转换成调试寄存器读写。 |
| DMI | DTM 和 DM 之间的寄存器访问接口。它不是 SoC 的 Wishbone 总线。 |
| DM | Debug Module，协调 CPU 暂停、继续、寄存器访问和小段调试指令的执行。 |
| hart | RISC-V 的一个硬件执行线程；本项目只有一个。 |
| Program Buffer | DM 中用于暂存调试指令的区域。OpenOCD 让处于调试模式的 CPU 执行 load/store 指令，访问正常 RAM。 |
| PC / dpc / dcsr.step | PC 是当前指令位置；dpc 保存调试恢复位置；单步控制使 CPU 执行一条指令后再次停下。 |
| 硬件 / 软件断点 | 硬件断点由地址匹配触发，本配置有两个；软件断点临时改写 RAM 中的指令，因此不能随意用于只读 BootROM。 |
| ELF / BIN / bit | ELF 含程序地址、代码和符号，适合 GDB；BIN 是字节映像，适合 UART BootROM；bit 定义 FPGA 电路，不能混用。 |

**写 RAM 不要求 DM 自带独立 Wishbone 主端口。**本配置没有 System Bus Access，使用标准 Program Buffer：OpenOCD 通过 DMI 设置寄存器和调试指令，CPU 在调试模式下通过已有数据 Wishbone 写 RAM。普通应用暂不执行，下载后再设置 PC 并继续。因此新配置明确使用 `riscv set_mem_access progbuf`。

## 实现配置

- CPU 生成配置：`rtl/cpu/GenDebugCpu.scala`；采用上游 `EmbeddedRiscvJtag` 和特权调试 CSR，不用旧 `DebugPlugin` 私有协议。
- 固定 VexRiscv 修订：`baf7dc82f855eddaf5b0a20a6802c526f127e38a`，SpinalHDL 1.13.0、Scala 2.12.18、sbt 1.6.0、Java 17。
- RV32IM、4 KiB 指令缓存、无数据缓存、静态物理地址转换、指令/数据 Wishbone；两个硬件触发器。
- TAP IR 长度 5，IDCODE `0x10002fff`，DTM version=1、DMI 地址 7 位、idle=7；单 hart、datacount=1、progbufsize=2。
- IDCODE 是上游示例默认值，OpenOCD 会显示厂商码 `0x7ff (<invalid>)`；不是安路芯片 ID，也没有宣称是正式注册的产品 ID。
- `zeroBoot` 定义通用寄存器初值；生成脚本为固定上游补上 TSELECT 选择寄存器 `init(0)`，避免调试器第一次枚举触发器时读到不确定值。修改只作用于本地 `build/deps` 副本。
- CPU 和外设可由 SW2 或 DM 的 `ndmreset` 复位；DM 不跟随这些复位，RAM 内容保留。上电复位才复位 DM。重新配置 FPGA或掉电不保证 RAM 保留。
- 仍是 8 KiB ROM `0x20000000..0x20001fff`、64 KiB RAM `0x80000000..0x8000ffff`、UART `0x40001000`。地址译码和实体 BRAM 没有缩小。

用户提供的 `riscv-debug-spec-0.13.0797ec1.pdf` 是 **2017-03-17 的 0.13 草案**，封面明确提示不是最终标准。用它理解 TAP/DTM/DMI/DM、halt/resume 和 Program Buffer；实现采用上述固定上游，兼容当前 OpenOCD 的标准 `riscv` target，不把旧草案全部寄存器字段当成最终定义，也不宣称通过完整规范一致性测试。

## 已有证据

以下均连接真实生成的 CPU RTL 和功能 BRAM 模型，通过实际 JTAG 引脚扫描，**不是软件伪造的 DMI 返回值**。TB 只为首次响应前未定义的 DTM 响应缓存选择合法初值；随后未知 TDO 会使测试失败。

| 检查 | 结果和本地证据 |
| --- | --- |
| 标准 OpenOCD 探测、RAM bank 边界和最后一字 | 通过；`build/debug/openocd_validation.log`。 |
| 逐指令单步 | PC 为 `0x80000004/08/0c`，a0 为 1、3，store 写入 3；不是只观察 PC。 |
| reset halt 和硬件断点 | 调试连接保留，RAM 标记保留，命中 `0x80000008`。 |
| GDB ELF 和 C 调试 | 下载 132 字节示例，`.text/.data` 比较相同；命中 `debug_add/debug_done`，`stepi` 前进，`result=9`、`initialized=7`；2026-10-15 又通过软件断点和 C 源码 `step`（result=7）；`gdb_validation.log`。 |
| 完整 64 KiB JTAG 传输 | 65536 字节非均匀图案下载、verify、dump，再由 Python 逐字节比较；`download_validation.log` 和 `ram-readback.bin`。 |
| 大程序 ELF | 原 Stage3 app A 的 ELF 下载及回读验证通过，软件 BIN 为 42424 字节；没有在这项测试中宣称应用运行或串口输出通过。 |
| 同地址指令替换 | 不复位，先执行 `addi a0,zero,1`，再替换为 `addi a0,zero,9`，执行结果为 9；标准调试器缓存维护有效。 |
| 新 CPU BootROM 串口启动 | 115200 的真实 UART 线输出 `BOOT UART 64K`，板载复位后再次输出；`uart_boot_validation.log`。没有完整新 CPU UART 大应用传输的结论。 |
| FPGA 实现 | TD 完成综合、布局布线、位流；0 setup / 0 hold，CPU 40ns、JTAG 1000ns；`stage3_debug.timing`。不等于实板调试成功。 |

2026-10-14 的全 RAM 图案与读回 SHA256 相同：`92637c8cb225bd128b795e12c87eb7a42d069e0fb0b9f4ffeee185770f5312b9`。对应调试位流 SHA256：`40e478aac0ab25fa60b0374caec63a211399f76c813c6ccefad8a1e9f05cde20`；重新构建的指纹可能不同，应以新日志为准。

2026-10-15 最终构建门禁复验通过，当前 `stage3_debug.bit` SHA256 为 `72c1b6fb67ef636d8d75a0c900883e0cef2634599478af795a1f4ada64661bed`，仍为 0 setup/hold。旧位流已保留为带时间戳的 previous 文件，不覆盖历史证据。

2026-10-15 03:55（北京时间）完整仿真套件重新通过，命令为 `run_debug_validation.ps1 -Test all -Timeout 7200`，退出码为 0。`simulation_validation.json` 的 core、gdb、download 全部 passed，`mode=simulation`、`full_suite_passed=true`；本次图案/读回均为 65536 字节，SHA256 与上述全 RAM 图案一致。36 项主机 Python 测试也通过，包含硬件确认门禁、预览不连接、仿真/实板分离及失败记录/清理。所有本次仿真进程已退出；这些仍不是实板证据。

资源报告：3383/4480 LUT（75.51%），1848/4480 寄存器；10/12 个 9K BRAM，6/6 个 32K、1/1 个 128K、1/1 个 256K 存储原语。JTAG 与系统是异步时钟域，官方 DTM 使用同步后的 toggle 握手和稳定载荷。时序约束只划分这两类时钟；TMS/TDI 按 TCK 下降沿发送、上升沿采样。没有用空对象或全局 false-path 消除违例。实板初始速度 100 kHz，不超过当前约束的 1 MHz。

`verify_image` 曾提示没有工作区，因而不能在目标 RAM 执行加速 CRC；它退回内存回读比较。测试刻意不预留/覆盖被测 RAM 作工作区，完整 dump 的 Python 比较另外证实了字节一致。日志中的仿真传输速率不是硬件 JTAG 性能指标。

## 不接板的复现

从项目根目录运行；本机工具默认路径已在脚本中设置。其他电脑需 Java 17、Python、Icarus、RISC-V GCC/GDB、支持 RISC-V 的 OpenOCD 和 TD；可用 `SOC_JAVA`/`JAVA_HOME`、`SOC_PYTHON`、`IVERILOG`、`VVP`、`RISCV_TOOLCHAIN`、`RISCV_GDB`、`OPENOCD`、`TD_EXECUTABLE` 覆盖。

```powershell
Set-Location 'D:\demo14_vexriscv_stage1_resource_safe_fixed'
.\script\bootstrap_debug_cpu.ps1
.\script\build_debug_cpu.ps1
.\script\build_stage3_firmware.ps1
.\script\build_debug_firmware.ps1
.\script\run_debug_sim.ps1 -CompileOnly
.\script\run_debug_validation.ps1 -Test core
.\script\run_debug_validation.ps1 -Test gdb
.\script\run_debug_validation.ps1 -Test download
.\script\run_debug_sim.ps1 -Test uart
.\script\build_debug_td.ps1
```

bootstrap 从固定 URL 下载源码/JAR 并检查 SHA256，sbt 第一次还要下载依赖。有代理时设置 `HTTPS_PROXY`；依赖及缓存保留于 `build/deps`。`build_debug_td.ps1` 只构建，不配置板卡；旧成功位流会移到带时间戳的 previous 文件，只有本次新报告和位流存在且时序通过才产生 `stage3_debug.bit`。

OpenOCD + 仿真仅监听本机，使用端口 9824/3333/6666/4444；重复启动前会检查占用，结束后关闭自己创建的进程。完整 RAM 扫描在本机约需数十分钟，不是卡死；超时可设 `-Timeout 7200`。不要同时跑多套 JTAG 测试。TD 专用 CPU 副本定义 `SYNTHESIS` 以排除 `$urandom` 仿真代码；功能仿真使用原始生成 RTL。

## 自动验收和证据记录

同一个入口默认仍是 **仿真**；只有明确传入 `-Adapter` 才选择实板。以下预览可在没有硬件时运行，只显示命令、不启动 OpenOCD、不写目标 RAM，也不产生“通过”的实板报告：

```powershell
.\script\run_debug_validation.ps1 -Adapter jlink -PlanOnly
```

未来已经配置新位流、确认型号和 H3 接线后，先关闭手动启动的 OpenOCD，再执行实板自动验收。它会复位/暂停 CPU 并覆盖原 RAM 内容，**不是只读探测**，必须明确确认；不会配置 FPGA 或擦写 Flash：

```powershell
# 仅在有 J-Link 硬件并核对接线后执行，不是现在必须运行的命令。
.\script\run_debug_validation.ps1 -Adapter jlink -Test all -ConfirmRamOverwrite
# 支持 JTAG 的 CMSIS-DAP 用 -Adapter cmsis-dap；不要仅凭 USB 接口名称判断能力。
```

实板每次调用独立保存到 `build/debug/hardware/<时间戳>/`，包括 OpenOCD/GDB 日志、完整 RAM 图案/读回，以及 `hardware_validation.json`。报告记录输入文件 SHA256、实际命令、开始/结束时间、各项状态。失败、超时或中断不能留下整体 passed；仅运行 core 也不能得到 `full_suite_passed=true`。本地 `.bit` 指纹不是设备上当前位流的证明，配置日志和接线仍须另行确认；自动报告不会擅自把项目目标标记完成。

仿真仍写 `build/debug/simulation_validation.json`，其中 mode 明确为 simulation，记录本次选择的检查而不是冒充历史全部测试。实板报告不会引用仿真日志。测试会清理自己启动的进程；全容量检查完成后 RAM 已被测试/示例改写，如需恢复 UART 下载应复位回 BootROM，再重新上传应用。

当前只验证了预览/确认门禁、失败清理等主机单元测试和真实 RTL 的共用流程，**实板分支本身未实测**。

## 待有调试器后的接线

需要支持 **JTAG 和 3.3 V**、能由 OpenOCD 驱动的硬件。已有模板是 J-Link 和支持 JTAG 的 CMSIS-DAP；**SWD-only 的 DAP 不可用**。FT2232 类也可，但要根据实际型号、通道和电路确认布局，不能猜一份万能配置。购买前确认上述能力。

| 调试器信号 | FPGA 封装引脚 | PotatoPie V3.0 H3 排针位置 |
| --- | --- | --- |
| TCK | P49，时钟可用普通 I/O | 55 |
| TMS | P38 | 45 |
| TDI，调试器输出 | P39 | 46 |
| TDO，调试器输入 | P40 | 47 |
| GND | 共地 | 57，亦可用 2/4/6 |
| VTref | 板卡 3.3 V 电平参考 | 59/60，亦可用 1/3/5 |

依据本机 `D:\PotatoPie V3.0\原理图\PotatoPie V3.0.pdf` 的 H3 网络标注，配合 `constraints/debug.adc`。H3 位置编号不是 FPGA 的 Pxx 引脚编号；接线前按实际丝印、原理图确认方向，断电接线。**不要接到 H2 的 FPGA 配置 JTAG 1..4；不要给普通 I/O 输入 5 V。VTref 是参考输入，不是要求由调试器给整板供电。**本设计没有独立 TRST/SRST 引脚，TMS 复位 TAP，OpenOCD 通过 DM 复位 CPU。

H3 的 3.3 V 电源针不能单独证明相关 I/O bank 当前也使用 3.3 V。接线前还需核对板卡供电选择和相关 VCCIO 的实际电压；板卡若有改动，不能仅凭默认原理图假定电平匹配。

## 实板待验收步骤

本节是未来操作，不是已经完成的记录。

1. 确认独立调试器型号及 3.3 V 接线；先只配置易失性逻辑，不改 Flash。
2. 通过 AL-Link Mini 配置新电路，随后独立调试器连接 H3。不要把原 UART 位流当作带标准调试模块的位流。
3. OpenOCD 探测 IDCODE、hart 和 RAM，然后执行小程序 halt/resume/step、reset halt。
4. GDB 下载 ELF、硬件及软件断点、`stepi`/源码 `step`、寄存器和变量检查。
5. 使用保存完整日志的测试完成 64 KiB 回读、大程序下载、复位和换程序，补录硬件验收后才标记总目标完成。

配置电路会改变板卡当前状态；以下命令 **只在准备好硬件后执行**：

```powershell
& 'D:\TD_5.6.5_Release_119.222\bin\td_commands_prompt.exe' .\script\configure_debug_fpga.tcl
$ocd = 'D:\risc-v\toolchain\jtag\xpack-openocd-0.12.0-7\bin\openocd.exe'
& $ocd -f .\script\openocd\board-jlink.cfg -c 'init; halt'
# 若实物是支持 JTAG 的 CMSIS-DAP，改用 board-cmsis-dap.cfg。
```

另一终端打开 GDB：

```powershell
& 'D:\risc-v\toolchain\xpack-riscv-none-elf-gcc-15.2.0-1\bin\riscv-none-elf-gdb.exe' .\build\debug\debug_demo.elf
```

```gdb
target extended-remote localhost:3333
monitor reset halt
load
compare-sections
set $pc = _start
hbreak debug_add
continue
stepi
info registers
print result
```

调试示例链接时保留顶部 4 KiB 栈，代码/数据/BSS 必须在剩余 60 KiB 内。完整 64 KiB 图案只用于暂停 CPU 后测试容量，不是允许 C 应用占满 RAM 后再额外使用栈。连接的调试器能够改写程序和内存，本项目没有调试鉴权，不用于有保密要求的产品。
