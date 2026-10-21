# EF2 内置 Flash 与 1-way 指令缓存

更新：2026-10-22。此前位流与 XIP 应用已写入 EF2 片内 Flash，实板经临时 SRAM 配置后输出 `BOOT FLASH` 和 `HELLO,YUAN!`，JTAG 观测到 1-way 指令缓存重填后命中。新增 MCU 总线 SPI 写控制器与 RAM 侧 C 驱动已通过真实 RV32 RTL 仿真和实板擦写。新版位流在 2026-10-22 持久烧入配置 Flash 并通过只读校验；用户确认只给开发板断电重上电、未用 TD 下载位流后，CPU JTAG 读到 XIP 应用区 PC 和持续增长的循环计数。**调试线保持连接，尚未测试完全脱离调试线的上电；本轮未捕获 COM3 启动横幅。**

随后又开发并在**仅配置 FPGA SRAM** 的条件下实板验证了 16 字节批量页编程版。以下 2026-10-22 持久烧写记录中的哈希指当时的旧位流；当前本地 `build/flash/stage3_flash.bit` 已由后续构建更新，不能据旧记录认定新版已经持久烧到配置 Flash。

## 最新实板结果

### XIP 应用 V2 更新与恢复

2026-10-22 经用户授权，真正替换物理 `0x50000..0x50fff` 的单启动 XIP 应用，串口文字由 `HELLO,YUAN!` 改为 `HELLO,YUAN! XIP V2`。没有改写 FPGA 配置预留区。旧 192 字节镜像 SHA256 为 `927b0ba3bf9ed1e847ea085097f9c93f0f83683a47c65c9dc6d5bc2ee707e761`；新 200 字节镜像 SHA256 为 `be935fae1233090b4f1f8bd3a6d7405f57727e705d9afd10dab33eae364ed432`。新镜像的入口仍为 `0x30050010`，头内长度/CRC32 由构建器生成并经独立解析器验证；RTL 整机仿真验证了新文字、缓存运行以及 CRC 损坏时回退 UART，模拟 CPU JTAG 读回与 90 项主机测试通过。

写前 `script/backup_flash_readonly.ps1` 八段各双读，得到 `build/flash/backups/ef2_internal_flash_20261022-013812_824add66.bin`（524,288 字节，SHA256 `0c43f4fa5e579fe4433e6b0b8e002526c06760f83cf68f0e1afd9e062eb309e4`）。`script/plan_xip_update.py` 要求旧扇区与合法的旧镜像加全 `FF` 尾部完全一致，新镜像必须合法、不同且不超过一个 4 KiB 扇区；它在 `build/flash/backups/xip_update_v2_20261022_0142/` 保存旧/新完整扇区与哈希清单。完整扇区镜像可清掉旧程序多出的尾部。烧写时 `flash_expected_before_image` 再与板上即时读取的旧扇区逐字节比较，不符则在任何写命令前中止；脚本还会另存 `.before.bin`、写后读回 `.after.bin`。

`build/flash/xip_v2_program_20261022.log` 记录 `FLASH_PLAN sector=0x50000 changed=20 erase=1`、`FLASH_SECTOR_OK`、13 次页写与 `FLASH_PROGRAM_OK`。写后扇区与计划文件 SHA256 都为 `96388e39edb7a9d5cc218299b264cab700c17c61c957d58ad2921252f016ce39`。随后再次八段双读整片，`ef2_internal_flash_20261022-014240_82314502.bin` 的 SHA256 为 `f1fbbc46bcf2d8178551efe4253b6b6be4905a56beacd7966d6c1d8d2e8fc54a`，`plan_xip_update.py --after` 逐字节验证 512 KiB 与计划完全一致，配置区和其他用户区没有差异。CPU JTAG `reset run` 后，COM3 日志 `build/flash/poweron_uart_20261022-014549.log` 收到 `BOOT FLASH` 与完整的 `HELLO,YUAN! XIP V2`。这证明新程序在复位后运行；真正断电重上电的同步验证另行记录，不能与 CPU 复位混称。

复现时先构建固件、核对 `hello.xip` 的新旧哈希，再做新的整片双读备份。用 `plan_xip_update.py --before <新备份> --old-image <旧镜像> --new-image build/flash/hello.xip --output-dir <新的目录>` 生成 `old_sector.bin`、`new_sector.bin`；人工核对清单地址仅为 `0x50000..0x50fff`。在本次用户授权的范围内，OpenOCD `program-user-flash.tcl` 输入 `new_sector.bin`、物理偏移 `0x50000`、新的 `flash_backup_prefix`、`flash_expected_before_image=old_sector.bin` 和 `flash_confirm=PROGRAM_USER_FLASH`。写后再做整片双读备份，用同一规划器的 `--after <写后备份>` 严格校验；**校验成功之前不要复位运行新应用**。

