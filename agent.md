# 项目进度与接手说明

最后整理：2026-10-15；UART 实板验收日期：2026-10-13。目标板卡为安路 EF2L45LG144B，配置下载器为 AL-Link Mini；串口测试使用 COM3、115200 8N1。以下记录的是已完成的测试，不代表板卡此刻仍连接、COM3 此刻仍空闲。独立 CPU JTAG 调试尚未实板验收。

## 仓库与目录

公开仓库：https://github.com/yuanyuan284/RISC-V-SoC 。目录已按 `rtl/`（电路）、`fw/`（固件）、`tb/`（测试）、`script/`（构建及上传）、`constraints/`（约束）、`docs/`（文档）整理。Stage 3 是当前主线，Stage 1/2 在对应子目录保留为历史实验。

全部构建输出和历史日志在本地 `build/`，由 `.gitignore` 排除，不随源码提交；旧产物不会因为这次整理而被删除。TD 工程和 UART 适配副本由 `script/prepare_td_project.py` 从源码重新生成，不依赖历史 TD run 文件。根 `README.md` 是当前入口，含架构图、依赖、构建、仿真及板测命令。

## 当前结论

### 当前目标：独立 RISC-V JTAG，尚未完成实板验收

最新目标是在 CPU 中实现标准 RISC-V 调试 TAP，四根 JTAG 信号通过 FPGA **普通 I/O** 引出，不走安路配置 TAP/用户扫描链；下载软件到已有 **64 KiB RAM**，支持暂停、继续和单步。使用上游 `EmbeddedRiscvJtag`、特权调试 CSR 和标准 OpenOCD `riscv` target，不是历史 69 位私有加载器，也不使用 ChipWatcher。

| 项目 | 当前证据 |
| --- | --- |
| 电路 | `GenDebugCpu.scala` 生成 RV32IM、4 KiB Icache、无 Dcache、两个硬件触发器；`stage3_debug_top.v` 保留 8 KiB ROM、64 KiB RAM、UART 和 Wishbone。DM 与 CPU 复位分开。 |
| OpenOCD 仿真 | 实际 JTAG 引脚扫描及真实 CPU/BRAM 模型下完成探测、所有 RAM bank 边界、寄存器读写、三条指令单步、store 效果、reset halt 保留 RAM、硬件断点。 |
| GDB 仿真 | ELF 下载及 `.text/.data` 比较、C 函数硬件断点、`stepi`、变量 `result=9/initialized=7` 通过；2026-10-15 补验软件断点和 C 源码 `step`（result=7）也通过。 |
| 64 KiB 下载 | 全 65536 字节非均匀图案通过 JTAG 下载、verify、dump，Python 逐字节读回比较通过；两文件 SHA256 相同。 |
| 大应用和重载 | 原 app A（BIN 42424B）的 ELF 下载/回读验证通过；同地址代码从 a0=1 改成 a0=9、不复位后执行新结果通过。没有把这项检查当成大应用运行通过。 |
| UART 回归 | 新调试 CPU 以真实 115200 UART 线输出 BootROM 横幅，board reset 后再次输出，通过；不代表新 CPU 的完整 UART 大应用传输已验证。 |
| TD | 综合、布局布线、位流生成通过；CPU 25 MHz、JTAG 1 MHz 约束下 0 setup / 0 hold。约 75.51% LUT，64 KiB RAM 未缩减。 |
| 实板 | **用户再次确认暂时没有独立 USB-JTAG 调试器，未配置新位流、未实测接线或 JTAG 下载/单步。离线准备已完成，实板阶段等待外部硬件，总目标未完成。** |

主要日志：`build/debug/openocd_validation.log`、`gdb_validation.log`、`download_validation.log`、`uart_boot_validation.log`、`td_flow.log`；时序和资源为 `stage3_debug.timing`、`stage3_debug_phy.area`。2026-10-14 全 RAM 图案/读回 SHA256：`92637c8cb225bd128b795e12c87eb7a42d069e0fb0b9f4ffeee185770f5312b9`。这些是离线证据，不能套用为实板证明。

