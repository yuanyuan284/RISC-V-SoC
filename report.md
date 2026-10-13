# EF2 FPGA 上的 RISC-V 程序加载实验：从零理解与答辩准备

> 初版截至2026-10-12；Stage 3 进度补记于2026-10-13。本文依据当前工程代码、构建报告和已有实板测试记录撰写。**尚未见到正式课题书或评分标准**，所以“项目要求”一节是从工程目标推导出的建议验收口径，不应冒充老师给出的原始要求。

## 最新目标与当前边界

初版正文主要解释已在实板验证的 Stage 2（1KiB ROM/1KiB RAM、最多896B程序）及旧JTAG探索。现在的新目标是 **8KiB BootROM + 64KiB RAM**：C先经RISC-V交叉GCC编译为ELF；`objcopy -O binary` 得到BIN，`objcopy -O ihex` 得到Intel HEX；上位机只把BIN送给BootROM，BootROM验CRC后写入RAM并跳转；应用使用newlib `printf`/`snprintf`，不是只靠 `putc` 拼字符串。ELF用于链接和检查，BIN是下载的字节映像，HEX是另一种文本记录格式，三者不是三个要同时发给板卡的文件。

目前编译/转换、一致性校验、TD时序（0 setup/hold错误）、完整存储空间的功能仿真已通过；**Stage 3 app A/B 均已在实板通过42424B BIN下载、CRC校验、跳转RAM和真实newlib格式化输出**。COM3分别返回 `id=1`、`id=2`，且均有 `signed=-42 hex=001234ab str=form %`、`FLOAT=3.25`、内存测试 `errors=0` 和 `STAGE3 PASS`。六类非法帧的拒绝及有效BIN恢复执行也实测通过。两项Icarus长仿真因耗时终止，不计通过；Stage 3仅SW2复位换载尚未单独实测，本轮通过同一位流重新配置复位。实板记录见 `stage3/HARDWARE_VALIDATION.md`，地址布局和操作命令见 `stage3/README.md`。

## 先用一分钟理解项目

**一句话目标：**在安路 EF2 FPGA 里搭建一台小型 RISC-V 计算机，使 FPGA 硬件配置保持不变，而我们可以从电脑发送新的 C 程序，让这台计算机运行它。

可以把 FPGA 位流理解为“搭建计算机的图纸”，把 C 程序理解为“这台计算机要执行的工作”。换程序不等于重新搭计算机。当前工程已经在实板上通过 **UART 串口**演示了“同一份位流运行两个不同程序”。另有 **JTAG 软件加载**方案，但目前只在仿真中通过，不能说已在板上完成。

本项目不是开发一块新的物理芯片，也不是把 C 程序直接交给 FPGA 执行。C 程序先被编译成 RISC-V 机器指令，再由 FPGA 里的 VexRiscv CPU 取指并执行。

## 1. 为什么要做这件事

传统 FPGA 演示常把测试程序预先放在位流里。想换程序，就重新综合、布局布线、生成位流并配置 FPGA。这会把“改软件”与“改硬件”绑在一起，不利于反复实验。

本项目把两者分开：

1. **硬件层：**FPGA 位流定义 CPU、存储器、串口和总线。只有改这些电路时，才需要重新构建位流。
2. **软件层：**C 程序编译成 RISC-V 可执行代码，上传到运行时 RAM。只改程序内容时，理论上不必重新构建位流。

因此，当前成果的意义不是“能打印一句话”，而是**证明一套固定的可编程硬件能够接收并运行不同的软件映像**。两个应用打印不同文字，只是为了把这个事实清楚地展示出来，并不是项目的最终应用价值。

## 2. 必须先懂的基础知识