若擦写/读回失败，不要把 `FLASH_PLAN` 或单个退出码当成功；保持 CPU 暂停，检查板上当前扇区和本次 `.before.bin`。`old_sector.bin` 是完整恢复镜像，可在确认它属于本板本次备份后，作为 `flash_image` 交给相同 OpenOCD 脚本、`flash_offset=0x50000`、全新备份前缀及显式确认来恢复，恢复后仍须整片双读比较并复位验证旧程序。单槽、原地擦写无法保证中途断电后仍可启动；BootROM 的 CRC 失败会退回 UART 加载，**不等于自动回滚**。完全断电安全更新需要另设计双槽/提交机制，本次没有实现。

后续只读运行探针仍读到 PC `0x30050098` 位于 XIP 程序区，RAM 循环计数在约 1 秒内从 `0x1b1ec42a` 增至 `0x1b32af01`，退出前已恢复 CPU 运行。另开 300 秒 COM3 窗口等待实际开发板断电重上电，`build/flash/poweron_uart_20261022-014648.log` 未收到字符并超时；该窗口**没有**上电横幅证据。用户随后报告已给 EF2 开发板断电重上电、未用 TD 下载位流。紧接着只读 JTAG 识别 CPU TAP `0x10002fff`，写控制器状态 `0x0`（此前 SRAM 临时页编程版为 `0x82`，符合重上电后加载旧版持久位流），V2 头长度 `0xb8`，PC 位于 XIP 区 `0x300500a8/0x30050098`，RAM 循环计数约 1 秒内从 `0x1883678` 增至 `0x19c1583`。重上电后再次读出应用扇区 `build/flash/backups/xip_v2_after_user_powercycle_20261022.bin`，SHA256 `96388e39edb7a9d5cc218299b264cab700c17c61c957d58ad2921252f016ce39`，与计划的新扇区逐字节相同。这个组合支持开发板断电重上电后，旧版配置位流自动加载并运行新 XIP 应用；调试线仍连接，**未同步捕获本次上电串口横幅，也未验证完全脱离调试线的独立供电**。

### 16 字节批量页编程实板测速

原控制器每写一字节就执行一次 `06h` 写使能、`02h` 单字节编程、`05h` 状态轮询。候选版增加 16 字节缓冲：软件先写物理起点，命令 `3` 清空并开启缓冲，随后向数据寄存器连续写入 1..16 个字节，命令 `4` 发起**同一条 `02h` SPI 事务**并等待完成。不能跨越 256 字节 Flash 页边界；配置区、超长缓冲和越界请求在发送擦写命令前被拒绝。状态寄存器 bit7 表示支持批量模式、bit3 表示正在暂存；旧单字节命令 `1`/`2` 仍可用。C 驱动和 OpenOCD 烧录脚本读取 bit7，旧位流上自动回退原路径。OpenOCD 仍须先备份所有目标扇区、检查需要擦除的 0->1 变化，写后逐扇区读回；批量模式只减少 SPI 编程事务和轮询次数，不改变持久写入的风险。

32 字节缓冲的首次 TD 构建虽然时序余量为正，但出现路由冲突，**没有形成可用位流**；缩至 16 字节后，RTL 写入/保护边界、真实 RV32 RAM 固件整机仿真、OpenOCD 隔离模拟后端与 83 项主机测试均通过。TD 资源为 4104/4480 LUT、10/12 BRAM，CPU 25 MHz/JTAG 1 MHz 的最终报告为 0 setup/0 hold。当前本地位流 SHA256 `152cadf20cb9390ee75a1a55fc4d85b414fa1d74dfba61b7a8a7f7a1e69a8f81`；此前已烧入的旧位流 SHA256 `b2f7d1af3921d31cbd961d2c43b44aa0cd6ab3fdafe03d602c33358ed6233078` 保留为 `build/flash/stage3_flash.previous-20261022-010008-246_bit`。

用户授权备份后擦写物理 `0x60000..0x60fff` 测试扇区。TD 仅将新位流下载到 FPGA SRAM，日志 `build/flash/configure_page16_sram_20261022.log` 退出码 0；随后 CPU JTAG 读到 TAP `0x10002fff`，写控制器状态由旧版 `0x00` 变为 `0x80`，XIP 头和 `MCU!` 仍可读。写前 `script/backup_flash_readonly.ps1` 分八段各双读，得到 524,288 字节 `build/flash/backups/ef2_internal_flash_20261022-011525_8e30acd4.bin`，SHA256 `0c43f4fa5e579fe4433e6b0b8e002526c06760f83cf68f0e1afd9e062eb309e4`；测试扇区只有起始四字节 `MCU!` 非 `FF`。

