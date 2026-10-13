# Stage 3: 8 KiB BootROM + 64 KiB RAM + UART C application download

## 目标和状态

FPGA 中的 VexRiscv 从 `0x20000000` 的 8 KiB BootROM 启动。BootROM 以115200 8N1从UART接收扁平BIN，写入 `0x80000000` 起的64KiB RAM，核对CRC32后跳转 `0x80000000`。同一位流换应用仅需复位并重新上传BIN。RAM断电失效；没有Flash持久化或自定义JTAG依赖。

截至2026-10-13：GCC/objcopy产物、ELF/BIN/Intel HEX一致性检查、TD布局布线与时序、整段ROM/RAM的功能模型测试已经完成。`stage3_uart.bit` **已实板验证 app A 和 app B 的42424B BIN 下载、CRC成功、RAM执行及newlib格式化输出**，包括 `FLOAT=3.25`、`errors=0`、`STAGE3 PASS`。六类非法帧拒绝和有效BIN恢复执行也已板测。记录见 `HARDWARE_VALIDATION.md`。两项 Icarus 真实UART线长仿真未完成；相应协议与执行功能已由标准波特率实板验证，长仿真不作为已通过证据。Stage 3仅SW2换载属于待补充的演示测试。旧 `stage2_uart.bit` 保留为历史版本。

## 构建与离线检查

从项目根目录执行：

```powershell
.\tools\build_stage3_firmware.ps1
python .\tools\verify_stage3_artifacts.py
.\tools\run_stage3_sim.ps1 -Test memory
.\tools\run_stage3_sim.ps1 -Test smoke
.\tools\run_stage3_sim.ps1 -Test uart
.\tools\build_stage3_td.ps1
```

`bootrom.elf/.bin/.hex` 和 `app_a/b.elf/.bin/.hex` 在 `stage3/build`。`.hex` 是 **Intel HEX**，供检查/其他工具使用；真正经UART发的是 `.bin`。RTL ROM 初始化采用另一个 `bootrom.words.hex` / `bootrom_init.vh`，不是Intel HEX。完整UART仿真传两份42424B BIN；为缩短运行时间，对UART预分频器做**仅仿真**加速。`smoke` 保持生产115200波特率，测试短映像、非法长度和CRC拒绝。功能BRAM模型不等于厂商时序模型；位流时序另由TD检查。

TD报告中8KiB ROM/64KiB RAM使用1块256K、1块128K、6块32K原语，setup/hold错误均为0。另有VexRiscv综合告警，不能把时序通过表述为实板功能通过。

## 固件、内存与输出

| 地址 | 用途 |
| --- | --- |
| `0x20000000..0x20001fff` | 8KiB BootROM，只读 |
| `0x80000000..0x8000efff` | 最多60KiB应用映像/数据/堆和测试区 |
| `0x8000f000..0x8000ffff` | 4KiB栈；初始SP=`0x80010000` |
| `0x40001000` | UART寄存器窗口 |

随工程提供的测试应用把 `0x8000b800..0x8000efff` 保留为14KiB RAM测试区，以验证物理bank边界；它不是任意C程序的通用链接脚本。普通应用需按自身text/data/BSS/堆/栈重新检查链接布局。当前测试应用BIN约42KiB；并非声明任何小于60KiB的C程序都能无修改运行。

应用通过RISC-V GCC链接真正的newlib nano，并用 `_write` 系统调用把 `printf` 输出送UART。示例验证 `%u`、`%d`、`%08x`、`%.4s`、`%%` 和 `%.2f`，还检查 `.data` 初始化、`.bss` 清零及RAM跨bank读写。这不是手写字符替代格式化函数；BootROM自身的协议字符输出则仍是逐字节发送。

## 协议与板测边界

BootROM发 `BOOT UART 64K\r\n`。上位机依次发送ASCII `RV32`、小端32位对齐后的BIN长度、入口 `0x80000000`、IEEE CRC32，随后发送BIN（必要时补零到4字节）。BootROM每收1字节回 `A`，头有效回 `H`，CRC通过回 `G` 并跳应用，错误回 `E` 并重新等待。长度上限61440B；仅长度/入口校验不能证明任意BIN的内部指令和地址有效。

项目内 `tools/vendor` 已装有 `pyserial`。板测需确认COM3未被Tera Term占用，并将**该版本位流**仅配置到FPGA易失逻辑；不要烧Flash。先启动下面命令等待新横幅，再通过另一终端调用TD的 `tools/configure_stage3_fpga.tcl`，或者在已经配置好该位流时按下并松开SW2：

```powershell
python .\tools\uart_upload_stage3.py .\stage3\build\app_a.bin --port COM3 --expect-text 'STAGE3 PASS'
```

第二次可用同一位流复位后上传 `app_b.bin`。app A/B 均已板测成功，本轮每次通过同一位流重新配置来复位；仅SW2复位换载尚未单独实测。现有 `tools/uart_upload.py` 属于 Stage 2，限制896B；Stage 3使用新的上传器。

错误处理的实板复现：先启动 `python tools/validate_stage3_hardware.py stage2/build/app_a.bin --port COM3 --expect-text 'APP A: UART loaded C!'`，再配置同一Stage 3位流。脚本测试零长度、超长、未对齐长度、错误入口、错误magic和错误CRC，之后发送144B短BIN并检查真实UART输出。此处Stage 2短应用仅用于恢复测试；42KiB/newlib格式化程序的板测日志为 `stage3/build/app_b_hardware.log`。