| 术语 | 通俗解释 | 在本项目中的对应物 |
| --- | --- | --- |
| FPGA | 可以重新配置内部数字电路的芯片。它本身不是一个现成的 RISC-V CPU。 | 安路 EF2L45LG144B；TD 工具把 HDL 变成配置位流。 |
| HDL / RTL | 用 Verilog 描述“电路如何连接、寄存器何时更新”的代码，不是 CPU 顺序执行的软件。 | `stage2/rtl/stage2_top.v`、`stage2_memory.v` 等。 |
| 综合、布局布线、时序分析 | 综合把 HDL 映射为逻辑资源；布局布线把资源放到芯片上并连线；时序分析检查信号能否在规定时间到达。 | TD 的构建流程和 `.area`、`.timing` 报告。时序报告 0 错误是必要检查，不等于所有实板功能均已验证。 |
| 位流 bitstream | 配置 FPGA 电路的数据文件。下载位流是在改变 FPGA 实现的硬件。 | 已验证的 `stage2/build/stage2_uart.bit`；与 C 程序的 `.bin` 不是一回事。 |
| CPU / 指令集 ISA | CPU 是执行指令的电路；ISA 规定指令如何编码及其含义。 | Stage 2 使用 VexRiscv，应用按 RV32IM 编译。 |
| SoC | CPU 加存储器、外设和互连，组成能独立工作的“小计算机”。 | VexRiscv + BootROM + RAM + UART + 总线。 |
| Wishbone 总线 | 片内模块间读写地址、数据、应答的接口协议。 | CPU 通过它访问 ROM、RAM 和 UART；JTAG 原型加载器也使用它写 RAM。 |
| ROM / RAM | ROM 用于放启动代码，RAM 用于可修改的代码和数据。RAM 断电或重新初始化后不能保证内容保留。 | 本工程的 BootROM 是由位流初始化的 FPGA 逻辑存储器，**不是芯片出厂固化 ROM**；应用放在 1 KiB RAM 中。 |
| UART | 异步串行通信：TX 发、RX 收，双方约定波特率。 | 电脑通过 USB-UART 与板卡传输应用；115200 8N1，测试端口是 COM3。 |
| BootROM / 引导程序 | CPU 复位后先运行的较小程序，负责接收、检查并启动应用。 | `stage2/firmware/bootrom.c`；复位后打印 `BOOT UART`。 |
| 编译器、链接脚本 | 编译器把 C/汇编变成指令；链接脚本决定代码、数据放在哪些地址。 | RISC-V GCC；`bootrom.ld` 把引导程序放在 `0x20000000`，`app.ld` 把应用放在 `0x80000000`。 |
| ELF、BIN、HEX | ELF 带入口地址和装载段等结构信息；BIN 是平坦字节序列；HEX 在本工程里用于初始化存储器或仿真。 | `app_a.elf` 可由上传器在电脑端校验并转成上传字节；板上的 BootROM 不解析 ELF。 |
| JTAG | 一套硬件引脚和扫描协议，可用于识别、配置或调试芯片；还需要下载器及软件发命令。 | AL-Link Mini 通过 JTAG 与 EF2 通信。**JTAG 既不是单独的软件，也不等于已经有 RISC-V 的 GDB 调试功能。** |
| ChipWatcher | 安路的 FPGA 内部信号观察工具，类似在设计里加入逻辑分析仪。 | 目前遇到 TD 插入逻辑的时序违例；它不是 ELF 上传器。 |
| 仿真 / 实板验证 | 仿真是在软件中运行电路模型；实板验证是让真实 FPGA 和外设实际工作。 | UART 路线两者都做过；JTAG 软件加载只做过仿真。 |

**最容易混淆的一点：**JTAG 可以用来下载 FPGA 位流，也可以在有相应硬件支持时用来与用户电路交换数据；这两件事不是同一个操作。`JTAG 已连接、IDCODE 可读` 只证明物理扫描链的基本通信，不证明自定义 RISC-V 加载器已经可用。

## 3. 系统究竟由什么组成

```text
电脑上的 C 源码
    │ RISC-V GCC 编译、链接
    ▼
应用 ELF / BIN ── 上传器 ── USB-UART ── EF2 FPGA
                                      ┌─────────────────────────────┐
                                      │  VexRiscv CPU                │
                                      │       │ Wishbone 总线         │
                                      │  BootROM   RAM   UART 外设   │
                                      │  可选：自定义 JTAG 加载器   │
                                      └─────────────────────────────┘
                                                     │ TX
                                                     ▼
                                           电脑看到应用输出
```

板卡提供物理芯片、时钟、复位按钮和接口；`stage2_uart.bit` 在 FPGA 内部配置出上述 SoC。10 MHz 参考时钟经 PLL 生成系统所用的 25 MHz 时钟。CPU 复位后从 `0x20000000` 取 BootROM 指令。ROM、RAM、UART 的主要地址分别为：

| 地址 | 作用 | 初学者要记住什么 |
| --- | --- | --- |
| `0x20000000` | 1 KiB BootROM | 复位后先运行这里；内容随 FPGA 位流确定。 |
| `0x80000000` | 1 KiB 应用 RAM | 上传后的程序从这里执行；其中最高 128 字节留给栈，所以当前可装载映像最多 896 字节。 |
| `0x40001000` | UART 寄存器区域 | CPU 对特定地址读写，就等于向串口收发数据。 |

