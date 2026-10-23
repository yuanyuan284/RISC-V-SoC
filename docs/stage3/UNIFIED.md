# RTOS、XIP 与 CPU JTAG 合并实验

本页记录 RTOS、XIP 和独立 CPU JTAG 的合并实验。FreeRTOS XIP 应用已持久写入 MCU 用户区，合并位流已持久写入 FPGA 配置 Flash，两者的整片读回核对通过。2026-10-23 用户确认开发板只接供电和 COM3 后，预先打开串口监听再上电；同一次监听捕获 `BOOT FLASH`、FreeRTOS 启动、自检通过和三次增长心跳，报告 `status=passed`。独立 CPU JTAG 曾扫描全 1，现已读到 TAP、合并外设标识，在 XIP 中命中硬件断点并完成单指令步进，恢复后心跳继续增长。完整 RAM 下载等旧独立调试变体的验收尚未在持久合并系统重跑。

## 目标结构

`GenUnifiedCpu.scala` 以同一颗 VexRiscv 结合 RTOS 所需的可写 `mtvec`、`mscratch`、`ecall`、机器中断和独立 JTAG 调试模块。`stage3_unified_top.v` 把这颗 CPU 的指令/数据 Wishbone 端口连到 BootROM、64 KiB RAM、UART、CLINT、PLIC、事件寄存器、Flash XIP 只读窗口及原有 Flash 写控制器。调试模块的 `stoptime` 接 CLINT；只有调试器请求暂停计时才冻结 `mtime`，定向仿真已通过。复位入口仍为 `0x20000000`：Flash BootROM 优先检查用户区 XIP 镜像，失败才进入 UART 加载。FPGA 配置 JTAG 与 CPU JTAG 仍是两条不同链路。

该实验使用独立的 `build/unified/`，不覆盖 `build/rtos/`、`build/flash/`、`build/debug/`。构建和本地验收入口：

```powershell
.\script\build_debug_cpu.ps1 -Variant unified
.\script\build_unified_firmware.ps1
.\script\run_unified_sim.ps1 -Test bootrom
.\script\run_unified_sim.ps1 -Test bootrom-reject
.\script\run_unified_modelsim.ps1
.\script\run_unified_sim.ps1 -Test jtag
.\script\run_unified_sim.ps1 -Test jtag-bootrom -Timeout 600
.\script\build_unified_td.ps1 -Bitstream
```

固件命令只在本地生成 `build/unified/freertos_xip.elf`、`.bin` 和 `.xip`，不会烧写 Flash。XIP 入口为 `0x30050010`。由于关闭 CPU 寄存器前递以节省 FPGA 资源后，完全从 SPI Flash 执行的 1 kHz RTOS tick 曾使低优先级任务长期得不到运行机会，因此链接脚本把 FreeRTOS 的 `tasks.c`、`list.c` 和 `portASM.S` 放到高 RAM 的 `.ramtext`：启动代码从 Flash 复制这部分热代码、复制 `.data` 到低 RAM、清零 `.bss`，然后进入仍主要从 Flash XIP 执行的应用。低 RAM `0x80000000..0x80007fff` 放数据/堆，高 RAM `0x80008000..0x8000efff` 放热代码，顶部 `0x8000f000..0x8000ffff` 留作栈。打包器逐段检查 ELF/BIN、Flash 加载地址、RAM 代码和栈边界，并生成 BootROM 所需的 `XIP1` 头和 CRC。当前 `.xip` 为 15908 B；2026-10-23 主机测试 111 项通过。

完整生产镜像的 BootROM CRC 和 FreeRTOS 验收使用 `run_unified_modelsim.ps1`：ModelSim 10.1c 对同一 RTL 从默认复位入口执行，检查完整 15908 B XIP 镜像、抢占、队列、软件/定时器/PLIC UART 中断、寄存器保存和临界区。2026-10-23 脚本复跑输出 `PASS unified XIP FreeRTOS preemption, queue and interrupts`，用时约 391 秒，日志为 `build/unified/modelsim/full_crc_system.log`。原 `run_unified_sim.ps1 -Test system` 仍可用 Icarus 做同一全长 CRC 测试，但在本机耗时很长；不要把它的等待误判为死锁。

`-Test jtag` 直接从 XIP 入口复位，已由 OpenOCD 验证暂停、读取 XIP 头、两次单步和单个硬件断点。新增 `-Test jtag-bootrom` **不覆盖复位入口**，先从 BootROM 进入 FreeRTOS，通过 UART 中断与调度自检后才开放 remote-bitbang JTAG；2026-10-23 在同一次 Icarus RTL 运行中得到 `PASS unified Flash BootROM, FreeRTOS self-test, and CPU JTAG in one RTL run`，OpenOCD 的 XIP 读取、单步和硬件断点标记也全部出现。为避免 Icarus 在 BootROM 软件 CRC 上超过 600 秒，这项联合测试调用 `prepare_unified_sim_image.py` 生成独立 `.hex`：**全部应用字节保持不变**，仅将仿真用 XIP 头的 CRC 长度改为前 64 字节并重新计算校验值。它验证 BootROM 的检查与跳转以及三种能力在同一运行中协作，**不证明这一次运行校验了完整应用**；完整 CRC 由上述 ModelSim 测试单独覆盖。真实 `.xip`、位流和板上 Flash 不受此仿真镜像影响。测试台还补齐 JTAG 后置模式的 UART 自检激励、镜像装载失败即报错和超时进度日志；此前的 600 秒空日志由全长软件 CRC 耗时及自检激励缺失共同造成。

