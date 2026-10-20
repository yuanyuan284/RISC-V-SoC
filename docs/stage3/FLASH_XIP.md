# EF2 内置 Flash 与 1-way 指令缓存

更新：2026-10-20。位流与 XIP 应用已写入 EF2 片内 Flash，实板经临时 SRAM 配置后输出 `BOOT FLASH` 和 `HELLO,YUAN!`，JTAG 观测到 1-way 指令缓存重填后命中。其后用户确认只给开发板断电重上电、未用 TD 下载位流；CPU JTAG 读到 XIP 应用区 PC 和持续增长的循环计数。**调试线保持连接，尚未测试完全脱离调试线的上电。**

## 最新实板结果

烧写前两次 CPU JTAG 全片备份与一次普通调试位流下的 TD 原生读回逐字节一致，SHA256 均为 `3a60a97c00ade9b34a6834f52b016476252d5ea5bdf2940ef7c8e5c3cede00cf`。TD `download -mode program_spi` 完成配置位流持久烧写；写后 512 KiB 备份 `build/flash/backups/td_after_bitstream_program_20261020.bin` 的 SHA256 为 `72f24b2f0227e5854d033afefb711f431169674a0a95788997b7c169b1d5b20a`，新增配置字节止于 `0x3ed0e`，MCU 用户区保持原样。TD `download -mode program_spibin -bin hello.xip.bin -start_addr 0x50000` 报告仅擦除第 80 个 4 KiB 扇区；写后备份 `td_after_xip_program_debug_20261020.bin` 的 SHA256 为 `f4747274c3ec9773d4e3ce7d60c5179357d95cb50cf56c9382c32a9a2ede925c`，全片比较只发现预期 192 字节改变。

TD `read_flash` 必须在普通调试位流运行时执行：`persist_bit=0` 的 Flash 变体运行时曾产生误导性的全 `FF` 读数。临时把 Flash 变体配置到 FPGA SRAM 后，COM3 收到 `BOOT FLASH`、`HELLO,YUAN!`；OpenOCD 读到 CPU TAP `0x10002fff`。应用循环计数持续增长，SPI 事务数在每次 JTAG 恢复后的 100 ms 与 2 s 运行窗口均只增 16，符合缓存重填后命中。用户后来确认开发板断电至少 3 秒并重新上电，未用 TD 下载位流；一次探针返回全 1，后续探针读到 CPU TAP `0x10002fff`，PC `0x3005009c` 位于 XIP 应用区，RAM 循环计数在 1 秒内从 `0x350c71a` 增至 `0x364a82a`，SPI 事务计数从 `0x7d` 增至 `0x8d`。这支持 Flash 自动装载与 XIP 运行，但首次探针失败原因未定；本轮 COM3 同步窗口未捕获启动横幅。重插板卡供电时其他调试线仍连接，未验证完全独立供电场景。

## 单启动分区（不考虑 Multi Boot）

EF2L45LG144B 的内置 GD25Q40B SPI Flash 为 4 Mbit，即 512 KiB。项目采用下面的**单启动软件分区约定**；边界按 64 KiB 对齐，也按芯片的 4 KiB 擦除扇区对齐。本节暂不为 Multi Boot 分配第二份位流。

| 物理 Flash 字节偏移（含首尾） | 大小 | CPU 只读映射 | 归属 |
| --- | ---: | --- | --- |
| `0x00000..0x4FFFF` | 320 KiB | `0x30000000..0x3004FFFF` | FPGA 单启动配置预留区；不允许 MCU 软件或应用烧写流程擦除/覆盖 |
| `0x50000..0x7FFFF` | 192 KiB | `0x30050000..0x3007FFFF` | MCU 用户区，可存放 XIP 程序及以后定义的数据 |