这里的地址叫**内存映射**：CPU 发起一次读写，总线根据地址决定把请求送给 ROM、RAM 还是 UART。UART 的“发送一个字符”在软件看来就是写一个寄存器地址。

## 4. 一次 UART 换程序是怎么发生的

1. **先有固定硬件。**把通过时序检查的 `stage2_uart.bit` 配置到 FPGA；这一步搭好了 CPU、BootROM、RAM、UART。
2. **复位进入引导程序。**按下并松开板上的 SW2，CPU 从 BootROM 起跑，串口输出 `BOOT UART\r\n`。这里的 SW2 是 FPGA 设计的复位输入，不是下载器的复位按钮。
3. **电脑准备应用。**RISC-V GCC 产生 ELF。上传器检查 ELF 的架构、入口、装载地址和大小，在电脑端将其变成适合当前 RAM 的字节映像。
4. **上传器发送。**电脑先等到新一次复位的横幅，再发送 16 字节 `RV32` 文件头（包含长度、入口地址和 CRC32），随后发送应用字节。BootROM 按字节回复 `A`，接受文件头回复 `H`。
5. **校验并运行。**BootROM 将字节写入 RAM，计算 CRC32；一致时回复 `G` 并跳转到 `0x80000000`。应用开始执行，打印自己的文字。
6. **更换应用。**再次按 SW2 进入 BootROM，上传另一份程序。已验证的实验中，app A 与 app B 使用同一 FPGA 位流；只换了 RAM 中运行的软件。

`A/H/G` 是本项目自定义串口协议中的应答字符，不是 UART 标准自带的功能。CRC32 能发现传输错误，但不是加密或身份认证。上传器要求新横幅，是为了避免把机器码误发给正在运行的应用。

## 5. 为什么分三个阶段

**Stage 1 是起步验证。**它使用资源很少的简化 CPU，支持固定演示程序所需的少量指令，主要验证时钟、复位、UART、ROM 初始化和最基本的板级运行。它不能被当成能运行普通 C 程序的完整处理器。

**Stage 2 验证了小容量加载。**它使用完整的 VexRiscv RTL、BootROM、RAM、UART 和真正交叉编译的 RV32IM C 示例。1KiB RAM/1KiB ROM验证“同一硬件换程序”，并完成仅按SW2换载的历史实测。

**Stage 3 是当前成果。**它把ROM扩大到8KiB、RAM扩大到64KiB，使用交叉GCC和objcopy导出ELF/BIN/Intel HEX，BootROM接收BIN并校验后跳RAM执行。更大的存储支持链接newlib `printf`/`snprintf`及软件浮点格式化；两个约42KiB应用的实板结果已经通过。

这种分阶段做法的逻辑是：先缩小硬件连接和时钟问题的范围，再换上完整 CPU 验证软件加载。答辩时不要把 Stage 1 的简化 CPU 说成 Stage 2 使用的完整 VexRiscv。

## 6. 已经证明了什么，尚未证明什么

| 结论 | 证据层级 | 严格表述 |
| --- | --- | --- |
| Stage 3 构建与BIN装载执行 | **产物校验及实板通过** | ELF/BIN/Intel HEX对应一致；两份42424B BIN经UART下载、CRC通过后在RAM运行。 |
| Stage 3 真正格式化输出 | **实板已验证** | newlib `printf`/`snprintf` 输出整数、十六进制、截断字符串、百分号和 `FLOAT=3.25`；`errors=0`、`STAGE3 PASS`。 |
| Stage 3 8KiB ROM/64KiB RAM | **译码/资源/内存功能仿真通过，部分实板读写验证** | 全空间功能模型读写通过；实板执行代码、测试上部14KiB及栈。没有实板全地址穷举的结论。 |
| Stage 3 非法传输拒绝 | **实板已验证** | 零长度、超长、未对齐长度、错误入口、错误magic、错误CRC均拒绝，之后有效BIN可执行。 |
| Stage 2 UART 路线能让同一位流运行 app A、app B | **实板已验证** | 实板输出了两份不同应用的文字；SW2-only 复位后可再次上传，不必重新下载位流。 |
| 上传器可接受当前示例的 ELF | **实板已验证** | 电脑解析 `app_b.elf` 后传给 BootROM，板卡运行 app B。不能说 BootROM 在板上解析 ELF。 |
| Stage 2 UART 协议与 CPU 系统逻辑能完成 A 到 B 流程 | **RTL 仿真通过** | 旧版测试平台检查横幅、应答和两个应用输出；Stage 3长UART仿真未完成，不可套用此结论。 |
| JTAG 私有 69 位加载器可写 RAM、回读、切换启动地址 | **仅 RTL 仿真通过** | 仿真用测试替身模拟了 `EF2_PHY_CONFIG` 的用户扫描使能；没有验证真实 EF2 如何选择用户扫描链。 |
| JTAG 连接正常 | **有限实板验证** | 只读 IDCODE `0x03004C37` 通过，不代表 JTAG ELF 下载已通。 |
| Stage 3 UART 位流时序、资源 | **工具报告通过** | 0 个 setup/hold 错误；存储使用1块256K、1块128K、6块32K，CPU另使用10块9K BRAM。 |
| JTAG 位流时序、资源 | **工具报告通过，未下板** | 0 个 setup/hold 错误；使用 3912/4480 LUT、12/12 个 9K BRAM。报告不能代替实板运行。 |
| ChipWatcher 实时观察 | **尚未完成** | 最小工程复现 `jrstn` 的 removal 时序违例，不能靠不精确的 false-path 约束掩盖。 |