2026-10-15 收尾复验：28 项 Python 测试通过（新增调试/原 UART 工程分离及 SYNTHESIS 副本检查）；调试 PowerShell 脚本语法通过；最终 `run_debug_validation.ps1 -Test core` 完整通过并正常退出。TD 新产物门禁复验通过，当前调试位流 SHA256：`72c1b6fb67ef636d8d75a0c900883e0cef2634599478af795a1f4ada64661bed`。原 UART TD 工程已重新生成，未被调试工程覆盖。本轮启动的仿真、OpenOCD/GDB 和 TD 流程均已结束。Python 测试曾因沙箱临时目录权限失败，改用本地 `build/test-temp` 后全部通过，未把权限错误算作功能通过。

2026-10-15 03:55（北京时间）完整套件复验结束：`run_debug_validation.ps1 -Test all -Timeout 7200` 退出码为 0。`build/debug/simulation_validation.json` 明确记录 `mode=simulation`，core、gdb、download 均为 passed，`full_suite_passed=true`。本次覆盖指令/源码单步、软硬件断点、完整 65536 字节下载及逐字节读回、大应用 ELF 校验、同地址换程序后的指令缓存检查；图案和读回 SHA256 均为 `92637c8cb225bd128b795e12c87eb7a42d069e0fb0b9f4ffeee185770f5312b9`。本次仿真进程已退出，未执行实板分支。

同日继续时进行了只读 USB 设备核查：发现 AL-Link Mini（VID 336C/PID 1002）和 USB Serial Converter（VID 0403/PID 6001）；未识别到独立 JTAG 调试器。一个名称不明的复合设备经总线描述确认是 MCHOSE K99 V3 键盘。当前无 `build/debug/hardware` 验收目录。设备枚举不证明板上接线、供电或当前位流正确；没有连接 OpenOCD 实板会话、打开 COM3 或改动驱动。下一步仍需用户确认独立调试器型号。

用户随后再次答复“暂时还没有”独立调试器；本次恢复后连续三轮仍受同一硬件条件限制，离线准备已无必需的未完成项，因此目标标记为 blocked（等待硬件），不标记 complete。收到调试器具体型号并确认供电/接线后再恢复实板验收；不自动反复跑仿真或尝试现有 AL-Link 的未知调试协议。

配置位流仍可由 AL-Link Mini 完成；CPU 调试需要另外支持 JTAG/3.3 V/OpenOCD 的适配器。已写 J-Link 和支持 JTAG 的 CMSIS-DAP 配置模板；SWD-only 不可用。H3 接线：TCK=55/P49、TMS=45/P38、TDI=46/P39、TDO=47/P40、GND=57、VTref=59/60（3.3 V）；不要接到 H2 的 FPGA 配置 JTAG。接线方向需按实际丝印核实。

实板自动验收入口也已准备：`run_debug_validation.ps1 -Adapter jlink -Test all -ConfirmRamOverwrite`（仅在硬件/接线/配置准备好后运行），或使用支持 JTAG 的 `cmsis-dap`。不传 Adapter 默认仿真；`-PlanOnly` 只预览且不启动连接。实板报告使用独立 `build/debug/hardware/<时间戳>/hardware_validation.json`，记录命令、输入指纹、逐项状态和失败原因；不把仿真当硬件，也不因单项通过就记录完整套件通过。没有执行硬件分支。新增门禁/失败清理单元测试后，当前 Python 测试共 36 项通过。

完整原理、工具、接线、电压限制、复现和实板待验收步骤见 `docs/stage3/JTAG_DEBUG.md`。从项目根目录构建后运行 `script/run_debug_validation.ps1 -Test core/gdb/download`（参数每次选一个，或 `all`）；完整 RAM 扫描约需数十分钟。GitHub 同步范围为源码、约束、固件示例、脚本、测试和文档；输出、完整日志和依赖均在忽略的 `build/`，仍只保留本地。源码同步不改变实板尚未验收的结论。

### 2026-10-14 仓库整理验证