MCU 用户区目前只有前 64 KiB（物理 `0x50000..0x5FFFF`）定义为 `XIP1` 演示程序槽：前 16 字节为头，程序入口为 CPU `0x30050010`；后 128 KiB（物理 `0x60000..0x7FFFF`）**暂未分配**，不是现有 BootROM 能自动启动的第二个程序区。当前桥可读取整个 512 KiB，故“归属 MCU”指将来允许管理/写入的范围，并非 CPU 对配置区完全不可读。当前桥对所有 Flash 写操作都返回总线错误，MCU 还不能在运行时自行更新用户区。

本地 `stage3_flash.bit` 实测 **259,359 字节（约 253.3 KiB）**，小于 320 KiB 预留区，按文件长度算还余 68,321 字节。这只是必要的离线尺寸检查：`.bit` 文件大小不等于 TD 实际写入 Flash 的最终占用、元数据或擦除范围。选择 `0x50000` 也与[安路 MCU Flash Cache 示例](https://tech.anlogic.com/Public/Uploads/ueditor/upload/file/20230707/1688692342948968.pdf)的应用起始偏移一致；该示例本身不证明烧写安全。本次写前/写后 512 KiB 整片读回逐字节比较确认，应用写入未改变配置区；以后更新仍须重复检查。

## 目标与现状

新变体 `stage3_flash_top` 将 CPU 地址 `0x30000000..0x3007ffff` 映射到片内 Flash 物理 `0x00000..0x7ffff`。数据总线访问该窗口会直接读取 SPI Flash；写操作返回总线错误。CPU 的 `IBusCachedPlugin` 已配置为 4 KiB、32 字节行、`wayCount = 1`；从该窗口取指时由现有的 1-way 指令缓存负责缓存。Flash 桥本身目前没有另建数据缓存。只读寄存器 `0x40003000` 记录 SPI 读事务次数，用于观察缓存是否命中；写入该地址返回总线错误。CPU 复位仍从 `0x20000000` 的 8 KiB BootROM 开始，BootROM 根据 Flash 镜像头决定 XIP 或 UART 下载。

Flash 桥使用标准 SPI `03h` 单线读命令，一次读取一个 32 位字；25 MHz 系统时钟产生 12.5 MHz SPI 时钟。顶层通过 `EF2_PHY_INTFLASH` 访问内部管脚，`WP#`/`HOLD#` 保持高电平。该变体位流生成时显式使用 `bitgen -g {persist_bit:0}`，以开放用户模式的 Flash 管脚。此选项由本机 TD 5.6 接受；实板已读回并运行 Flash 中的 XIP 应用，详见上面的验收记录。

Flash BootROM 在复位后先检查物理 `0x50000` 处的 16 字节 `XIP1` 头（长度、入口、CRC32），校验通过便跳到 CPU 地址 `0x30050010`。`HELLO,YUAN!` C 应用链接在该地址，`.text/.rodata` 驻 Flash、栈和两个观测计数驻 RAM；`0x80000000` 是持续增长的循环次数，`0x80000004` 保存程序最近读取的 SPI 事务次数。当前镜像没有需要复制的 `.data`。头不存在或校验失败时仍进入原 UART 下载路径。`0x50000` 是上述单启动分区约定的应用槽起点；192 字节应用已经写入并经整片读回确认。

## 已通过的离线检查

- `script/run_flash_sim.ps1`：SPI 命令、首字、物理 `0x40100`、配置/MCU 分界两侧 `0x4FFFC`/`0x50000`、演示槽分界两侧 `0x5FFFC`/`0x60000`、末字、大小端和复位中止检查通过；完整 CPU/BootROM/Flash/UART 仿真输出 `BOOT FLASH`、`HELLO,YUAN!`，CRC 损坏或镜像头无效时回退 `BOOT UART 64K`。Flash 循环执行期间 RAM 次数增长、SPI 事务数不变，且 CPU 经 MMIO 读到的事务数与模型一致，验证了仿真中的 1-way 指令缓存命中。
- `script/run_flash_jtag_sim.ps1`：实际 OpenOCD 通过 remote-bitbang 扫描真实 CPU RTL 的 TAP `0x10002fff`，经 Program Buffer 读取仿真 Flash 窗口 `0x30050000` 的 32 字节，并与 XIP 镜像逐字节一致。日志和导出文件在本地 `build/flash/flash_jtag_*`、`jtag-image-head.bin`；这验证了备份路径的 JTAG/CPU/总线/Flash 读桥连接，但仍是 RTL 仿真，不是实板全片备份。
- `script/build_flash_firmware.ps1`：BootROM `.text` 836B，XIP 应用 `.text` 174B、`.bss` 8B，192B 带头镜像 `build/flash/hello.xip`；ELF 入口 `0x30050010`，无 `.data`。打包时会校验 ELF 入口、可执行装载地址和导出 BIN 内容一致，避免链接地址与镜像头脱节。
- `script/build_flash_td.ps1`：独立工程综合、布局布线和位流生成通过，CPU 25 MHz/JTAG 1 MHz 时序报告为 0 setup、0 hold；3665/4480 LUT、10/12 BRAM。
- Python 主机测试 58 项通过，含 ELF/BIN 入口一致性、单启动分区边界、只读实板探针命令、Flash 工程与旧 UART/JTAG 工程隔离，以及 512 KiB 备份长度、占用范围、XIP 镜像 CRC/地址和全片写后读回对比。
- 含只读事务计数器、应用候选偏移为 `0x50000` 的本地 `build/flash/stage3_flash.bit` SHA256 为 `6c1d96051f40faab66d96c4c21f247c00f436be7add666c9825d20bb6a25c1a9`。构建输出在忽略的 `build/`，不随仓库发布。

## 烧写前只读检查（历史）

接好开发板供电和 AL-Link 后，先确认配置器可用，再运行 `script/configure_flash_fpga.tcl` 将新位流**仅配置到 FPGA SRAM**。独立 IoTelic FT2232H CPU JTAG 保持 H3 接线，使用 `script/openocd/probe-flash-read.cfg` 读取 Flash 首部、`0x40000`/`0x41000`、配置预留区末尾 `0x4FFF0..0x4FFFF`、MCU 用户区起点 `0x50000`、演示槽末尾 `0x5FFF0..0x5FFFF`、未分配区起点 `0x60000` 和器件末端。该脚本会暂停 CPU 以读取存储器，但没有 Flash 写命令。保存 TD、OpenOCD 原始输出及位流哈希，再核实单启动分区是否适用于实板现状。

完整只读备份入口为 `script/backup_flash_readonly.ps1`。先运行 `-PlanOnly` 检查路径；在确认上述新位流已配置、板卡持续供电后，去掉 `-PlanOnly` 才会通过 OpenOCD 暂停 CPU 并从 `0x30000000` 导出全部 512 KiB。100 kHz JTAG 完整读回可能很慢，运行期间不要断电。脚本使用独立文件名，默认 300 秒超时，把未完成的文件保留为 `.partial`，并检查 TAP/CPU 日志、长度和 SHA256；不擦除、不写入 Flash。也可以用 TD 的 `FLASH READ` 模式独立导出后交给分析器，但不要选 `DIRECT FLASH READ`（它要求下载器直接接 Flash）。**全 `FF` 只能说明看起来未编程，不证明该区域可写**；仍须确认真实配置布局。

2026-10-20 实板记录：TD 将 SHA256 `6c1d96051f40faab66d96c4c21f247c00f436be7add666c9825d20bb6a25c1a9` 的位流成功配置到 FPGA SRAM；CPU TAP 为 `0x10002fff`。两次成功的 CPU JTAG 全片只读导出分别为 `build/flash/backups/ef2_internal_flash_20261020-140301_c1260ea0.bin` 和 `ef2_internal_flash_20261020-142926_8b4aba15.bin`，均为 524,288 字节，逐字节相同，SHA256 `3a60a97c00ade9b34a6834f52b016476252d5ea5bdf2940ef7c8e5c3cede00cf`。它们仅在开头 4 KiB 扇区有 5 个非 `FF` 字节，`0x50000..0x7FFFF` 全为 `FF`。中间一次读回卡住、随后 TAP 扫描错码；重新配置 SRAM 后三次 TAP 扫描正常，再次全片读回与第一份一致。TD 原生 `read_flash -start_addr 0x0 -length 524288` 独立导出 `build/flash/backups/td_flash_20261020.bin`，长度 524,288 字节、SHA256 `043e238a765f7cfbc62596a50e53c8ffb6b188a99357b0ebede251725d67589f`，**全为 `FF`**。与 CPU JTAG 读数恰有 5 字节不同，偏移为 `0x1..0x4` 和 `0x8`；两条路径尚未一致，不能把 CPU JTAG 备份视为准确的物理镜像。之后 CPU JTAG 短读还出现过 TAP `all ones`，链路稳定性待查。没有擦除或写入 Flash。

## 写入前后的核对门禁（已执行）

1. 烧录前已留存两份 CPU JTAG 和一份 TD 原生 512 KiB 备份，三份逐字节一致；`0x50000` 位于本项目单启动 MCU 用户区，写前全为 `FF`。
2. TD CLI 实测有效位流烧写模式是 `download -mode program_spi`，随后用 `download -mode verify_spi` 和普通调试位流下的 `read_flash` 完成核对。烧写后已取得独立的**写应用前**整片备份；不是 SRAM 下载。
3. `inspect_flash_dump.py` 已检查 `hello.xip` 的头、CRC、入口和目标扇区；TD 实际报告只擦除 `0x50000..0x50fff` 一个 4 KiB 扇区。
4. TD CLI 实测有效应用烧写模式是 `download -mode program_spibin -bin hello.xip.bin -start_addr 0x50000`；本机要求 `.bin` 扩展名，固件构建现在自动生成同字节副本。写后整片读回与写前比对，只改变预期 192 字节。未使用背景 `bg` 模式；[安路 FAQ](https://tech.anlogic.com/Cn/Index/index/p/6.html)说明用户逻辑使用 Flash（`persist_bit=0`）时不支持该模式。

```powershell
python .\script\inspect_flash_dump.py .\build\flash\backups\pre-app.bin --image .\build\flash\hello.xip
python .\script\inspect_flash_dump.py .\build\flash\backups\pre-app.bin --image .\build\flash\hello.xip --after .\build\flash\backups\post-app.bin
```

比较器只会在镜像内容、目标扇区和其余 Flash 字节都符合预期时报告**文件级**通过；它无法证明输入文件确实来自同一块实板，也不执行烧录或代替掉电上电验收。文件名是示例，实际备份脚本会生成带时间戳的文件。

实板缓存检查已通过 OpenOCD 读取 `0x80000000`、`0x80000004`、`0x40003000`：RAM 循环次数持续增长，后两个 SPI 事务计数相等。两次 JTAG 恢复后分别运行 100 ms 和 2 s，事务数各增加固定的 16 次，符合缓存重新填充后命中；调试恢复会引入重填，不能把“零增长”作为该测法的通过条件。

位流和应用的持久烧写、整片读回、临时 SRAM 配置后的真实 Flash 取指与缓存观察已有实板证据。**掉电重启后自动加载位流并运行应用仍没有实板证据**；`persist_bit=0` 与成功综合不能代替此项验收。

资料：本地 `D:/4.EF2 Family/TN401_安路ELF2 FPGA编程和配置使用说明.pdf`、`TN402_安路ELF2 FPGA内置FLASH读写.pdf`、`TN413_ELF2 DUAL BOOT功能使用指南.pdf`，以及 `D:/PotatoPie V3.0/例程/demo6_test_flash.7z`。