**当前限制：**Stage 3应用映像上限60KiB，最高4KiB RAM留栈，入口固定 `0x80000000`。测试应用的链接脚本另保留14KiB RAM测试区，普通应用要重新核对代码、数据、BSS、堆和栈布局。两个42KiB应用的成功不等于任意C程序都能运行。每次加载一个应用，下一次需复位；RAM掉电失效。协议不提供远程断点或单步。896B上限属于旧Stage 2。

## 7. JTAG 路线为什么卡住

理想的 JTAG 路线是：电脑通过 AL-Link 将数据送入 EF2 的 JTAG TAP，TAP 选中 FPGA 用户扫描链，自定义加载器通过 Wishbone 写 RAM、回读校验，再让 CPU 从 RAM 启动。项目已有自定义加载器和完整 SoC 的仿真。

但**从 TAP 走到用户扫描链的那一步缺少器件文档**。我们能读到芯片 ID，不代表知道哪条 IR 指令可以让 `EF2_PHY_CONFIG.jscanen` 有效。已有候选指令未返回加载器签名；其中有些指令在官方 BSDL 中属于测试或配置用途，继续盲试有风险。JTAG 仿真中的 `EF2_PHY_CONFIG` 是测试替身，直接把 `jscanen` 设为有效，因此仿真绕开了这个硬件未知点。`stage2_jtag.bit` 迄今未下载到实板。

还有一条不同的工具路线：安路 ChipWatcher 用于观察 FPGA 内部信号。但 TD 5.6.119222 在插入它后出现 JTAG 复位相关的 removal 时序违例，最小工程也能复现；目前需要安路确认原因和官方修复方式。ChipWatcher 与自定义 JTAG 软件加载器是两个问题，不应混为一谈。

**最诚实的答辩说法：**“JTAG 物理连接和 ID 读取已经验证；自定义 JTAG 装载协议及两个应用的执行在 RTL 仿真中通过；EF2 用户扫描链指令尚缺官方定义，因此没有进行实板 JTAG 软件装载。”

## 8. 当前明确要求和验收证据

用户最新提出的工程要求和对应证据如下；这仍不是老师正式课题书的转录：

1. C经RISC-V交叉编译生成ELF，objcopy生成BIN和HEX：构建脚本和产物一致性检查通过。
2. BootROM下载BIN到RAM，再跳RAM地址执行：两份42424B应用实板下载、CRC及输出通过。
3. RAM64KiB、ROM8KiB：地址译码、厂家资源映射、完整空间功能测试及应用实板读写共同提供证据。
4. 真正格式化输出：newlib `printf`/`snprintf`的整数、字符串和浮点结果已经实板确认。

上述明确要求已经实现。自定义JTAG软件加载、单步/断点及Stage 3仅SW2换载演示属于另外的扩展或补充测试，不应写成已完成的本次证据。

## 9. 三分钟答辩讲述范例

