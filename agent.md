# 项目进度与接手说明

最后整理：2026-10-19；UART-only 实板验收日期：2026-10-13，FreeRTOS 实板验收日期：2026-10-15，独立 CPU JTAG 完整实板验收日期：2026-10-18。目标板卡为安路 EF2L45LG144B，配置下载器为 AL-Link Mini；串口测试使用 COM3、115200 8N1。以下记录的是已完成的测试，不代表板卡此刻仍连接、COM3 此刻仍空闲。

## 仓库与目录

公开仓库：https://github.com/yuanyuan284/RISC-V-SoC 。目录已按 `rtl/`（电路）、`fw/`（固件）、`tb/`（测试）、`script/`（构建及上传）、`constraints/`（约束）、`docs/`（文档）整理。Stage 3 是当前主线，Stage 1/2 在对应子目录保留为历史实验。

全部构建输出和历史日志在本地 `build/`，由 `.gitignore` 排除，不随源码提交；旧产物不会因为这次整理而被删除。TD 工程和 UART 适配副本由 `script/prepare_td_project.py` 从源码重新生成，不依赖历史 TD run 文件。根 `README.md` 是当前入口，含架构图、依赖、构建、仿真及板测命令。

## 当前结论

### 2026-10-19：Flash 上电启动尚待实现

EF2L45LG144B 片内 Flash 可用于保存 FPGA 配置位流，并在对应启动模式下上电自动加载。项目现有 `configure_stage3_fpga.tcl`、`configure_rtos_fpga.tcl`、`configure_debug_fpga.tcl` 均只通过 AL-Link 配置易失性逻辑；尚无 Flash 烧写、断电重启与自动加载的实板验收记录，不应称为已完成。第一次将位流写入 Flash 仍需配置接口，成功后才可免去每次上电的位流下载。

当前 UART、RTOS 和调试应用都以 RAM 为运行存储，掉电不保留；位流内初始化的 8 KiB BootROM 只负责等待/接收 UART 应用。单独固化现有位流不会使 `HELLO,YUAN!` 或 FreeRTOS 应用在上电后自动运行。若目标是完全脱离电脑上电运行，下一阶段还需设计应用持久化与启动加载路径，并分别验证位流自动配置和应用自动运行。2026-10-18 的 JTAG 全套验收及其日志只证明 SRAM 配置与 RAM 下载/调试，不构成 Flash 验收。

### 2026-10-18：独立 CPU JTAG 完整实板验收通过

用户已有 IoTelic JTAG-USB_V1.0（2018.11.06，主芯片 FT2232HL），USB 枚举为 `15BA:002A / OL5C11FC`，描述符为 Olimex ARM-USB-TINY-H；描述符不证明它与 Olimex 电路相同。两个 USB 接口均已安装 WinUSB，设备状态 OK；AL-Link Mini 仍使用原 ANLOCYUSB 驱动，FT232R 串口驱动未更换。

用户确认五线已接好并要求继续，不再要求接线照片。CK→P49、MS→P38、DI→P39、DO→P40、已测候选 GND→板卡 GND；不交叉 DI/DO。候选地为 DI 同排另一列的那一针，用户报告其到断电 USB 信号地约 3.1 Ω、表笔短接约 1.3 Ω；这不是整列地针认证。3V3/RST 不接。原理图显示 BANK1 默认选择 3.3 V，但未实测本板 VCCIO 或调试器输出电平。

新增 `iotelic-ft2232h.cfg`、`board-iotelic-ft2232h.cfg` 和只识别 TAP 的 `probe-iotelic-tap.cfg`；初始 100 kHz，仅启用 MPSSE AD0/1/3 输出、AD2 输入，其余 FTDI GPIO 不驱动，不照搬 Olimex 的复位/LED 引脚。本模块通道 A 与 CK/DI/DO/MS 的标准 MPSSE 配置已由后续实际扫描、下载和调试通过证明可用，不代表认证所有同名模块的电路。验证入口支持 `-Adapter iotelic-ft2232h`，RAM 覆盖确认门禁保留。42 项主机测试、PlanOnly 和 OpenOCD 不初始化硬件的配置解析通过；主机测试与实板证据分开记录。