在不带旧 `build/` 的独立源码副本中重新构建 Stage 2/3 固件，Stage 3 BootROM 和两份应用的 BIN SHA256 均与 2026-10-13 实板版本一致。26 项 Python 测试、全 ROM/RAM 仿真、JTAG 加载器仿真和 Stage 2 JTAG SoC 仿真通过；Stage 3 UART testbench 编译通过，长 UART 仿真没有重新计为通过。TD 完成 Stage 3 综合、布局布线和位流生成，时序为 0 setup / 0 hold 错误。本次没有配置板卡或操作 COM3。

沙箱内 Icarus 在部分编译任务中以访问冲突退出（`0xC0000005`）；同一源码在沙箱外通过编译与上述离线仿真，因此记录为工具运行环境问题。生成配置 `rtl/cpu/GenVexRiscv.scala`、上游许可证及配套完整 CPU RTL 的固定版本/SHA256 见 `rtl/cpu/README.md`；生成 CPU 仍只作为本地构建输入。

前一轮 UART 目标已经完成：RV32 C 经交叉 GCC 生成 ELF、objcopy 生成 BIN/Intel HEX，由 8 KiB BootROM 从 UART 接收 BIN 写入 64 KiB RAM、CRC32 正确后跳 RAM，并由 newlib `printf` 完成真正格式化输出。**Stage 3 的 app A、app B 均已实板通过：各42424B BIN 上传成功、CRC 正确，分别输出 `APP 1`、`APP 2`，以及 `FLOAT=3.25`、`errors=0` 和 `STAGE3 PASS`。**固件产物校验、TD 时序和完整内存功能仿真也已通过。该历史目标已完成，不等于新的独立 JTAG 调试目标完成。Stage 2 小容量 UART 换程序和自定义 JTAG 加载器保留为历史实验。

| Stage 3 项目 | 2026-10-13 的证据与边界 |
| --- | --- |
| 存储和位流 | `stage3_uart_phy.area`：1x256K、1x128K、6x32K 原语组成 64 KiB RAM/8 KiB ROM，CPU 另用 10 个9K BRAM；`stage3_uart.timing`：0 setup/hold 错误。`stage3_uart.bit` 已完成仅易失性配置及 app A/B 实板验证，不覆盖 Stage 2 位流。SHA256：`7dbaef7ebca686504bd38d883afb5a27c88330588274da6c4d94e2ce5b637cf7`。 |
| 软件产物 | `build_stage3_firmware.ps1` 生成 BootROM 和两应用的 ELF、BIN、Intel HEX。BootROM BIN 580B；应用各42424B。`verify_stage3_artifacts.py` 比较 ELF 装载字节、BIN、Intel HEX、RTL word HEX、BootROM INIT 及 UART 帧，核对入口、BSS、堆栈和 libc 符号。 |
| BootROM 协议 | 新横幅 `BOOT UART 64K\r\n`；固定入口 `0x80000000`；最多61440B（顶端4KiB栈），每字节 ACK，帧头/CRC 错误拒绝，CRC 正确后跳 RAM。BootROM 不解析 ELF，下载的是 BIN。 |
| 格式化输出 | 应用链接 newlib nano `_printf_float`、`printf`、`snprintf`、`_write`。实板 COM3 分别输出 `id=1`、`id=2`，以及 `signed=-42 hex=001234ab str=form %`、`FLOAT=3.25`，且 `.data=1234`、`.bss=0`、RAM 测试 `errors=0`，均与应用预期一致。 |
| 测试 | 13 项新旧上传器单元测试通过；功能 BRAM 模型下全8KiB ROM、全64KiB RAM、16种byte enable、物理bank边界及reset测试通过。app A、app B 均实板下载/执行成功；六类错误帧拒绝后有效BIN执行成功。两项真实UART线 Icarus 长仿真因耗时终止，未完成，不计通过；标准波特率协议功能已由实板覆盖。 |