> 我的项目是在安路 EF2 FPGA 上搭建 RISC-V SoC，并研究如何在硬件配置不变时加载不同的软件。FPGA 位流决定 CPU、存储器和串口电路；C 程序编译成 RISC-V 机器码后放到 RAM，由 CPU 执行。两者要区分，否则每换一段软件都得重新构建硬件。
>
> 我先用Stage 1确认时钟、复位和UART，再用Stage 2验证小容量程序加载。现在的Stage 3使用完整VexRiscv，配置8KiB BootROM、64KiB RAM和UART。C程序经交叉GCC生成ELF，objcopy导出BIN和Intel HEX。板卡实际接收BIN，BootROM检查长度、入口和CRC32，把机器码写到RAM后跳转执行。
>
> 实板上两份约42KiB的C应用均下载并运行成功，使用真正的newlib printf和snprintf，输出整数、十六进制、字符串和浮点3.25，上部RAM测试错误数为0。本轮使用同一位流重新配置来复位；Stage 3仅按SW2换载还没有单独实测。地址和存储资源支持64KiB RAM与8KiB ROM，完整内存功能模型测试通过，TD setup/hold错误均为0。当前最大BIN为60KiB，顶部4KiB留作栈，RAM掉电不保存。
>
> JTAG 方向已经实现了私有加载器并在仿真中完成两个程序的加载、回读和运行，实板只验证了 IDCODE。由于 EF2 用户扫描链指令的官方定义尚未取得，我没有把 JTAG 软件加载说成已在实板完成；ChipWatcher 还有一个待厂商确认的时序问题。

讲述时展示位流指纹、两份BIN的构建产物、`app_b_hardware.log`、`protocol_hardware.log`和TD存储/时序报告。Stage 2仅SW2换载记录可作为历史演示；不要归到Stage 3本轮结果。格式化和内存测试证明加载与执行能力，不提供处理器性能基准。

## 10. 常见提问与简答

**问：为什么 FPGA 里还要放 CPU？**  FPGA 负责实现硬件；CPU 让我们用编译后的程序描述可变行为。这样软件更新不必每次重新设计电路。

**问：换 app A 为 app B 时，到底改了什么？**  FPGA 位流没变；SW2 让 CPU 回到 BootROM，电脑把新机器码写进 RAM，CPU 再从 RAM 起跑。

**问：为什么要按 SW2？能不能不断电直接热更新？**  当前设计需要复位后重新进入 BootROM；还没有实现运行中安全停机、指令缓存维护与热更新。按 SW2 不等于重新下载位流。

**问：ELF、BIN、HEX和bit有何区别？** ELF包含软件机器码和装载信息；BIN是objcopy导出的扁平字节映像；Intel HEX是包含地址与校验的文本记录；bit配置FPGA电路。Stage 3只把BIN发给BootROM。

**问：RAM64KiB为什么BIN上限是60KiB？** 顶部4KiB留给栈。BIN不包含未初始化BSS，但BSS、堆和栈仍要占RAM；所以BIN大小合规不等于整体内存布局一定合规。896B是旧Stage 2的限制。

**问：CRC32 的作用是什么？**  检查收到的程序字节是否与发送端一致。它不是防篡改签名，也不能证明程序一定正确。

**问：时序报告 0 错误是否等于板上一定成功？**  不等于。它说明在当前约束和工具模型下没有报告的 setup/hold 违例；串口收发和程序运行还要靠实板验证。

**问：JTAG 是软件还是硬件？**  两者都涉及。板上有 JTAG 引脚和 TAP，AL-Link 是连接电脑的硬件下载器，TD/脚本发送协议命令。IDCODE 可读不意味着用户扫描链已找到。

**问：你完成了 JTAG 调试吗？**  没有。已完成 JTAG ID 读取和自定义加载器仿真；没有实板 JTAG ELF 加载，也没有标准 GDB 单步/断点调试。

**问：如果继续做，优先解决什么？** 可以补录Stage 3仅SW2换载演示，并适配实际业务C程序的链接布局。若课题另要求JTAG调试，再向安路确认用户扫描链定义及ChipWatcher时序处理。

## 11. 阅读和复现顺序

建议先读本文和 `stage3/HARDWARE_VALIDATION.md`，再按下面顺序定位当前代码：

1. `stage3/rtl/stage3_top.v`、`stage3_memory.v`：CPU、地址译码及存储原语。
2. `stage3/firmware/bootrom.c` 与 `tools/uart_upload_stage3.py`：下载和跳转。
3. `stage3/firmware/app.c`、`app.ld`、`syscalls.c`，以及共用的 `stage2/firmware/app_start.S`：C库、内存布局及启动。
4. `tools/build_stage3_firmware.ps1`、`verify_stage3_artifacts.py`：GCC、objcopy及格式一致性校验。
5. `stage3/sim/tb_stage3_memory.v`、`tools/validate_stage3_hardware.py`：测试覆盖范围；项目根目录 `agent.md`：状态和历史记录。

复现仿真可从项目根目录运行 `tools/run_stage2_sim.ps1`；**仿真不会证明当前板卡状态**。实板操作前应核对端口占用、当前位流和电压连接。不要运行已禁用的 JTAG 探测脚本，也不要下载 `*.invalid_bit` 文件。