为比较相同数据和起始状态，OpenOCD 在物理 `0x60010` 写入同一个 192 字节 `hello.xip` 镜像（只是测速数据，不作为该地址的启动程序）。第一次设置 `flash_force_byte 1`，旧路径实际编程 190 个非 `FF` 字节，`FLASH_WRITE_TIME_MS` 为 **33,663 ms**；扇区读回一致。按写前备份擦除并恢复原扇区后，再用自动识别的新路径写同一镜像，12 次 16 字节页写、`FLASH_WRITE_TIME_MS` 为 **11,213 ms**，读回一致，写入阶段约 **3.0 倍**。两次都在 100 kHz CPU JTAG 下，镜像本身有 2 个 `FF` 字节；计时只覆盖擦除/编程阶段（这两次写入均无需擦除），不包括 OpenOCD 连接、扇区备份、读回和整片备份。原始日志为 `build/flash/page16_bench_byte_20261022.log` 与 `build/flash/page16_bench_page_20261022.log`。

第二次写后再按原扇区备份擦除恢复，OpenOCD 扇区读回与原扇区完全相同；写后整片八段双读备份 `build/flash/backups/ef2_internal_flash_20261022-012157_9dd69418.bin` 长 524,288 字节、SHA256 仍为 `0c43f4fa5e579fe4433e6b0b8e002526c06760f83cf68f0e1afd9e062eb309e4`，与写前备份逐字节相同。CPU 已从 JTAG 暂停状态恢复运行。**新位流未写入配置 Flash**，开发板掉电后会回到旧版单字节控制器；本次没有重测完全独立冷启动或 XIP 应用更新。

2026-10-22 新版配置位流持久烧写：待写 `build/flash/stage3_flash.bit` 为 259,359 字节，SHA256 `b2f7d1af3921d31cbd961d2c43b44aa0cd6ab3fdafe03d602c33358ed6233078`，小于 320 KiB 配置预留区；TD 最终时序报告 0 setup/0 hold。烧写前 `script/backup_flash_readonly.ps1` 自动分八段、每段双读得到完整 512 KiB 备份 `build/flash/backups/ef2_internal_flash_20261022-000902_a88c657a.bin`，SHA256 `b13c4922e1678c26b4b63550c81a5a0c13741766a32ab74ed650ee168b15ba77`，与 10 月 21 日备份逐字节一致。经用户要求，通过受显式确认变量保护的 `script/program_flash_fpga.tcl` 执行 TD `download -mode program_spi`；日志 `build/flash/program_spi_new_20261022.log` 识别 EF2L45B、SPI Flash ID `c8`，命令退出码 0。`script/verify_flash_fpga.tcl` 运行 `download -mode verify_spi`，日志 `build/flash/verify_spi_new_20261022.log` 退出码 0。烧写后独立 CPU JTAG 双读备份 `ef2_internal_flash_20261022-001554_bc19c23e.bin`，SHA256 `0c43f4fa5e579fe4433e6b0b8e002526c06760f83cf68f0e1afd9e062eb309e4`；与写前逐字节比较，102,199 个变化字节全部位于物理 `0x00272..0x2719f` 配置区，**MCU 用户区 `0x50000..0x7ffff` 0 字节变化**，`XIP1` 和 `MCU!` 仍可读。用户随后确认只重上电 EF2L45 开发板、未用 TD 下载；`build/flash/cold_boot_new_bit_probe_20261022.log` 记录 CPU TAP `0x10002fff`、XIP 头 `0x31504958`、物理 `0x60000` 的 `MCU!`，循环计数在 1 秒内从 `0x1b038ed` 增至 `0x1c42315`。另一次只读探测读到 PC `0x300500ac`，位于 XIP 应用区。这个组合支持新版配置从 Flash 自动加载且 XIP 程序运行；调试线仍连接，本轮没有同步捕获 COM3 启动输出，也没有以完全拔掉调试线的条件测试。

最终只读检查日志为 `build/flash/cold_boot_new_bit_final_20261022.log`：PC `0x300500ac`，暂停/恢复后 1 秒内循环计数从 `0x1c42315` 增至 `0x1d83e14`，OpenOCD 退出前已再次执行 `resume`，使 CPU 留在运行状态。