`-Test bootrom` 使用已有 `build/flash/hello.xip`（先运行 `build_flash_firmware.ps1` 生成），通过 Flash BootROM 的 CRC 检查启动小型 XIP 应用，并看到 `BOOT FLASH` / `HELLO,YUAN! XIP V2`；`-Test bootrom-reject` 故意损坏应用字节，验证 CRC 不匹配时回退到 `BOOT UART 64K`。这些均为本地 RTL 仿真，不是实板结果。

## 2026-10-22 资源实测

目标器件 EF2L45LG144B，25 MHz CPU、1 MHz JTAG 时钟约束；以下数字来自 TD 5.6.5 本地工程。`mslice` 的器件上限为 1120，早期方案先在布局阶段触及此限制。

| 方案 | gate LUT | place 所需 mslice | 结果 |
|---|---:|---:|---|
| 4 KiB I-cache、2 个硬件断点槽 | 4326/4480 | 1192/1120 | 超出 72 |
| 2 KiB I-cache、2 槽 | 未保留报告 | 1223/1120 | 更差，已恢复 4 KiB |
| 4 KiB I-cache、1 槽 | 4223/4480 | 1164/1120 | 未接 `stoptime` 时的基线，超出 44 |
| 上行方案改用掩码 OR 读数据汇合 | 4408/4480 | 1207/1120 | 更差，已恢复原译码 |
| 上行基线去掉 Flash 读计数器 | 4342/4480 | 1204/1120 | 更差，已恢复计数器 |
| 早期方案：4 KiB I-cache、1 槽，CLINT 支持 `stoptime` | 4217/4480 | 1169/1120 | 超出 49 |
| 上行方案关闭未用的 `mcycle` CSR | 4085/4480 | 1146/1120 | 仍超出 26 |
| 上行方案改为 64B 缓存行 | 4119/4480 | 1147/1120 | 更差，已恢复 32B |
| 上行方案关闭寄存器堆 `zeroBoot` | 4085/4480 | 1146/1120 | 无收益，已恢复 |
| 上行方案取消唯一硬件断点槽 | 4006/4480 | 1127/1120 | 仍超出 7，且削弱调试；已恢复 |
| 保留硬件断点、只读 `mtime` | 4168/4480 | 1164/1120 | 比保留写能力更差；已恢复 |
| 当前方案：4 KiB I-cache、1 槽，关闭四处寄存器前递 | 4220/4480 物理 LUT | 1105/1120 | 完成布线和位流，剩余 15 mslice |

先前 `PHY-9009` 的失败是历史试验，不代表当前状态。当前候选位流 `build/unified/stage3_unified.bit` 为 259361 B，SHA256 `BDFF6D40A2132DCA196ABBEA79A9F7D0AC5A29489B5E8CCF8D86C68C240A4A10`；TD 报告物理 LUT 4220/4480、BRAM9K 10/12、布局 1105/1120 mslice，最终时序 0 setup/0 hold，25 MHz CPU 最小时钟周期 21.199 ns。资源余量仅 15 mslice，增加逻辑后必须重跑 TD。关闭前递会增加相关指令之间的停顿，不改变 RV32IM 功能；实际调度性能需要以软件和实板验证。当前 CPU 保留 **1 个硬件断点槽**，比旧独立 JTAG CPU 少 1 个；`mcycle` CSR 被去掉，RTOS tick 仍使用 CLINT `mtime`。合并位流的本地仿真及下述实板初测验证了单步和一个硬件断点，但尚不能沿用旧位流的完整 JTAG 实板验收结论。

物理面积报告中的层级数据可帮助判断后续改动的成本；下表 `LE/LUT` 是模块层级统计，**不是**可以逐行相加后与上面的全芯片物理 LUT 数直接比较的同一口径。