第二份BIN及六类错误帧的实板日志分别为 `build/stage3/app_b_hardware.log`、`build/stage3/protocol_hardware.log`；配置日志为 `configure_stage3.log`、`configure_stage3_b.log`、`configure_stage3_protocol.log`，均位于 `build/stage3`。这些日志只保留本地。app A 输出依据当时工具会话保存于验收记录，未另存原始串口日志。实板记录见 `docs/stage3/HARDWARE_VALIDATION.md`，复现见 `docs/stage3/README.md`。新克隆需通过 `python -m pip install -r requirements.txt` 安装 `pyserial`；原本安装的本地副本在 `build/deps/pyserial`，上传器仍可加载。

## 当前容量与验证边界

| 地址范围 | 用途 |
| --- | --- |
| `0x20000000..0x20001fff` | 8 KiB BootROM，CPU 复位入口为 `0x20000000`。 |
| `0x80000000..0x8000efff` | 应用、数据、BSS、堆及测试区；BIN 上限61440B（60 KiB），入口固定 `0x80000000`。 |
| `0x8000f000..0x8000ffff` | 顶部4 KiB栈，初始SP为 `0x80010000`。 |
| `0x40001000` 起 | UART寄存器窗口。 |

- 两个42424B应用均实板通过；尚未用最大60KiB BIN做实板传输测试。
- 全64KiB RAM、全8KiB ROM的逐字覆盖来自功能模型；实板应用覆盖代码/数据、上部14KiB测试区与栈，不能称为实板全地址穷举。
- 测试应用链接脚本把 `0x8000b800..0x8000efff` 留为14KiB测试区。换普通C程序需核对代码、BSS、堆、栈布局；BIN尺寸合规不代表全部运行时内存合规。
- 本轮以相同位流文件重新配置来复位，没有烧写Flash。Stage 3仅按SW2换载尚未单独实测；Stage 2有历史实测，不能直接套用。
- 两项Icarus真实UART线长仿真因耗时终止，未完成，不计通过；标准115200波特率的下载、错误恢复和格式化执行已有实板证据。
- 收尾时已结束仿真、TD与串口测试。最后一次实测后，Stage 3硬件运行的是144B短应用，用于证明错误帧后的恢复；板卡后来是否复位或断电需另行确认。

## 当前后续事项

当前必需的未完成项是独立 CPU JTAG **实板验收**：取得支持 JTAG 的调试器，确认 3.3 V H3 接线及相关 I/O bank 的实际供电、配置 `stage3_debug.bit`，然后验证标准 OpenOCD/GDB 的 RAM 下载、单步、断点、复位和换程序并保存日志。离线设计、完整仿真和验收入口已准备好；等待调试器和接线条件后继续，不重复跑相同离线测试来代替实板验收。不重复占用 COM3，不盲试安路用户扫描 IR。UART-only 的 SW2 换载和最大 BIN 演示是历史路线的补充测试，不代替本轮验收。

## Stage 2 历史记录

| 项目 | 进度与证据 |
| --- | --- |
| UART 实板运行 | 同一个 `build/stage2/stage2_uart.bit` 先后运行 app A 和 app B。仅按 SW2 使 app B 复位回 BootROM 后，又上传并运行 app A，期间没有重新配置 FPGA。另一次实板测试直接上传 `app_b.elf`，板卡输出 `APP B: same FPGA, new C!`。 |
| UART 位流 | TD 完成布局布线，时序报告中 setup/hold 错误均为 0。SHA256：`a261d76379c6f04fd18d1ac7db1de99a0777c38b7642487b471b511d473b32bc`。这是目前应保留的已验证位流。 |
| UART 协议 | BootROM 在复位后发送 `BOOT UART\r\n`。上位机发送 `RV32` 文件头、CRC32 和位于 `0x80000000` 的程序映像；程序最多 896 字节。`script/uart_upload.py` 接受 `.bin` 或 `.elf`，但 ELF 是由上位机校验并转换的，BootROM 本身不解析 ELF。 |
| 自定义 JTAG 加载器 | 完整 SoC 的 RTL 仿真通过 69 位私有协议加载、回读并运行 app A 和 app B。`build/stage2/stage2_jtag.bit` 的 TD 时序报告中 setup/hold 错误均为 0，但**从未下载到实板**。SHA256：`d5661611a667ad9fe9b419bfac18dcc586511a5bbf2c074a09a0f0018d1aad30`。 |
| JTAG 物理连接 | 只读 IDCODE 检查通过，读数为 `0x03004C37`。只读 USERCODE 为 `0x00190000`，与 UART 位流生成日志中的 `0x007E0000` 不同，因此不能凭 USERCODE 判断当前运行哪份位流。此前按 SW2 后，COM3 收到 `BOOT UART\r\n`。该检查没有配置 FPGA，也没有写 Flash。 |
| ChipWatcher | 最小计数器工程复现了 TD 插入逻辑中的 `jrstn` 到内部 TAP 复位寄存器 removal 时序违例，slack 为 -2.145 ns。带 ChipWatcher 的完整 UART SoC 也有同类违例，slack 为 -2.048 ns。目前没有经过验证的时序例外，也没有可安全下载的 ChipWatcher 位流。 |