2026-10-21 MCU 写入验收：先经 CPU JTAG 只读导出全片 512 KiB，文件 `build/flash/backups/ef2_internal_flash_20261021-123216_77890ac3.bin` 的 SHA256 为 `f4747274c3ec9773d4e3ce7d60c5179357d95cb50cf56c9382c32a9a2ede925c`，与 2026-10-20 TD 原生备份逐字节相同，物理 `0x60000..0x60fff` 全 `FF`。用户明确授权该扇区擦写后，TD 当时将 SHA256 `b2f7d1af3921d31cbd961d2c43b44aa0cd6ab3fdafe03d602c33358ed6233078` 的新位流**仅配置到 FPGA SRAM**。OpenOCD 通过独立 JTAG 读到 CPU TAP `0x10002fff`、写控制器初始状态 0，并把 `ram_writer_smoke.elf` 加载到 RAM `0x80000000` 运行。15 秒后，控制器命令和状态均为 `2`（单字节编程完成且无 error），Flash 读窗 `0x30060000` 返回 `0x2155434d`，即小端 `MCU!`。写后整片备份 `ef2_internal_flash_20261021-123640_82ef80e3.bin` 的 SHA256 为 `b13c4922e1678c26b4b63550c81a5a0c13741766a32ab74ed650ee168b15ba77`；与写前逐字节比较，**只在物理 `0x60000..0x60003` 发现 `FF FF FF FF -> 4D 43 55 21`，其余 524,284 字节不变**。OpenOCD 操作日志为 `build/flash/hardware_mcu_flash_write_20261021.log`。本轮没有同步捕获 UART `P`，因此成功判据是状态寄存器、读窗和全片前后对比。该段记录的是 10 月 21 日操作；新版位流随后于 10 月 22 日持久烧入。

烧写前两次 CPU JTAG 全片备份与一次普通调试位流下的 TD 原生读回逐字节一致，SHA256 均为 `3a60a97c00ade9b34a6834f52b016476252d5ea5bdf2940ef7c8e5c3cede00cf`。TD `download -mode program_spi` 完成配置位流持久烧写；写后 512 KiB 备份 `build/flash/backups/td_after_bitstream_program_20261020.bin` 的 SHA256 为 `72f24b2f0227e5854d033afefb711f431169674a0a95788997b7c169b1d5b20a`，新增配置字节止于 `0x3ed0e`，MCU 用户区保持原样。TD `download -mode program_spibin -bin hello.xip.bin -start_addr 0x50000` 报告仅擦除第 80 个 4 KiB 扇区；写后备份 `td_after_xip_program_debug_20261020.bin` 的 SHA256 为 `f4747274c3ec9773d4e3ce7d60c5179357d95cb50cf56c9382c32a9a2ede925c`，全片比较只发现预期 192 字节改变。

TD `read_flash` 必须在普通调试位流运行时执行：`persist_bit=0` 的 Flash 变体运行时曾产生误导性的全 `FF` 读数。临时把 Flash 变体配置到 FPGA SRAM 后，COM3 收到 `BOOT FLASH`、`HELLO,YUAN!`；OpenOCD 读到 CPU TAP `0x10002fff`。应用循环计数持续增长，SPI 事务数在每次 JTAG 恢复后的 100 ms 与 2 s 运行窗口均只增 16，符合缓存重填后命中。用户后来确认开发板断电至少 3 秒并重新上电，未用 TD 下载位流；一次探针返回全 1，后续探针读到 CPU TAP `0x10002fff`，PC `0x3005009c` 位于 XIP 应用区，RAM 循环计数在 1 秒内从 `0x350c71a` 增至 `0x364a82a`，SPI 事务计数从 `0x7d` 增至 `0x8d`。这支持 Flash 自动装载与 XIP 运行，但首次探针失败原因未定；本轮 COM3 同步窗口未捕获启动横幅。重插板卡供电时其他调试线仍连接，未验证完全独立供电场景。

## 单启动分区（不考虑 Multi Boot）

EF2L45LG144B 的内置 GD25Q40B SPI Flash 为 4 Mbit，即 512 KiB。项目采用下面的**单启动软件分区约定**；边界按 64 KiB 对齐，也按芯片的 4 KiB 擦除扇区对齐。本节暂不为 Multi Boot 分配第二份位流。

| 物理 Flash 字节偏移（含首尾） | 大小 | CPU 只读映射 | 归属 |
| --- | ---: | --- | --- |
| `0x00000..0x4FFFF` | 320 KiB | `0x30000000..0x3004FFFF` | FPGA 单启动配置预留区；不允许 MCU 软件或应用烧写流程擦除/覆盖 |
| `0x50000..0x7FFFF` | 192 KiB | `0x30050000..0x3007FFFF` | MCU 用户区，可存放 XIP 程序及以后定义的数据 |

MCU 用户区目前只有前 64 KiB（物理 `0x50000..0x5FFFF`）定义为 `XIP1` 演示程序槽：前 16 字节为头，程序入口为 CPU `0x30050010`；后 128 KiB（物理 `0x60000..0x7FFFF`）**暂未分配**，不是现有 BootROM 能自动启动的第二个程序区。XIP 读桥可读取整个 512 KiB，直接向 `0x30000000` Flash 窗口写入仍返回总线错误。新写控制器另占 `0x40004000` 寄存器页，并且只接受 `0x50000..0x7FFFF` 用户区地址；它不会赋予配置区写权限。