| 模块 | LE | 层级 LUT | 对资源规划的意义 |
| --- | ---: | ---: | --- |
| VexRiscvUnified CPU（含缓存和调试） | 3049 | 2804 | 最大成本；其中 4 KiB I-cache 为 197 LE/176 LUT，Debug Module 为 238/191，JTAG TAP/DTM 为 309/225，均已包含在 CPU 行内 |
| Flash 写控制器 | 444 | 416 | 保留 MCU 用户区编程和 16 字节批量页写，不能因只测试 XIP 读取就随意删除 |
| UART | 316 | 271 | 启动回退、RTOS 中断输入及验收输出共用，仍是完整系统的一部分 |
| CLINT | 284 | 235 | 提供 FreeRTOS tick/软件中断；调试暂停时 `stoptime` 防止时钟继续走 |
| Flash XIP 读桥 | 175 | 166 | 把用户区 Flash 映射到 CPU 地址空间，缓存未命中时发起 SPI 读取 |
| PLIC | 56 | 56 | 接收 UART 等外部中断，向 CPU 发机器外部中断 |

TD 最终布局日志报告 `1105 mslices`，器件上限 `1120`，只余 **15 个（约 1.3%）**；相对 LUT 上限也只余 260 个（约 5.8%），BRAM9K 只余 2 个。这里的“余量”不是可以直接拿来放任意模块的连续空白空间，新的逻辑还可能改变布线、时序和缓存/BRAM 打包。因此当前选择保留 FreeRTOS、XIP、Flash 写入和一个硬件断点，而不是为提高余量删掉目标能力；后续增功能先评估模块成本，再跑完整综合、布局、布线和时序，不把软件测试通过当作硬件可放得下。

## 2026-10-22 实板验证与持久化边界

经 TD 的 `script/configure_unified_fpga.tcl` 将候选位流**仅配置到 FPGA SRAM**后，COM3 先收到 `BOOT FLASH` 和原有 `HELLO,YUAN! XIP V2`。OpenOCD 读到 CPU TAP `0x10002fff`、新版 Flash 写控制器状态 `0x80`，在旧 XIP 应用中完成单步和一个硬件断点。本轮没有向 RAM 下载调试程序。

`script/backup_unified_flash_readonly.ps1` 将片内 512 KiB Flash 分成八个 64 KiB 段，每段独立读两次并比较。写前备份为 `build/unified/backups/ef2_internal_flash_20261022-190112_2cf7abba.bin`，SHA256 `f1fbbc46bcf2d8178551efe4253b6b6be4905a56beacd7966d6c1d8d2e8fc54a`。原 `0x50000` 是 V2 XIP 镜像，`0x51000..0x53fff` 原为空白。

更新计划位于 `build/unified/plans/rtos_xip_from_v2_20261022/`：目标 FreeRTOS XIP 镜像 15908 B，涉及物理 `0x50000..0x53fff` **四个 4 KiB 扇区**。`old_sectors.bin` 是恢复用原始快照，`new_sectors.bin` 是待写入内容。用户单独授权此范围后，OpenOCD 再次逐扇区核对旧内容，持久写入并逐扇区读回通过，`FLASH_PROGRAM_OK` 报告共改变 15698 字节。写后八段、每段独立双读的整片备份为 `build/unified/backups/ef2_internal_flash_20261022-192938_581a50ad.bin`，SHA256 `0b4533cf787b8d25142bca0f6f566c3d4946da11d51b53b9684f1629167bf974`；`plan_xip_update.py --after` 逐字节比较通过，配置预留区及其他 MCU 用户区均与写前一致。单槽原地更新不具备断电原子性。

首次写后串口反复打印 `BOOT FLASH`、`FREERTOS START`，但不进入自检。CPU JTAG 读到 `mcause=5`、`mepc=0x300518b8`、`mtval=0x0200bffc`，是程序读取 CLINT `mtime` 高 32 位时的取数访问错误。进一步只读探测发现 UART/RAM/Flash 可访问，CLINT、PLIC、事件寄存器均不可访问；这表明板上当时运行的不是合并逻辑。重新执行 **SRAM 配置**后，这三个 RTOS 外设全部可读，问题消失。为何此前 SRAM 位流未保持，尚未确定；不能仅凭 TD 下载成功就推断后续板上仍运行同一位流。

重新配置后，CPU JTAG `reset run`，`script/validate_unified_rtos_hardware.py --port COM3` 在 `build/unified/hardware/rtos_uart_20261022-221157.log` 捕获：

```text
BOOT FLASH
FREERTOS START V11.1.0 RV32IM 64K tick=1000Hz
UART IRQ PASS count=1
CHECK preemption=1 registers=1 critical=1 queue=1 notify=1
FREERTOS PASS tick=76 switches=86 queue=16 msip=1 plic=1 uart=1
RTOS ALIVE tick=1085 queue=217
RTOS ALIVE tick=2089 queue=418
RTOS ALIVE tick=3091 queue=619
```

对应 JSON 报告 `status=passed`。运行中通过 CPU JTAG 在 `vApplicationTickHook` 的 XIP 地址 `0x30050768` 命中唯一硬件断点，移除断点并恢复后，RAM 中 tick 从 `0x10b39` 增至 `0x11438`、队列消费从 `0x3570` 增至 `0x373e`。这些是 **当前 SRAM 位流 + 持久 MCU XIP 应用** 的共存实板证据，不是掉电自启动验收，也不等同旧独立 JTAG 变体的完整下载测试。

