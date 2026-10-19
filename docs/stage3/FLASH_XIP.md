# EF2 内置 Flash 与 1-way 指令缓存

更新：2026-10-19。已生成 Flash 启动 BootROM 和候选 XIP 应用；实板读回、应用写入、断电上电启动均尚未通过。

## 目标与现状

EF2L45LG144B 的片内 GD25Q40B SPI Flash 为 4 Mbit（512 KiB）。TD 生成的本项目位流约 259 KiB，占用配置区的一部分；其余空间可能还包含 Golden/Multi Boot 镜像，不能仅凭位流文件大小选一个地址写入。厂商 TN413 给出的 Golden 起点为物理 `0x041000`。在读回并确认当前布局前，Flash 变体只有读功能，不含擦除、页编程和写使能命令。

新变体 `stage3_flash_top` 将 CPU 地址 `0x30000000..0x3007ffff` 映射到片内 Flash 物理 `0x00000..0x7ffff`。数据总线访问该窗口会直接读取 SPI Flash；写操作返回总线错误。CPU 的 `IBusCachedPlugin` 已配置为 4 KiB、32 字节行、`wayCount = 1`；从该窗口取指时由现有的 1-way 指令缓存负责缓存。Flash 桥本身目前没有另建数据缓存。CPU 复位仍从 `0x20000000` 的 8 KiB BootROM 开始，BootROM 根据 Flash 镜像头决定 XIP 或 UART 下载。

Flash 桥使用标准 SPI `03h` 单线读命令，一次读取一个 32 位字；25 MHz 系统时钟产生 12.5 MHz SPI 时钟。顶层通过 `EF2_PHY_INTFLASH` 访问内部管脚，`WP#`/`HOLD#` 保持高电平。该变体位流生成时显式使用 `bitgen -g {persist_bit:0}`，以开放用户模式的 Flash 管脚。此选项由本机 TD 5.6 接受并成功生成位流，但实际电气读回仍需板测。

Flash BootROM 在复位后先检查物理 `0x40000` 处的 16 字节 `XIP1` 头（长度、入口、CRC32），校验通过便跳到 CPU 地址 `0x30040010`。候选 `HELLO,YUAN!` C 应用链接在该地址，`.text/.rodata` 驻 Flash、栈在 RAM；当前镜像没有需要复制的 `.data`。头不存在或校验失败时仍进入原 UART 下载路径。`0x40000` 只是暂定应用槽位；写入前必须排除 Golden/Multi Boot 占用。

## 已通过的离线检查

- `script/run_flash_sim.ps1`：SPI 命令、首字、物理 `0x40100`、末字、大小端和复位中止检查通过；完整 CPU/BootROM/Flash/UART 仿真输出 `BOOT FLASH`、`HELLO,YUAN!`，CRC 损坏或镜像头无效时回退 `BOOT UART 64K`。Flash 循环执行期间无新增 SPI 读事务，验证了仿真中的 1-way 指令缓存命中。
- `script/build_flash_firmware.ps1`：BootROM `.text` 836B，XIP 应用 `.text` 142B，160B 带头镜像 `build/flash/hello.xip`；ELF 入口 `0x30040010`，无 `.data/.bss`。
- `script/build_flash_td.ps1`：独立工程综合、布局布线和位流生成通过，CPU 25 MHz/JTAG 1 MHz 时序报告为 0 setup、0 hold；3559/4480 LUT、10/12 BRAM。
- Python 主机测试 43 项通过，含 Flash 工程与旧 UART/JTAG 工程隔离。
- 含 Flash 启动 BootROM 的本地 `build/flash/stage3_flash.bit` SHA256 为 `64ead754de05133f6f5e6f40c37aae0e71a859208a37dc553bec59995edccc87`。构建输出在忽略的 `build/`，不随仓库发布。

## 实板只读检查

接好开发板供电和 AL-Link 后，先确认配置器可用，再运行 `script/configure_flash_fpga.tcl` 将新位流**仅配置到 FPGA SRAM**。独立 IoTelic FT2232H CPU JTAG 保持 H3 接线，使用 `script/openocd/probe-flash-read.cfg` 读取 Flash 首部、配置区末端、`0x40000` 附近和器件末端。该脚本会暂停 CPU 以读取存储器，但没有 Flash 写命令。保存 TD、OpenOCD 原始输出及位流哈希，再决定应用的安全存储区。

读回、JTAG 实际取指、缓存命中、Flash 程序写入、掉电重启和自动运行尚无实板证据。以上缓存和启动检查仅为 RTL 仿真；`persist_bit=0` 与成功综合不能代替实板验收。

资料：本地 `D:/4.EF2 Family/TN401_安路ELF2 FPGA编程和配置使用说明.pdf`、`TN402_安路ELF2 FPGA内置FLASH读写.pdf`、`TN413_ELF2 DUAL BOOT功能使用指南.pdf`，以及 `D:/PotatoPie V3.0/例程/demo6_test_flash.7z`。