本地 `stage3_flash.bit` 实测 **259,359 字节（约 253.3 KiB）**，小于 320 KiB 预留区，按文件长度算还余 68,321 字节。这只是必要的离线尺寸检查：`.bit` 文件大小不等于 TD 实际写入 Flash 的最终占用、元数据或擦除范围。选择 `0x50000` 也与[安路 MCU Flash Cache 示例](https://tech.anlogic.com/Public/Uploads/ueditor/upload/file/20230707/1688692342948968.pdf)的应用起始偏移一致；该示例本身不证明烧写安全。本次写前/写后 512 KiB 整片读回逐字节比较确认，应用写入未改变配置区；以后更新仍须重复检查。

## 目标与现状

新变体 `stage3_flash_top` 将 CPU 地址 `0x30000000..0x3007ffff` 映射到片内 Flash 物理 `0x00000..0x7ffff`。数据总线访问该窗口会直接读取 SPI Flash；写操作返回总线错误。CPU 的 `IBusCachedPlugin` 已配置为 4 KiB、32 字节行、`wayCount = 1`；从该窗口取指时由现有的 1-way 指令缓存负责缓存。Flash 桥本身没有另建数据缓存。只读寄存器 `0x40003000` 记录 SPI 读事务次数，用于观察缓存是否命中；写入该地址返回总线错误。CPU 复位仍从 `0x20000000` 的 8 KiB BootROM 开始，BootROM 根据 Flash 镜像头决定 XIP 或 UART 下载。

### MCU 总线 SPI 写控制器（实板已验证）

`stage3_flash_writer` 位于 Wishbone 外设页 `0x40004000`。它与原 XIP 读桥互斥使用同一组 `EF2_PHY_INTFLASH` 引脚。CPU 写命令后，硬件顺序发送 SPI `06h` 写使能、`05h` 状态读取并核对 WEL、`20h` 4 KiB 扇区擦除或 `02h` 页编程（旧版一次一字节；当前 SRAM 临时新版一次最多 16 字节），再反复用 `05h` 查询 WIP 直到完成；25 MHz 系统时钟对应 12.5 MHz SPI，操作超过约 1 秒会报错并停止等待。控制器**没有**块擦除、整片擦除或写状态寄存器指令。

| CPU 地址 | 读 | 写 |
| --- | --- | --- |
| `0x40004000` | 19 位物理 Flash 字节偏移 | 设置偏移；只接受空闲时的 32 位字写 |
| `0x40004004` | 低 8 位待写字节 | 旧模式设置单字节数据；候选版在暂存模式下每次写入追加一个缓冲字节 |
| `0x40004008` | 最近命令：`1` 擦除、`2` 单字节编程；候选版另有 `3` 开始暂存、`4` 提交批量 | 对应启动或暂存操作 |
| `0x4000400C` | bit0 `busy`、bit1 `done`、bit2 `error`、bits15:8 最近 Flash 状态；候选版增加 bit7 批量能力、bit3 暂存状态 | 空闲时写 bit1 清 `done`、bit2 清 `error` |

写命令必须使用物理偏移 `0x50000..0x7FFFF`；扇区擦除地址还必须 4 KiB 对齐。越界、非对齐、忙时改参数等会置 `error`，**不会发送对应擦写指令**。当前固件驱动 [`fw/flash/flash_writer.c`](../../fw/flash/flash_writer.c) 提供 `flash_erase_sector` 与 `flash_program_bytes`，先检查范围与 0->1 冲突，完成后经只读窗口核对数据。`fw/flash/ram_writer_smoke.c` 是 RAM 测试程序：拒绝配置区擦除，在物理 `0x60000` 擦除一个扇区、写入 `MCU!`、拒绝未擦除的 0->1 写入，再通过 UART 报告结果。配置 Flash 中持久位流仍走单字节模式；当前临时配置到 SRAM 的新版将连续数据分成最多 16 字节的批量事务，仍受 Flash 256 字节页边界约束。

**执行写操作的程序和待写镜像都必须驻 RAM，不能在正被改写的 XIP 区运行/取数据。**擦除会把整个 4 KiB 扇区变成 `FF`；改一个字节也不能跳过该扇区现有数据的备份、擦除与回写。写控制器只用地址门禁保护配置区，不自动处理掉电中断、镜像原子更新或 Icache 失效。更新 XIP 应用后应复位并重新执行 BootROM 的头/CRC 校验，不能继续运行旧缓存中的指令。实板已验证独立 `0x60000` 扇区的 MCU 擦写；**尚未验证用 MCU 原地更新正在运行的 XIP 程序**。

### 通过 OpenOCD 的 CPU JTAG 烧录 MCU 用户区

`script/openocd/program-user-flash.tcl` 不需要另开 CPU 固件：OpenOCD 暂停 CPU，经 JTAG 对 `0x40004000` SPI 写控制器发命令，并从 `0x30000000` 读窗校验。输入是原始二进制文件与**物理** Flash 字节偏移；只允许完整落在 `0x50000..0x7ffff`。每个涉及的 4 KiB 扇区在首次写入前由 OpenOCD 备份。脚本保留镜像覆盖范围之外的旧数据；若某字节需要从 0 变 1，就先擦除该扇区，再重新编程扇区内所有非 `FF` 数据。默认只做备份和计划，不擦写；仅显式设置 `flash_confirm PROGRAM_USER_FLASH` 才执行。写后逐扇区读回，必须与预期内容完全一致。备份与读回文件由 `flash_backup_prefix` 指定，**每次运行用新的前缀**，脚本拒绝覆盖旧文件。

先确认 FPGA 正运行含写控制器的位流且 CPU JTAG 可连接；当前已临时配置 16 字节版，但掉电后会恢复旧版。要重复 16 字节测试，须重新只配置 FPGA SRAM，并先核对位流哈希，不能把本地新文件误当板上已装载版本。例如先只读规划当前 XIP 镜像（此镜像如果与板上相同会报告 0 字节变化）：

```powershell
$ocd = 'D:\risc-v\toolchain\jtag\xpack-openocd-0.12.0-7\bin\openocd.exe'
& $ocd -f script/openocd/board-iotelic-ft2232h.cfg -c 'set flash_image build/flash/hello.xip; set flash_offset 0x50000; set flash_backup_prefix build/flash/backups/my_plan_01; source script/openocd/program-user-flash.tcl'
```

核对 `FLASH_PLAN` 的扇区、变化数量、是否擦除及备份后，持久烧写须使用新的备份前缀并追加确认变量：

```powershell
& $ocd -f script/openocd/board-iotelic-ft2232h.cfg -c 'set flash_image build/flash/hello.xip; set flash_offset 0x50000; set flash_backup_prefix build/flash/backups/my_program_01; set flash_confirm PROGRAM_USER_FLASH; source script/openocd/program-user-flash.tcl'
```

只有 `FLASH_PROGRAM_OK` 表示本次确有字节变化且相关扇区读回一致；`FLASH_NO_CHANGE` 表示未执行擦写。状态 bit7 为 1 时默认使用 16 字节页写；显式设置 `flash_force_byte 1` 可在同一新版硬件上强制旧单字节路径作对照。`FLASH_WRITE_TIME_MS` 只覆盖该扇区擦除/编程，不包括连接、备份与读回。脚本在结束后让 CPU 保持暂停，不自动从原 XIP PC 恢复执行。更新 XIP 应用还需要事先生成有效头/CRC、确认镜像边界，并在完成后复位 CPU 验证 BootROM 启动；本脚本不负责持久烧写 FPGA 配置位流。

2026-10-21 OpenOCD 实板直接编程：写前全片备份 `ef2_internal_flash_20261021-145035_47c09037.bin` 长 524,288 字节、SHA256 `b13c4922e1678c26b4b63550c81a5a0c13741766a32ab74ed650ee168b15ba77`；脚本在物理 `0x60004` 写入四字节 `JTAG`，输出 `FLASH_SECTOR_OK sector=0x60000 erase=0 programmed=4` 和 `FLASH_PROGRAM_OK`，日志为 `build/flash/openocd_jtag_program_20261021.log`。写后整片备份 `ef2_internal_flash_20261021-145239_6934cf9b.bin` 的 SHA256 为 `ccaa1e20a58f80ec8ee78769715ae21912f8c705437075af7be61bd2cf87efa7`。逐字节比对仅 `0x60004..0x60007` 四字节由 `FF` 变为 `4A 54 41 47`，其余 524,284 字节完全不变。

同日经用户再次授权，先只读核对板上仍为 `MCU!JTAG`、写控制器空闲、恢复镜像为四个 `FF`，然后以 `build/flash/jtag_flash_restore.bin` 对物理 `0x60004` 执行持久恢复。`build/flash/openocd_jtag_restore_20261021.log` 记录 `FLASH_PLAN sector=0x60000 changed=4 erase=1`、`FLASH_SECTOR_OK sector=0x60000 erase=1 programmed=4`、`FLASH_PROGRAM_OK`；擦除前/后扇区文件为 `build/flash/backups/openocd_restore_program_20261021_60000.before.bin` 和 `.after.bin`。读回扇区只剩 `MCU!` 四个非 `FF` 字节，证明脚本在 0->1 需求下擦除后保留了同扇区原有数据。随后单次连续 512 KiB JTAG 导出一次报错、一次超时，两份 `.partial` 均不计作成功备份；改为八个独立 64 KiB 只读段 `build/flash/backups/restore_verify_chunk0_20261021.bin` 至 `chunk7`，每段 OpenOCD 退出码 0、TAP 正确、日志无错误、长度 65,536 字节。八段逐字节覆盖整片，与写入 `JTAG` 前备份 **0 字节差异**，包括配置区、XIP 程序和恢复的测试扇区。长时间单次 JTAG 扫描仍不稳定，后续备份宜分段并逐段检查；这不影响本次分段全片比对结论。

Flash 桥使用标准 SPI `03h` 单线读命令，一次读取一个 32 位字；25 MHz 系统时钟产生 12.5 MHz SPI 时钟。顶层通过 `EF2_PHY_INTFLASH` 访问内部管脚，`WP#`/`HOLD#` 保持高电平。该变体位流生成时显式使用 `bitgen -g {persist_bit:0}`，以开放用户模式的 Flash 管脚。此选项由本机 TD 5.6 接受；实板已读回并运行 Flash 中的 XIP 应用，详见上面的验收记录。

Flash BootROM 在复位后先检查物理 `0x50000` 处的 16 字节 `XIP1` 头（长度、入口、CRC32），校验通过便跳到 CPU 地址 `0x30050010`。`HELLO,YUAN!` C 应用链接在该地址，`.text/.rodata` 驻 Flash、栈和两个观测计数驻 RAM；`0x80000000` 是持续增长的循环次数，`0x80000004` 保存程序最近读取的 SPI 事务次数。当前镜像没有需要复制的 `.data`。头不存在或校验失败时仍进入原 UART 下载路径。`0x50000` 是上述单启动分区约定的应用槽起点；192 字节应用已经写入并经整片读回确认。

## 已通过的离线检查

- `script/run_flash_sim.ps1`：SPI 命令、首字、物理 `0x40100`、配置/MCU 分界两侧 `0x4FFFC`/`0x50000`、演示槽分界两侧 `0x5FFFC`/`0x60000`、末字、大小端和复位中止检查通过；完整 CPU/BootROM/Flash/UART 仿真输出 `BOOT FLASH`、`HELLO,YUAN!`，CRC 损坏或镜像头无效时回退 `BOOT UART 64K`。Flash 循环执行期间 RAM 次数增长、SPI 事务数不变，且 CPU 经 MMIO 读到的事务数与模型一致，验证了仿真中的 1-way 指令缓存命中。
- `script/run_flash_jtag_sim.ps1`：实际 OpenOCD 通过 remote-bitbang 扫描真实 CPU RTL 的 TAP `0x10002fff`，经 Program Buffer 读取仿真 Flash 窗口 `0x30050000` 的 32 字节，并与 XIP 镜像逐字节一致。日志和导出文件在本地 `build/flash/flash_jtag_*`、`jtag-image-head.bin`；这验证了备份路径的 JTAG/CPU/总线/Flash 读桥连接，但仍是 RTL 仿真，不是实板全片备份。
- `script/build_flash_firmware.ps1`：BootROM `.text` 836B，XIP 应用 `.text` 174B、`.bss` 8B，192B 带头镜像 `build/flash/hello.xip`；ELF 入口 `0x30050010`，无 `.data`。打包时会校验 ELF 入口、可执行装载地址和导出 BIN 内容一致，避免链接地址与镜像头脱节。
- `script/build_flash_td.ps1`：独立工程综合、布局布线和位流生成通过，CPU 25 MHz/JTAG 1 MHz 时序报告为 0 setup、0 hold；3665/4480 LUT、10/12 BRAM。
- Python 主机测试 58 项通过，含 ELF/BIN 入口一致性、单启动分区边界、只读实板探针命令、Flash 工程与旧 UART/JTAG 工程隔离，以及 512 KiB 备份长度、占用范围、XIP 镜像 CRC/地址和全片写后读回对比。
- 2026-10-21 新增写控制器后，`script/run_flash_sim.ps1` 通过单字节编程、4 KiB 擦除、配置区及非对齐拒绝测试；真实 RV32 MCU 还从 RAM 运行 C 驱动，完成仿真 Flash `0x60000` 扇区擦写、逐字节读回，并拒绝配置区和不合法的 0->1 更新。原有 Flash XIP/CRC 回退整机测试仍通过。`script/run_flash_jtag_sim.ps1` 的 OpenOCD 读回仍通过，61 项主机测试通过；这些均是离线证据，不是实板烧写。
- TD 对此前**已烧入实板配置 Flash**的写控制器位流完成 25 MHz/JTAG 1 MHz 时序检查，0 setup/0 hold；最终面积为 3974/4480 LUT、10/12 BRAM。该历史位流长 259,359 字节，SHA256 `b2f7d1af3921d31cbd961d2c43b44aa0cd6ab3fdafe03d602c33358ed6233078`，于 2026-10-22 持久烧入配置 Flash 并通过 TD `verify_spi`；开发板单独重上电后 CPU JTAG 观察到 XIP 运行，完全脱离调试线的上电未测。它已不是当前本地 `build/flash/stage3_flash.bit`；后者是仅在 FPGA SRAM 上板验证的 16 字节批量版。2026-10-20 的 SHA256 `6c1d96051f40faab66d96c4c21f247c00f436be7add666c9825d20bb6a25c1a9` 属于更早的位流。构建输出在忽略的 `build/`，不随仓库发布。

## 烧写前只读检查（历史）

接好开发板供电和 AL-Link 后，先确认配置器可用，再运行 `script/configure_flash_fpga.tcl` 将新位流**仅配置到 FPGA SRAM**。独立 IoTelic FT2232H CPU JTAG 保持 H3 接线，使用 `script/openocd/probe-flash-read.cfg` 读取 Flash 首部、`0x40000`/`0x41000`、配置预留区末尾 `0x4FFF0..0x4FFFF`、MCU 用户区起点 `0x50000`、演示槽末尾 `0x5FFF0..0x5FFFF`、未分配区起点 `0x60000` 和器件末端。该脚本会暂停 CPU 以读取存储器，但没有 Flash 写命令。保存 TD、OpenOCD 原始输出及位流哈希，再核实单启动分区是否适用于实板现状。

完整只读备份入口为 `script/backup_flash_readonly.ps1`。先运行 `-PlanOnly` 检查路径；在确认支持 Flash 读窗的位流正在 FPGA 上运行、板卡持续供电后，去掉 `-PlanOnly` 才会通过 OpenOCD 暂停 CPU 并读取 Flash。默认将 512 KiB 分成八个 64 KiB 段，每段在独立 OpenOCD 会话中读两次；每次检查 CPU TAP、退出码、无 `Error:` 日志和精确长度，两次内容还必须逐字节相同。单次失败最多重试一次，默认单次超时 120 秒。所有段通过后才合成、检查 512 KiB 长度和 SHA256，并将 `.partial` 改名为正式 `.bin`；失败尝试、每段原文和 OpenOCD 日志保留在同名 `.segments` 目录，不把它们冒充完整备份。脚本仅只读，不擦写 Flash。

```powershell
.\script\backup_flash_readonly.ps1 -PlanOnly
.\script\backup_flash_readonly.ps1 -TimeoutSeconds 120
```

可用 `-ChunkBytes`（4..64 KiB、须整除 512 KiB）、`-ReadPasses`（2 或 3）和 `-MaxAttempts`（1..3）调整读取规模与重试次数。2026-10-21 新工具实板默认运行完成 16 次独立读取，正式文件 `build/flash/backups/ef2_internal_flash_20261021-214241_02b6a233.bin` 为 524,288 字节，SHA256 `b13c4922e1678c26b4b63550c81a5a0c13741766a32ab74ed650ee168b15ba77`，与写入 `JTAG` 前的完整基线逐字节一致；16 份原始分段和日志保留在对应 `.segments` 目录。双读一致能发现部分链路错误，但仍不能单独证明位流身份，也不能替代另一条读取路径的交叉验证。也可以用 TD 的 `FLASH READ` 模式独立导出后交给分析器，但不要选 `DIRECT FLASH READ`（它要求下载器直接接 Flash）。**全 `FF` 只能说明看起来未编程，不证明该区域可写**；仍须确认真实配置布局。

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

旧版位流和应用的持久烧写、整片读回、临时 SRAM 配置后的真实 Flash 取指与缓存观察已有实板证据。用户确认掉电重上电且未用 TD 下载位流后，CPU JTAG 观察到旧版 XIP 应用运行。2026-10-21 新版 MCU 写控制器位流只临时配置到 SRAM 并通过实板擦写；2026-10-22 新版位流随后持久烧入，用户再次确认开发板重上电且未用 TD 下载后，CPU JTAG 观察到 XIP 程序继续运行。两次重上电时调试线均连接，未验证完全脱离调试线的上电。

资料：本地 `D:/4.EF2 Family/TN401_安路ELF2 FPGA编程和配置使用说明.pdf`、`TN402_安路ELF2 FPGA内置FLASH读写.pdf`、`TN413_ELF2 DUAL BOOT功能使用指南.pdf`，以及 `D:/PotatoPie V3.0/例程/demo6_test_flash.7z`。