17:17 首次用 AL-Link 配置 `build/debug/stage3_debug.bit` 失败，TD 返回 `PRG-9505 USB device open error`、`PRG-9525 Chip validation failed`，退出码 1，日志 `build/debug/configure_iotelic_20261018.log`。该次失败不计通过。用户拔插 AL-Link 下载 USB 后，17:26 重试芯片识别和 SRAM 配置成功，退出码 0，日志 `build/debug/configure_iotelic_20261018-172601.log`。位流 SHA256 仍为 `72c1b6fb67ef636d8d75a0c900883e0cef2634599478af795a1f4ada64661bed`，没有写 Flash。

100 kHz 扫描两次读到 CPU TAP `0x10002fff`，随后枚举出一个 RV32 hart，`datacount=1/progbufsize=2/misa=0x40001100`。探测日志为 `build/debug/tap_iotelic_20261018-172631.log`、`hart_iotelic_20261018-172727.log`。用户明确允许覆盖 RAM 后，执行 `run_debug_validation.ps1 -Adapter iotelic-ft2232h -Test all -ConfirmRamOverwrite -Timeout 3600`，北京时间 17:28:52..17:29:39 退出码 0。

| 本次真实 FPGA 验收 | 结果 |
| --- | --- |
| core | 全部 RAM bank 边界/最后一字、寄存器、三条指令单步及 store 效果、reset halt 保留 RAM、硬件断点通过。 |
| gdb | 132B ELF 下载，`.text/.data` 比较一致，C 函数硬件断点、指令单步、`result=9/initialized=7`、软件断点与 C 源码单步通过。 |
| download | 全 65536B 非均匀图案 JTAG 下载、verify、dump 和 Python 逐字节比较通过；Stage3 app A ELF 下载/回读通过；同地址指令替换后执行新结果 a0=9 通过。大应用仅验证下载/回读，不冒充 UART 输出或应用运行。 |

报告与各项日志：`build/debug/hardware/20261018-172852-821311/`。`hardware_validation.json` 明确为 `mode=hardware/adapter=iotelic-ft2232h/status=passed/full_suite_passed=true`，core、gdb、download 均 passed；图案与读回均为 65536B，SHA256 同为 `92637c8cb225bd128b795e12c87eb7a42d069e0fb0b9f4ffeee185770f5312b9`。报告的 `fpga_configuration=not performed` 表示验收脚本自身不配置电路，实际配置由上述单独 TD 日志证明，不是“整轮未配置”。OpenOCD 无工作区提示后走回读校验，GDB 有宿主编码警告，但所有断言与独立字节比较通过；不宣称无警告运行。

本次独立 JTAG 目标已实现、仿真、TD 和完整实板通过；不等于规范全覆盖认证、高速/长稳测试或 RTOS 与调试模块已合并。收尾 TD/OpenOCD/GDB 进程均已退出，COM3 未打开，Flash 未写；最后一次操作后是独立 JTAG 位流、CPU 暂停、RAM 留有测试内容，未恢复 RTOS/HELLO 应用。掉电会丢失本次易失性配置。以下 2026-10-15“没有调试器/等待硬件”的描述保留为历史记录，该硬件限制现已解除。

### 已验收目标：FreeRTOS，已完成实板验证

因暂时没有独立 JTAG 调试器，转而实现 FreeRTOS 所需的 CPU 陷阱/中断、timer 和外部中断控制器。新增独立 `VexRiscvRtos`/`stage3_rtos_top`，未把旧 UART 或 JTAG CPU 文件替换为 RTOS CPU。官方 FreeRTOS-Kernel V11.1.0 与其 GCC RISC-V port 固定下载到 `build/deps`，不手写调度器。