## 剩余工作

1. **继续核对脱离调试器的启动条件。** 2026-10-23 的新单次冷启动监听已在用户确认板端仅接供电和 COM3、IoTelic 从电脑断开的条件下通过；Windows 当时仍将 AL-Link Mini 报为在线，因此证据依赖用户关于 AL-Link 未接开发板的接线确认，而不是主机设备列表对 AL-Link 断开的证明。未来可在物理确认两种下载器均与开发板断开后多次冷启动，评估重复性。
2. 查明此前 FPGA SRAM 配置未保持的原因，并在每次实板验收前用 CLINT/PLIC 地址探测区分合并位流与旧位流，避免将应用的错误归因于 Flash 镜像。
3. 若需要与旧独立 JTAG 变体等价的调试验收，还需在合并版上补测全 64 KiB RAM 下载、ELF/源码级调试和重启一致性；当前已证明运行中暂停、单断点、单步和恢复。

### 配置 Flash 操作边界

2026-10-23 已新增 `script/program_unified_flash_fpga.tcl` 与 `script/verify_unified_flash_fpga.tcl`，均只引用 `build/unified/stage3_unified.bit`。前者需要显式设置 `SOC_CONFIRM_UNIFIED_CONFIG_FLASH=PROGRAM_UNIFIED_CONFIG_FLASH`，缺少或填错时 TD 在 `download` 前报错退出；已用错误确认值实测退出码 1，**没有执行持久烧写**。后者只调用 `verify_spi`。当前本地位流 259361 B，SHA256 `BDFF6D40A2132DCA196ABBEA79A9F7D0AC5A29489B5E8CCF8D86C68C240A4A10`。

执行前必须确认板卡供电、AL-Link 可访问、当前位流和用户对**配置区持久覆盖**的单独授权；重新做整片 512 KiB 双读备份，确认 MCU 用户区仍是 15908 B FreeRTOS XIP 镜像。获授权后才运行受确认变量保护的 `program_unified_flash_fpga.tcl`，接着只读 `verify_unified_flash_fpga.tcl`，再做写后整片双读备份。用 `python script/verify_unified_config_update.py --before <写前备份> --after <写后备份> --xip-image build/unified/freertos_xip.xip` 核对整片文件尺寸、新 XIP 镜像和整个 MCU 用户区逐字节不变；它会报告配置区变化范围，但**不能单独证明变化等于目标位流**。最后须不经 TD SRAM 下载而单独给开发板断电重上电，用 COM3 启动日志和 CPU JTAG 验证新位流与 XIP 应用同时持久生效。全片备份可用于分析和恢复，但不是断电原子更新的保证。

2026-10-23 初次只读探测时，Windows 仍能识别 AL-Link、IoTelic 和 COM3 设备，但独立 CPU JTAG 扫描为全 1；随后 AL-Link 成功识别 EF2L45B 并将位流配置到 SRAM，CPU TAP 仍不可访问。两条 JTAG 路径相互独立，不能以 AL-Link 成功推断 CPU TAP 正常。

### 2026-10-23 配置区持久烧写与读回

用户确认开发板供电并授权覆盖物理 `0x00000..0x4ffff` 配置预留区。为避开 XIP 位流下 TD `read_flash` 曾返回全 `FF` 的问题，先用 AL-Link 仅配置普通调试位流到 FPGA SRAM，再由 TD 原生 `read_flash` 两次独立只读导出整片 512 KiB。`build/unified/backups/td_preconfig_20261023_pass1.bin` 与 `pass2.bin` 均为 524288 B，SHA256 同为 `0b4533cf787b8d25142bca0f6f566c3d4946da11d51b53b9684f1629167bf974`，并与 10 月 22 日写入 FreeRTOS XIP 后的独立 CPU JTAG 双读备份逐字节一致；`0x50000` 的 XIP 镜像核对通过。

待写 `build/unified/stage3_unified.bit` 为 259361 B、SHA256 `bdff6d40a2132dca196abbea79a9f7d0ac5a29489b5e8ccf8d86c68c240a4a10`，小于 320 KiB 配置预留区，TD 最终时序 0 setup/0 hold。设置显式确认变量后运行 `script/program_unified_flash_fpga.tcl`，TD 识别 EF2L45B 和 SPI Flash ID `c8`，`program_spi` 退出码 0；紧接着 `script/verify_unified_flash_fpga.tcl` 的 `verify_spi` 退出码 0。