## JTAG 扩展的历史阻碍

1. 现有资料没有给出 EF2 用户扫描链的 IR 指令值，也没有说明 `EF2_PHY_CONFIG.jscanen[1:0]`、`jtdo[1:0]` 的选择方式和 `jtag8_ipa/ipb` 的含义。尝试过的 F0、02、03、10、11 均未返回加载器签名。另一封装的官方 EF2L45 BSDL 将 `0x03` 定义为 INTEST、`0x10` 定义为 PROG_USERCODE，不能继续盲猜指令。
2. TD 5.6.119222 的 ChipWatcher 产生上述 removal 时序违例。曾有空对象的 `set_false_path` 让错误消失，但它可能屏蔽无关路径，结果无效；**不要加入这种约束**。需要安路确认违例是否真实，以及官方支持的修复方法或精确作用域的时序例外。

已查阅 `D:\4.EF2 Family` 中的资料及 TD 自带的 `doc/TD_User_Guide_V5.6.pdf`：`SUG401` 讲内置 Cortex-M3 的 Keil/J-Link 调试；`TN401`、`TN424` 讲 JTAG 配置、ID 检查和 Flash 烧录。这些资料都没有定义本项目自建 VexRiscv 加载器所需的用户扫描链 IR。TD 的 `sim_release/ef2/ef2_phy_config.v` 只有端口声明，没有 IR 映射。官网搜索服务调用失败；先前直接查看官网也未找到映射。**这表示当前资料不足，不等于器件没有该功能。**

## 历史安路用户扫描链路线的步骤（非当前方案）

以下只用于回顾旧路线；新独立 CPU TAP 不需要等待这些厂商资料。

1. 向安路技术支持索取 EF2L45LG144B 的用户扫描链 IR 指令、链路选择和 TDO 协议，并询问 `jtag8_ipa/ipb` 的含义；同时提供匹配的 IDCODE 和 TD 版本。另请确认 USERCODE 反映的是当前 SRAM 位流、内部 Flash，还是独立寄存器。
2. 将最小 ChipWatcher 工程及报告交给安路，确认 `jrstn` removal 检查是否为真实硬件要求，以及官方处理方法。详细路径、复现命令和问题文字见 `docs/stage2/CHIPWATCHER_TIMING.md`。
3. 得到官方用户扫描链定义后，先在明确配置了 JTAG 加载器位流的板卡上进行只读签名测试；签名正确后，才考虑写 RAM 和上传 ELF。始终保留已验证的 UART 恢复路径。

**不要运行** `script/bringup_jtag.tcl`、`script/probe_loader.tcl`、`script/probe_candidates.tcl` 或 `script/program_ram.tcl`：这些入口已被故意禁用。不要下载 `build/stage2/stage2_uart_chipwatch.invalid_bit` 或其他 `*.invalid_bit` 文件。探索 JTAG 时不要烧写 Flash。

## 关键文件与复现