| 项目 | 2026-10-15 的证据 |
| --- | --- |
| CPU/内存 | RV32IM、25 MHz、4 KiB Icache、无 Dcache；可写 mtvec、ecall/mret、机器模式 CSR。8 KiB ROM / 64 KiB RAM 保留；链接器隔离顶部 4 KiB 主程序/ISR 栈，16 KiB 内核堆包含任务栈。 |
| Timer | CLINT 地址兼容的 64 位 mtime/mtimecmp、msip，直接连接 MTIP/MSIP；1000 Hz tick。独立仿真通过字节掩码、计数回卷、比较和复位。 |
| 外部中断 | 精简双源、单机器上下文 PLIC，UART RX=ID1、事件寄存器=ID2；支持优先级、阈值、pending、claim/complete 和持续电平 gateway。不是完整多核 PLIC。 |
| FreeRTOS | 六个应用任务和 idle；两忙任务验证时间片抢占及 s0..s11 保存，另测嵌套临界区/ecall、5 tick 周期生产者、队列顺序、ISR 通知唤醒。 |
| 完整仿真 | 最新输出 `tick=66 switches=102 queue=14 msip=1 plic=1 uart=1`；真实 CPU、功能 BRAM、UART 线与 IRQ 链路通过。仿真直接初始化 RAM，不冒充 UART 上传。 |
| TD | 0 setup / 0 hold；3138/4480 LUT（70.04%）、1483/4480 寄存器、10/12 BRAM9K，全部大 BRAM 保留原存储容量。 |
| 实板 | AL-Link 易失性配置后，COM3 从新 BootROM 横幅开始上传 15544B BIN，CRC 接受并跳转；`CHECK preemption=1 registers=1 critical=1 queue=1 notify=1` 和 `FREERTOS PASS tick=66 switches=101 queue=14 msip=1 plic=1 uart=0` 通过。随后发送实际 UART 输入，收到 `UART IRQ PASS count=1`。 |
| 持续运行 | 后续三次实板心跳为 tick/queue = 1070/214、2072/415、3074/615。没有把约三秒的观察表述为长期稳定性或实时延迟认证。 |
| 回归 | 40 项 Python 测试通过；CLINT/PLIC 独立 RTL、原完整 8 KiB ROM/64 KiB RAM 测试通过；新 RTOS 工程隔离检查保证不覆盖 UART/JTAG 工程或固件。 |

验收时间为北京时间 2026-10-15 10:40:24..10:45:00，日志为 `build/rtos/hardware_validation.log`、`hardware_validation.json`、`configure_hardware.log`、`simulation.log`、`interrupts.log`、`td_flow.log`。首次仅监听时因尚未复位/配置而未收到横幅，该次超时不计通过；配置新电路后的这次完整验收退出码 0，JSON 为 `mode=hardware/status=passed`。

RTOS 位流 SHA256：`18d181a8813ef9c7c73831a7091b434f216fdb6909ce8e406bf19fc3b35e92fc`；应用 BIN SHA256：`8cbe4fd1375a4171d4cc0b5a7273e739a86722c0953a226219fa22cb66103f98`；CPU RTL SHA256：`60e3373b624741bf98563e623732515bf43d93a33aa06ddb458e8339d60f36e1`。本地位流哈希需结合配置日志与串口运行证据，不单独当设备证明。主程序/ISR 栈顶 `0x80010000`，BSS 末端 `0x80007e10`；代码/数据/BSS 总计 32272B，BIN 不包含 BSS。

2026-10-15 这轮没有写 Flash、改驱动或使用独立调试器；验收后 COM3 已随程序退出释放，当时最后一次配置运行的是 RTOS 电路和应用。随后断电/复位或重新配置的状态需另行确认。RTOS 位流不含独立 JTAG TAP，当时 JTAG 实板目标仍待硬件；2026-10-18 已独立通过。当前 FreeRTOS 目标的实现、仿真、综合和实板运行均已通过；不含软件定时器、低功耗、任意应用或极限负载的承诺。原理/命令见 `docs/stage3/FREERTOS.md`；该轮 GitHub 同步范围为 RTOS 源码、脚本、测试和文档，位流、依赖及完整日志仍保留在本地 `build/`。

### 独立 RISC-V JTAG：离线证据与历史准备

前一目标是在 CPU 中实现标准 RISC-V 调试 TAP，四根 JTAG 信号通过 FPGA **普通 I/O** 引出，不走安路配置 TAP/用户扫描链；下载软件到已有 **64 KiB RAM**，支持暂停、继续和单步。使用上游 `EmbeddedRiscvJtag`、特权调试 CSR 和标准 OpenOCD `riscv` target，不是历史 69 位私有加载器，也不使用 ChipWatcher。

