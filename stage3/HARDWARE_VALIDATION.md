# Stage 3 实板验证记录

日期：2026-10-13。板卡：EF2L45LG144B；下载器：AL-Link Mini；串口：COM3，115200 8N1。

## 验证对象

- 位流：`stage3/build/stage3_uart.bit`，SHA256 `7dbaef7ebca686504bd38d883afb5a27c88330588274da6c4d94e2ce5b637cf7`。
- BIN：`stage3/build/app_a.bin`，42424B，SHA256 `91fe602c5d7b3f1a6a866512f5f2b57a21b12c16ef0eeb80bfa87a897ba74f03`。
- 第二份BIN：`stage3/build/app_b.bin`，42424B，SHA256 `0a34b5daed826de3a87e822180bbdc135be6cd1b85042086d9bc164b464bbd93`。
- 存储配置：ROM 8192B，RAM 65536B，应用入口 `0x80000000`，最高4KiB预留栈。
- 软件：RV32IM/ILP32 GCC + newlib nano，链接真实 `printf`、`snprintf` 和 `_printf_float`。

## 实际操作和结果

先启动 `tools/uart_upload_stage3.py stage3/build/app_a.bin --port COM3 --boot-timeout 180 --expect-text 'STAGE3 PASS'`，确认COM3监听已就绪，再以TD调用 `tools/configure_stage3_fpga.tcl`。TD仅配置FPGA易失性逻辑，没有Flash操作。`stage3/build/configure_stage3.log` 记录芯片验证和配置成功，工具退出码0。

上传器会话94112实际收到BootROM新横幅并逐字节上传，最终退出码0。以下为该会话输出的文字记录，不是后续新采集的串口原始日志：

```text
Uploaded 42424/42424 bytes
APP 1: id=1 signed=-42 hex=001234ab str=form %
RAM=65536 ROM=8192 data=1234 bss=0 errors=0
FLOAT=3.25
STAGE3 PASS
BootROM accepted CRC and application output was verified.
```

上传器仅在收到CRC成功标志 `G` 后接受应用输出。应用打印上述文本前已执行14KiB上部RAM测试区的逐字读写，检查 `0x8000c000`、`0x8000e000` 附近的byte/halfword写回以及 `.data`、`.bss` 状态。因此这次结果支持“BIN经BootROM写RAM、CRC通过后跳RAM执行、真实格式化输出”的实板结论。

## 其他证据及范围

第二次启动app B上传器并重新配置**相同位流文件**，工具均退出码0。COM3完整输出由 `Tee-Object` 保存到 `stage3/build/app_b_hardware.log`，配置记录为 `configure_stage3_b.log`。实际应用输出：

```text
APP 2: id=2 signed=-42 hex=001234ab str=form %
RAM=65536 ROM=8192 data=1234 bss=0 errors=0
FLOAT=3.25
STAGE3 PASS
```

随后运行 `tools/validate_stage3_hardware.py`，重新配置同一位流以启动BootROM。`stage3/build/protocol_hardware.log` 保存六类错误帧和恢复执行的实板结果，测试与配置工具退出码均为0：

```text
PASS: zero length rejected; BootROM recovered
PASS: oversized image rejected; BootROM recovered
PASS: unaligned length rejected; BootROM recovered
PASS: wrong entry rejected; BootROM recovered
PASS: wrong magic rejected; BootROM recovered
PASS: corrupted CRC rejected
Application output: b'APP A: UART loaded C!'
PASS: valid BIN executed after all six rejected frames
```

最后的恢复测试使用144B旧Stage 2短BIN，它实际运行在新的Stage 3硬件中；完整newlib格式化输出由前面的两份42424B应用证明。板卡最后停留在该短应用运行状态，FPGA配置仍为Stage 3。

`artifact_verification.json` 记录ELF装载字节、BIN、Intel HEX、RTL word HEX、物理ROM INIT、UART数据帧的一致性和入口/堆栈符号检查。TD `stage3_uart.timing` 为0 setup/hold错误，资源报告包含1块256K、1块128K、6块32K及CPU使用的10块9K BRAM。功能存储模型测试覆盖全8KiB ROM、全64KiB RAM、16种byte enable、bank边界及reset；13项新旧上传器单元测试通过。

本次应用BIN不是最大60KiB映像。全64KiB内存逐字覆盖来自功能模型测试；实板应用覆盖自身代码/数据、上部14KiB测试区和栈访问，不能写成实板全地址穷举。两项真实UART线Icarus长仿真未完成，在实板成功后终止，不计为通过；对应标准波特率协议、错误恢复和应用输出已经由实板测试覆盖。本轮未测试Stage 3不重新配置FPGA、仅按SW2换载。用户明确提出的构建/下载/跳转/容量/格式化目标已完成；没有继续运行的仿真、TD或串口测试会话。