- `docs/stage3/JTAG_DEBUG.md`：当前独立 CPU JTAG 调试原理、证据、接线和验收。
- `rtl/cpu/GenDebugCpu.scala`、`rtl/stage3/stage3_debug_top.v`：标准调试 CPU 生成配置和独立 TAP SoC。
- `script/bootstrap_debug_cpu.ps1`、`build_debug_cpu.ps1`、`build_debug_td.ps1`：固定依赖与离线硬件构建。
- `script/run_debug_sim.ps1`、`run_debug_validation.ps1`：实际 RTL + OpenOCD/GDB 验证入口。
- `docs/stage3/README.md`：当前版本的构建、上传命令与容量限制。
- `docs/stage3/HARDWARE_VALIDATION.md`：app A/B 和六类错误帧的实板验收证据。
- `docs/report.md`：中文原理解释与答辩准备，已更新Stage 3成果。
- `rtl/stage3/stage3_top.v`、`stage3_memory.v`：CPU、Wishbone仲裁、地址译码与片上存储。
- `fw/stage3/bootrom.c`、`app.c`、`app.ld`、`syscalls.c`：BootROM、格式化应用、链接布局及newlib UART后端。
- `script/build_stage3_firmware.ps1`、`verify_stage3_artifacts.py`：交叉编译、objcopy转换及产物一致性检查。
- `script/build_stage3_td.ps1`、`configure_stage3_fpga.tcl`：硬件构建及仅易失性配置。
- `script/uart_upload_stage3.py`、`validate_stage3_hardware.py`：当前BIN上传及错误恢复实测。
- `script/run_stage3_sim.ps1 -Test memory`：已通过的全ROM/RAM功能测试。

从项目根目录 `D:\demo14_vexriscv_stage1_resource_safe_fixed` 运行：

```powershell
.\script\build_stage3_firmware.ps1
python .\script\verify_stage3_artifacts.py
.\script\run_stage3_sim.ps1 -Test memory
.\script\build_stage3_td.ps1
python .\script\uart_upload_stage3.py .\build\stage3\app_b.bin --port COM3 --expect-text 'STAGE3 PASS'
```

最后一条需独占COM3并等待新的 `BOOT UART 64K` 横幅。在另一终端配置Stage 3硬件可用：

```powershell
& 'D:\TD_5.6.5_Release_119.222\bin\td_commands_prompt.exe' .\script\configure_stage3_fpga.tcl
```

若硬件已经配置好，也可在上传器监听后按下并松开SW2；此Stage 3操作路径仍待单独补测。Stage 3下载的是objcopy导出的BIN，不使用旧上传器的896B限制。

以下是旧版复现入口，只用于回看Stage 2历史验证：

- `docs/stage2/README.md`：Stage 2 设计、实板验证历史和 UART 协议。
- `docs/stage2/CHIPWATCHER_TIMING.md`：ChipWatcher 时序问题的最小复现及待询问安路的问题。
- `script/run_stage2_sim.ps1`：离线 UART app A 到 app B 的 RTL 仿真。
- `script/run_stage2_jtag_sim.ps1`：离线 JTAG 加载、回读和 ELF 运行仿真。
- `tb/python/test_uart_upload.py`：上位机 UART 上传器单元测试，运行 `python script/run_tests.py`。
- `script/configure_stage2_fpga.tcl`：将位流配置到 FPGA 易失性逻辑；运行它会改变板卡当前状态。

再次做 Stage 2 UART 实板测试时，应先确认对应旧位流在运行，关闭占用 COM3 的 Tera Term，启动旧上传器并指定预期输出，然后按下并松开 SW2。不要仅凭 USERCODE 判断当前位流。旧版示例：

```powershell
python script\uart_upload.py build\stage2\app_a.elf --port COM3 --expect-text "APP A: UART loaded C!"
```

上传器必须先收到**新一次复位**产生的 `BOOT UART` 横幅才会发送程序；面对 Stage 1 位流或尚未复位回 BootROM 的应用程序，它会拒绝上传。