重新仅配置普通调试位流到 SRAM 后，TD 两次独立整片回读 `build/unified/backups/td_postconfig_20261023_pass1.bin` 与 `pass2.bin` 均为 524288 B，SHA256 `7fbde22d06acd02d492062e71fbab308728d293d7692f20e500ba446935c0434`。与写前备份逐字节比较，107718 个变化字节只在物理 `0x00272..0x2719f`，MCU 用户区 `0x50000..0x7ffff` **0 字节变化**，FreeRTOS XIP 镜像仍匹配。该证据证明配置区已更新且应用区未变；此时 FPGA SRAM 运行的是临时调试位流，**还不能证明断电后自动装载合并位流**。

`script/validate_unified_rtos_hardware.py --trigger power-cycle` 在 COM3 开启 300 秒监听，但 `build/unified/hardware/rtos_uart_20261023-122547.log` 为 0 字节，报告 `status=failed`。本轮没有收到用户确认在监听窗口内重上电，因此此结果仅表示**未捕获冷启动串口证据**，不能单独判定持久位流或应用运行失败。下一步仍须在 COM3 监听已就绪时仅给 EF2 开发板断电重上电，且不调用 TD SRAM 下载；若仍无输出，再检查 COM3 接线、目标供电及独立 CPU JTAG。

在该监听窗口结束后，用户回复“已重上电”。随即重新只读打开 COM3 八秒，收到八条连续的 `RTOS ALIVE`，tick 从 `20149` 增至 `27173`、queue 从 `4031` 增至 `5435`，每条均递增。结合用户确认未用 TD SRAM 下载、此前为整片读回临时装入的普通调试位流，以及旧持久位流缺少 RTOS 中断外设，这支持新配置 Flash 位流与 MCU XIP 应用在重上电后共同运行；但**未捕获本次 `BOOT FLASH`、`FREERTOS START` 和自检横幅**，也没有独立验证用户实际断电时刻。独立 CPU JTAG 在当时的 100 kHz 和 10 kHz 两次扫描仍为全 1，OpenOCD 无法访问 CPU TAP；下文记录了后续恢复和复测。

### 2026-10-23 CPU JTAG 链路恢复与共存复测

用户确认 IoTelic `DO` 到 FPGA `P40`、已测 GND 到开发板 GND 均接牢。Windows 识别 IoTelic 双接口、AL-Link 和 USB 串口；随后 OpenOCD 100 kHz 的 TAP-only 扫描两次读到 `0x10002fff`，不再是全 1。前后状态变化的具体原因尚未查明，不能仅凭确认接牢就断言是某根线松动。

`script/openocd/probe-unified-identity.tcl` 短暂暂停 CPU，只读到 CLINT、PLIC、事件寄存器、Flash 写控制器状态 `0x80` 和 `XIP1` 头 `0x31504958`，随后恢复，输出 `UNIFIED_IDENTITY_OK`。同一持久合并位流运行期间，OpenOCD 在 ELF 符号 `vApplicationTickHook=0x30050768` 设置唯一硬件断点，命中时 PC 为 `0x30050768`；移除断点并恢复后输出 `UNIFIED_HW_BREAKPOINT_PASS`。这一操作未写 RAM 或 Flash。

`script/validate_unified_rtos_hardware.py --observe-running --port COM3 --timeout 20` 在断点测试前后各收到三次递增心跳，后一次 tick `1485722 -> 1487732`、queue `297145 -> 297547`，本地证据为 `build/unified/hardware/rtos_uart_20261023-125835.log` 和同名 `.json`，报告模式为 `hardware_uart_liveness_only`，**不表示捕获了启动过程**。该脚本的主机单元测试与全套 115 项主机测试通过。至此持久合并系统的基本 CPU JTAG 识别、外设只读、硬件断点及 FreeRTOS 恢复已实测；全 RAM 下载、源码级调试和完全脱离调试器的冷启动仍待验收。

### 2026-10-23 断电重上电启动与单步

第一次重新上电时，CPU JTAG TAP 仍读到 `0x10002fff`；RTOS tick 从此前约 148 万回到约 5.9 万，随后 COM3 捕获 `75373 -> 77383` 的递增心跳。这证明运行状态发生了重启，但监听器当时要求整行恰好等于 `BOOT FLASH`，没有同步到启动标记。改为在行内寻找标记，并加入启动标记前串口诊断后，117 项主机测试通过。

第二次在修正后的监听器就绪且已看到旧心跳时，用户确认仅给 EF2 开发板断电至少 3 秒并重上电、未使用 TD 下载位流。`build/unified/hardware/rtos_uart_20261023-130259.log` 同步捕获到 `BOOT FLASH`、`FREERTOS START`、`UART IRQ PASS`、所有自检项和 `FREERTOS PASS tick=82 switches=90 queue=17 msip=1 plic=1 uart=1`，随后抓到第一条 `RTOS ALIVE tick=1089 queue=219`。其 JSON 报告为 `status=failed`，**仅因 120 秒总监听时间在第二、第三条心跳前到期**；启动行前有 1 个杂字节，正是旧版精确整行匹配会漏掉的情况。另开 COM3 后，`rtos_uart_20261023-130519.log/.json` 捕获三次递增心跳 `22159 -> 24167`、queue `4433 -> 4834`，报告 `mode=hardware_uart_liveness_only`。这两份连续会话共同支持持久配置位流和 XIP FreeRTOS 应用在用户重上电后启动并持续运行，但不能把第一份失败报告改称整套单会话通过。脚本已将启动后验收窗口延长至少 15 秒，并新增临近总时限才启动的主机测试；本轮没有再次要求用户重上电来验证修正后的单会话实板结果。

