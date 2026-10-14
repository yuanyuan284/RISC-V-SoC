# 完整 VexRiscv CPU 来源

Stage 2/3 使用完整 VexRiscv，Stage 1 的 `VexRiscv.v` 是另一个精简实验实现。

`GenVexRiscv.scala` 来自 [rschlaikjer/fpga-3-softcores](https://github.com/rschlaikjer/fpga-3-softcores/tree/3ca2e1c97f3490859a627ffeec8824ba2a43d205/vendor/vexriscv)，原作者许可证见本目录 `LICENSE.md`。配置包括 4 KiB 指令缓存、无数据缓存的 DBusSimple、迭代乘除法、动态复位向量，以及指令/数据 Wishbone 端口。

本项目已验证的生成 RTL：

- 文件：上游固定版本 `3ca2e1c97f3490859a627ffeec8824ba2a43d205` 中的 `vendor/vexriscv/VexRiscv.v`。
- 大小：200418 字节。
- SHA256：`086f0d8f13c384d0f1c46d102aaf6eedc258664bed87693dde2879a4c7873f66`。
- 文件头标明 SpinalHDL v1.4.0，git head `ecb5a80b713566f417ea3ea061f9969e73770a7f`，生成日期 2020-08-23。

从仓库根目录下载并校验后设置构建输入：

```powershell
New-Item -ItemType Directory -Path build/cpu -Force | Out-Null
$cpuUrl = 'https://raw.githubusercontent.com/rschlaikjer/fpga-3-softcores/3ca2e1c97f3490859a627ffeec8824ba2a43d205/vendor/vexriscv/VexRiscv.v'
Invoke-WebRequest -Uri $cpuUrl -OutFile build/cpu/VexRiscv.v
$expectedHash = '086f0d8f13c384d0f1c46d102aaf6eedc258664bed87693dde2879a4c7873f66'
if ((Get-FileHash build/cpu/VexRiscv.v -Algorithm SHA256).Hash -ne $expectedHash) {
    throw 'CPU RTL SHA256 mismatch'
}
$env:VEXRISCV_SOURCE = (Resolve-Path build/cpu/VexRiscv.v).Path
```

生成 RTL 保留于已忽略的 `build/cpu/`。若需要改变 CPU 配置，应在兼容的 VexRiscv/SpinalHDL 工程中集成本目录 Scala，再重新生成并验证接口、缓存行为、仿真和时序。本次整理没有重新执行 Scala 生成流程，也不保证任意最新版本的生成器产生相同 RTL。
