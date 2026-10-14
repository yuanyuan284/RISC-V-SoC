# Stage 1：最初的低资源实验

这是历史阶段。当前主线与容量见根目录 [README](../../README.md)。本阶段的 `rtl/stage1/VexRiscv.v` 是精简实验 CPU，只实现 LUI、ADDI、SW、JAL 和 x0..x7 寄存器，不支持普通 GCC 编译的 C 程序。它不能代替 Stage 2/3 的完整 VexRiscv。

Stage 1 通过 Wishbone 访问小容量 ROM/RAM 与 UART，使用 EF2 PLL 的 25 MHz 系统时钟。`script/make_demo_firmware.py` 用这四种指令产生输出串口文字的程序，历史演示文字为 `Hello from C!`，文字本身不证明程序由 C 编译。

## 源码与构建

- `rtl/stage1/`：CPU、顶层、互连与逻辑 RAM。
- `rtl/common/`：UART、FIFO、自定义 JTAG 原型。
- `tb/stage1/VexRiscv_tb.v`：精简 CPU testbench。
- `script/build_stage1_firmware.ps1`：生成 `build/stage1/firmware/` 的演示 HEX。
- `script/build_td.ps1`：从源码生成 TD 工程并构建历史顶层。

从仓库根目录执行：

```powershell
.\script\build_td.ps1 -PrepareOnly
.\script\build_td.ps1
```

位流和报告在 `build/stage1/`，不提交到 Git。脚本仅在时序报告 0 setup/hold 错误后复制 `stage1_verified.bit`；新的构建仍需单独板测，不能直接套用旧结果。

## JTAG 原型边界

`rtl/common/jtag_wb_loader.v` 是私有 69 位扫描协议，不是标准 RISC-V Debug Module。最低位为写使能，bits 4:1 为字节选择，36:5 为地址，68:37 为数据；TDO 返回签名 `0x4a544147`、完成状态和读数据。控制地址 `0xfffffffc` 的 bit 0 选择 RAM 启动，bit 1 保持 CPU 复位。应先保持复位、写入并回读 RAM，再选择 RAM 启动并释放 CPU。

用户链路 IR 仍未确认，硬件探测候选没有返回签名。`bringup_jtag.tcl`、`probe_loader.tcl`、`probe_candidates.tcl`、`program_ram.tcl` 保持禁用。`script/jtag/` 的 IDCODE/USERCODE 扫描只用于只读识别，不能证明自定义加载器工作。详见 [Stage 2 历史](../stage2/README.md) 和 [ChipWatcher 记录](../stage2/CHIPWATCHER_TIMING.md)。

旧 TD GUI 工程、探测文件、仿真缓存及历史位流仅保留本地 `build/stage1/td_project/` 供诊断，当前构建不再依赖这些文件。