`script/openocd/validate-unified-live-debug.tcl` 对当前运行的 XIP 应用做只读标识检查、唯一硬件断点和单指令步进，实板得到 `UNIFIED_HW_BREAKPOINT_PC=0x30050768`、`UNIFIED_HW_STEP_PC=0x3005076c`、`UNIFIED_LIVE_DEBUG_PASS`，然后恢复 CPU。随后 `rtos_uart_20261023-130641.log/.json` 收到三次递增心跳 `102683 -> 104693`、queue `20537 -> 20939`。脚本不写 RAM 或 Flash；单步后的持续运行已实测，但还不是完整 64 KiB RAM 下载或源码级 GDB 验收。

后续用本地 `freertos_xip.elf` 经 GDB 连接 OpenOCD 的 3333 端口，只读解析到当前 PC `0x80008640`，对应官方 FreeRTOS `tasks.c:4718` 的 `xTaskIncrementTick()`；`tick_hooks=197574` 可由符号直接读取，没有下载 ELF 或写存储。这证明合并版可进行源码级定位与变量检查，但不是完整源码级断点/回溯验收。本次 GDB **仅 `detach`** 后 COM3 20 秒没有心跳，OpenOCD 重新连接并显式执行 `resume` 后，`rtos_uart_20261023-130905.log/.json` 再次收到三次递增心跳 `244214 -> 246230`。再用 GDB `target extended-remote`、`monitor halt`、只读符号检查、**`monitor resume` 后 `detach`** 的顺序复测，`rtos_uart_20261023-131048.log/.json` 收到三次递增心跳 `344743 -> 346753`。因此不能假定单独 `detach` 会恢复 CPU；每次 GDB 会话结束要明确 `monitor resume` 并确认心跳，避免把暂停状态误判为应用死机。

现有 `script/validate_unified_gdb_hardware.py` 将这一流程固定为只读验收：检查 3333/6666/4444 端口空闲，启动 OpenOCD，执行 `script/gdb/inspect-unified-live.gdb`，不下载 ELF；无论 GDB 成败都再向本次 OpenOCD 的 TCL 端口发送 `resume` 并关闭它，最后要求 COM3 三次递增心跳。`--plan-only` 仅列命令，不启动硬件工具。2026-10-23 实板报告 `build/unified/hardware/gdb_20261023-133520/report.json` 为 `status=passed/cpu_resume_confirmed_by_uart=true`；GDB 日志定位到官方 FreeRTOS `queue.c:1599` 的 `xQueueReceive()`，读取 `tick_hooks=1790631`，后续 UART tick `1792098 -> 1794108`、queue `358420 -> 358822`。该入口不会做完整 RAM 下载，且后续若改动 ELF/Flash 镜像须重新核对符号对应关系。

### 2026-10-23 仅板端供电与 COM3 的冷启动

用户先将开发板断电，报告已从开发板取下 IoTelic 的五根 CPU JTAG 杜邦线，并确认开发板只接供电和 COM3 串口。预先运行 `python script/validate_unified_rtos_hardware.py --port COM3 --timeout 180 --trigger power-cycle`，收到 `LISTEN_READY` 后用户才给板子上电，没有运行 TD 下载。单次日志 `build/unified/hardware/rtos_uart_20261023-172828.log` 依次包含 `BOOT FLASH`、`FREERTOS START V11.1.0 RV32IM 64K tick=1000Hz`、`UART IRQ PASS count=1`、`FREERTOS PASS tick=76 switches=86 queue=16 msip=1 plic=1 uart=1`，以及三次递增心跳 `1085/217 -> 2089/418 -> 3091/619`（tick/queue）。同名 `.json` 报告为 `mode=hardware_uart_after_power_cycle`、`status=passed`；与此前启动日志和心跳分属两次监听的记录不同，这是**单次完整验收**。