| 项目 | 当前证据 |
| --- | --- |
| 电路 | `GenDebugCpu.scala` 生成 RV32IM、4 KiB Icache、无 Dcache、两个硬件触发器；`stage3_debug_top.v` 保留 8 KiB ROM、64 KiB RAM、UART 和 Wishbone。DM 与 CPU 复位分开。 |
| OpenOCD 仿真 | 实际 JTAG 引脚扫描及真实 CPU/BRAM 模型下完成探测、所有 RAM bank 边界、寄存器读写、三条指令单步、store 效果、reset halt 保留 RAM、硬件断点。 |
| GDB 仿真 | ELF 下载及 `.text/.data` 比较、C 函数硬件断点、`stepi`、变量 `result=9/initialized=7` 通过；2026-10-15 补验软件断点和 C 源码 `step`（result=7）也通过。 |
| 64 KiB 下载 | 全 65536 字节非均匀图案通过 JTAG 下载、verify、dump，Python 逐字节读回比较通过；两文件 SHA256 相同。 |
| 大应用和重载 | 原 app A（BIN 42424B）的 ELF 下载/回读验证通过；同地址代码从 a0=1 改成 a0=9、不复位后执行新结果通过。没有把这项检查当成大应用运行通过。 |
| UART 回归 | 新调试 CPU 以真实 115200 UART 线输出 BootROM 横幅，board reset 后再次输出，通过；不代表新 CPU 的完整 UART 大应用传输已验证。 |
| TD | 综合、布局布线、位流生成通过；CPU 25 MHz、JTAG 1 MHz 约束下 0 setup / 0 hold。约 75.51% LUT，64 KiB RAM 未缩减。 |
| 实板 | **2026-10-18 通过 IoTelic FT2232HL 完整 core/gdb/download 实板验收，含全 64 KiB 读回、指令/源码单步、软硬件断点、复位保留 RAM、换代码后缓存一致性；见本页最新记录。** |

主要日志：`build/debug/openocd_validation.log`、`gdb_validation.log`、`download_validation.log`、`uart_boot_validation.log`、`td_flow.log`；时序和资源为 `stage3_debug.timing`、`stage3_debug_phy.area`。2026-10-14 全 RAM 图案/读回 SHA256：`92637c8cb225bd128b795e12c87eb7a42d069e0fb0b9f4ffeee185770f5312b9`。这些是离线证据，不能套用为实板证明。

2026-10-15 收尾复验：28 项 Python 测试通过（新增调试/原 UART 工程分离及 SYNTHESIS 副本检查）；调试 PowerShell 脚本语法通过；最终 `run_debug_validation.ps1 -Test core` 完整通过并正常退出。TD 新产物门禁复验通过，当前调试位流 SHA256：`72c1b6fb67ef636d8d75a0c900883e0cef2634599478af795a1f4ada64661bed`。原 UART TD 工程已重新生成，未被调试工程覆盖。本轮启动的仿真、OpenOCD/GDB 和 TD 流程均已结束。Python 测试曾因沙箱临时目录权限失败，改用本地 `build/test-temp` 后全部通过，未把权限错误算作功能通过。

2026-10-15 03:55（北京时间）完整套件复验结束：`run_debug_validation.ps1 -Test all -Timeout 7200` 退出码为 0。`build/debug/simulation_validation.json` 明确记录 `mode=simulation`，core、gdb、download 均为 passed，`full_suite_passed=true`。本次覆盖指令/源码单步、软硬件断点、完整 65536 字节下载及逐字节读回、大应用 ELF 校验、同地址换程序后的指令缓存检查；图案和读回 SHA256 均为 `92637c8cb225bd128b795e12c87eb7a42d069e0fb0b9f4ffeee185770f5312b9`。本次仿真进程已退出，未执行实板分支。

同日继续时进行了只读 USB 设备核查：发现 AL-Link Mini（VID 336C/PID 1002）和 USB Serial Converter（VID 0403/PID 6001）；未识别到独立 JTAG 调试器。一个名称不明的复合设备经总线描述确认是 MCHOSE K99 V3 键盘。当前无 `build/debug/hardware` 验收目录。设备枚举不证明板上接线、供电或当前位流正确；没有连接 OpenOCD 实板会话、打开 COM3 或改动驱动。下一步仍需用户确认独立调试器型号。