主机 PnP 只读检查当时未见 IoTelic `15ba:002a`，仍见 COM3 对应 FT232R `0403:6001` 与 AL-Link Mini `336c:1002` 在线。后续核对 [PotatoPie V3.0 开发板资料](https://chipdebug.com/forum-post/54111.html)及本机原理图，确认 AL-Link Mini 是**板载**下载器，板载 Type-C 的 USB 和供电与它相连，FPGA 配置 JTAG 在 PCB 内部连接；H2/H3 均为扩展排针。因此用户确认的条件是**外接 IoTelic CPU JTAG 五线已取下、只保留板载 Type-C 供电和 COM3、未执行 TD 下载**，不能称板上完全没有调试器，也不能由单次通过推断长期可靠性。报告里的本地位流和 XIP 哈希是文件指纹，不是对板上 Flash 的再次读回证明；持久写入和整片读回证据见上节。

### 2026-10-23 持续运行与完整调试回归

`python script/validate_unified_rtos_hardware.py --soak-seconds 120 --port COM3` 在开发板只接供电与 COM3 的当前运行状态下，记录 118 条 FreeRTOS 心跳，首末 tick 为 `17698048 -> 17815633`、queue 为 `3539610 -> 3563127`，约 120 秒内始终递增；最大心跳间隔 1.037 秒，未观察到重启。报告 `build/unified/hardware/rtos_uart_20261023-222931.json` 为 `mode=hardware_uart_soak/status=passed`，对应原始日志保存在同名 `.log`。这证明一次约两分钟的持续运行，不替代多次冷启动或更长时间稳定性测试。

随后以同一只读入口执行 `--soak-seconds 600`：`build/unified/hardware/rtos_uart_20261023-224116.json` 报告 `status=passed`、实际观察 600.831 秒、588 条心跳，首末 tick `18390493 -> 18980428`、queue `3678099 -> 3796086`，最大间隔 1.038 秒；同名 `.log` 实有 588 行。期间未观察到 `BOOT FLASH`/`FREERTOS START` 重启标记或计数倒退。这是十分钟连续运行证据，仍不能代替多次断电重上电或更长周期的可靠性验收。

新增 `script/validate_unified_full_debug_hardware.py` 作为合并版完整调试回归入口：先用 OpenOCD 只读核对合并版外设与 XIP 身份，再依次运行 RAM 寄存器/单步/断点、GDB ELF/C 源码、全 65536 字节 RAM 下载和逐字节读回及缓存一致性测试；结束时发送 `reset run`，要求 COM3 再次观察 BootROM、FreeRTOS 自检和三次心跳。`--plan-only` 不连接硬件，正式运行必须带 `--confirm-ram-overwrite`；测试会覆盖易失性 RAM、复位 CPU，**不擦写 Flash**。入口在启动前检查两份待加载 ELF 的全部可加载段均位于 RAM；故障注入单元测试确认中途失败仍尝试恢复且不会报告整套通过。此入口复用旧调试测试的断言，但证据目录和输入指纹单独标记为合并版，不沿用旧位流的通过记录。

用户确认五根 IoTelic CPU JTAG 线已接好、板卡供电，并单独授权覆盖 RAM 后，100 kHz TAP 扫描读到 `0x10002fff`；只读外设探测输出 `UNIFIED_IDENTITY_OK`（CLINT、PLIC、事件寄存器、页写控制器 `0x80` 与 `XIP1` 头均可读），随后 COM3 三条心跳递增。完整回归报告为 `build/unified/hardware/full_debug_20261023-225505-353747/report.json`：`mode=unified_full_debug_hardware`、`status=passed`、`full_suite_passed=true`，`core/gdb/download` 三组均为 `passed`。实板逐项通过 64 KiB RAM 边界/复位保留、寄存器与单步、硬件断点、GDB ELF 下载与 C 源码单步、软件断点、完整 65536 字节图案下载/校验/导出、应用 ELF 校验及更换代码后的指令缓存一致性。`ram-pattern.bin` 与 `ram-readback.bin` 均为 65536 字节，逐字节相同，SHA256 均为 `92637c8cb225bd128b795e12c87eb7a42d069e0fb0b9f4ffeee185770f5312b9`。回归后 OpenOCD 发送 `UNIFIED_RESET_RUN_SENT`，同一 COM3 监听收到 `BOOT FLASH`、FreeRTOS 自检通过和三次递增心跳 `1088/218 -> 2092/419 -> 3094/620`；再次独立监听仍有 `32192/6439 -> 34198/6840` 的递增心跳。报告中的本地位流/XIP 哈希是输入指纹，板上身份以外设读数与运行结果确认；本次没有写 Flash。

为补多次冷启动验收，`validate_unified_rtos_hardware.py` 另支持 `--trigger power-cycle --cycles 3`，同一个串口会话逐次显示 `LISTEN_READY`，每次均独立要求 BootROM、FreeRTOS 自检、UART IRQ 和三条递增心跳。报告保留各次通过/失败，不把重复出现的心跳冒充三次冷启动；物理断电动作仍须由操作者确认。完整调试回归的恢复路径另补了串口清缓冲区失败仍发送 CPU 复位、启动验收失败仍保存部分串口日志的测试。

实际运行 `--cycles 3 --timeout 180` 的报告 `build/unified/hardware/rtos_uart_20261023-230248.json` 为 `status=failed`：第 1、2 次均完整观察到 BootROM、FreeRTOS 自检、UART IRQ 和三条递增心跳，单次记录分别为 `passed`；第 3 次等待期间只有启动前旧心跳，共计 159 行，未捕获新的 `BOOT FLASH`，因而不能报告三次冷启动通过。用户随后确认又断电重上电，单次 `--timeout 300` 重试报告 `rtos_uart_20261023-230842.json` 仍未捕获启动标志；再运行 12 秒当前心跳观察无心跳。为排除只是启动标志被过滤，脚本已改为在未捕获启动时也保留串口原始数据；用户按 SW2 后的 60 秒监听 `rtos_uart_20261023-231603.log` 为 **0 字节**。Windows 只读设备检查仍显示 FT232R COM3 和 IoTelic 在线，AL-Link Mini 未枚举；板端独立 CPU JTAG 线按用户报告已取下。COM3 可打开不等于 FPGA 已供电或 UART 线有信号，IoTelic 在电脑端在线也不等于连通 FPGA。当前须先独立确认开发板供电与 COM3 板端 TX/RX/GND，再重试完整冷启动；**不应为此重烧 Flash**。修复后的全套主机测试为 137 项通过。

随后用户要求重试。Windows 设备检查时 AL-Link Mini 已重新枚举，FT232R COM3 和 IoTelic 也都为 `OK`；这只证明电脑端 USB 设备在线。用户确认开发板一侧仍没有调试线。COM3 `rtos_uart_20261023-231939.json/.log` 捕获三条递增心跳 `31187/6238 -> 33193/6639`，报告仅为 `liveness_observed`，并未重新捕获启动。紧接着 `--soak-seconds 60` 在 5 秒无心跳后失败，`rtos_uart_20261023-232006.log` 为 0 字节；随后的 12 秒 `--observe-running` 复测 `rtos_uart_20261023-232044.log` 也为 0 字节。曾短暂恢复输出，不代表持续稳定；这轮**没有通过新的可靠性验收**。需先独立确认板端电源电压和 UART TX/GND 连通，再判断是供电、连线还是运行故障。电脑端 AL-Link/IoTelic 枚举状态不能代替板端检测。

进一步检查发现 AL-Link Mini 从 Windows 的 `PresentOnly` 列表消失，历史设备状态变为 `Unknown`；同一时刻 TD 执行现有只读 `script/check_jtag.tcl` 报 `PRG-9505 USB device open error`，**未读到 ID，也未写入**。用户重插开发板板载 Type-C 后，AL-Link 重新枚举为 `OK`，相同 SVF 的 `TDO (03004C37) MASK (FFFFFFFF)` 校验由 TD 报 `PRG-2505 ... successfully`，证实此时板载下载器和 EF2 配置 JTAG 连通。不能仅凭这些事件断定故障根因是线材、插口、供电还是驱动，但它们将排查重点指向板载 Type-C/USB 连接状态。

重插后 `rtos_uart_20261023-232653.json` 的 60 秒只读观察为 `passed`，59 条心跳递增，最大间隔 1.038 秒。随后在同一 COM3 会话重新执行 `--trigger power-cycle --cycles 3 --timeout 300`；用户每次在 `LISTEN_READY` 后仅给板载 Type-C 断电至少 3 秒再接回，COM3 保持连接，外接 IoTelic 五线仍不接板，未执行 TD 下载。`build/unified/hardware/rtos_uart_20261023-232815.json` 为 `mode=hardware_uart_cold_boot_cycles/status=passed`，三次记录均为 `passed`；原始 `.log` 恰有三次 `BOOT FLASH`、三次 `FREERTOS PASS` 和九条验收心跳，各次还捕获 `FREERTOS START`、`UART IRQ PASS count=1`。物理断电动作由用户报告，串口启动序列为工具实测。第 3 次后再做 `--soak-seconds 120`，`rtos_uart_20261023-233435.json` 为 `passed`，120.741 秒内 119 条心跳递增，最大间隔 1.038 秒、无重启标志。这补齐了本轮三次上电和连续运行验收；先前失败报告原样保留，不能被事后改写为通过。长周期可靠性和此前 USB 间歇失联根因尚未完全确认。

为复验 Type-C 重插后的持续状态，随后又运行 `--soak-seconds 600`：`build/unified/hardware/rtos_uart_20261023-233901.json` 为 `hardware_uart_soak/status=passed`，同名原始 `.log` 恰有 587 条心跳，首末 tick `288433 -> 877363`、queue `57687 -> 175473`，观察窗口约 600 秒，最大相邻心跳间隔 2.935 秒（低于 5 秒阈值），未见启动、失败或计数倒退标志。结束后 Windows 仍显示板载 AL-Link Mini `OK`。这证明当前连接下的**三次冷启动、完整调试回归、十分钟连续运行**均通过；不能据此推断无限期稳定、其他线材/USB 口同样可靠，或断言先前失联的确切根因。外接 CPU JTAG 断开与板载 AL-Link 存在须继续分别表述。