用户随后再次答复“暂时还没有”独立调试器；本次恢复后连续三轮仍受同一硬件条件限制，离线准备已无必需的未完成项，因此目标标记为 blocked（等待硬件），不标记 complete。收到调试器具体型号并确认供电/接线后再恢复实板验收；不自动反复跑仿真或尝试现有 AL-Link 的未知调试协议。

配置位流仍可由 AL-Link Mini 完成；CPU 调试需要另外支持 JTAG/3.3 V/OpenOCD 的适配器。已写 J-Link 和支持 JTAG 的 CMSIS-DAP 配置模板；SWD-only 不可用。H3 接线：TCK=55/P49、TMS=45/P38、TDI=46/P39、TDO=47/P40、GND=57、VTref=59/60（3.3 V）；不要接到 H2 的 FPGA 配置 JTAG。接线方向需按实际丝印核实。

实板自动验收入口：`run_debug_validation.ps1 -Adapter iotelic-ft2232h -Test all -ConfirmRamOverwrite`（仅在硬件/接线/配置准备好后运行）；另外保留 `jlink` 和支持 JTAG 的 `cmsis-dap` 模板，后二者未由本次硬件验证。不传 Adapter 默认仿真；`-PlanOnly` 只预览且不启动连接。实板报告使用独立 `build/debug/hardware/<时间戳>/hardware_validation.json`，记录命令、输入指纹、逐项状态和失败原因；不把仿真当硬件，也不因单项通过就记录完整套件通过。主机测试现为 42 项通过，完整硬件分支已于 2026-10-18 通过。

完整原理、工具、接线、电压限制、复现和实板验收步骤见 `docs/stage3/JTAG_DEBUG.md`。从项目根目录构建后运行 `script/run_debug_validation.ps1 -Test core/gdb/download`（参数每次选一个，或 `all`）；不传 Adapter 是仿真，完整 RTL RAM 扫描约需数十分钟，不是硬件耗时指标。GitHub 同步范围为源码、约束、固件示例、脚本、测试和文档，包括本次 FTDI 接入和实板验收记录；输出、完整日志和依赖均在忽略的 `build/`，仍只保留本地。

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
- UART-only 的全64KiB RAM、全8KiB ROM逐字覆盖来自功能模型；其历史实板应用覆盖代码/数据、上部14KiB测试区与栈。另有 2026-10-18 独立 JTAG 位流的全64KiB图案下载/逐字节读回实板证据，二者不混用。
- 测试应用链接脚本把 `0x8000b800..0x8000efff` 留为14KiB测试区。换普通C程序需核对代码、BSS、堆、栈布局；BIN尺寸合规不代表全部运行时内存合规。
- 本轮以相同位流文件重新配置来复位，没有烧写Flash。Stage 3仅按SW2换载尚未单独实测；Stage 2有历史实测，不能直接套用。
- 两项Icarus真实UART线长仿真因耗时终止，未完成，不计通过；标准115200波特率的下载、错误恢复和格式化执行已有实板证据。
- 收尾时已结束仿真、TD与串口测试。最后一次实测后，Stage 3硬件运行的是144B短应用，用于证明错误帧后的恢复；板卡后来是否复位或断电需另行确认。

## 当前后续事项

当前 FreeRTOS 与独立 CPU JTAG 两个独立目标均无本次验收范围内的必需未完成项。后续可以扩展 RTOS 与 JTAG 合并、高速和长时间调试、更多外设或应用演示，但不将这些扩展冒充已验证能力。两种 CPU/位流仍分开；历史禁用的安路用户扫描 IR 入口未改。

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

- `docs/stage3/FREERTOS.md`：当前 FreeRTOS 原理、内存/中断布局、完整实板证据和复现。
- `rtl/cpu/GenRtosCpu.scala`、`rtl/stage3/stage3_rtos_top.v`、`rtos_clint.v`、`rtos_plic.v`：RTOS CPU、SoC、定时器和中断控制器。
- `fw/rtos/`、`script/build_rtos_*.ps1`、`run_rtos_sim.ps1`、`validate_rtos_hardware.py`：内核配置、应用、构建与验收。
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
