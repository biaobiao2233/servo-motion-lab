# ServoAxis-Demo

TwinCAT 3.1 Build 4026 的 NC/PTP 单轴定位仿真示例。

**2026-10-13 已完成最低功能运行验收：14 项检查通过。**
详见 [实际反馈记录与曲线](../../evidence/2026-10-13-single-axis/README.md)。

## 工程结构

`src` 内的 GVL_Command 是命令入口，GVL_Motion 包含 AXIS_REF，GVL_Monitor 保存
在线反馈。FB_ServoAxis 周期调用 MC_Power、MC_Home、MC_MoveAbsolute、MC_Stop、
MC_Reset，负责手动/自动状态机；MAIN 每周期调用它并复制实际 NC 位置、速度与状态。
定时器只作超时保护，完成由功能块反馈决定。

原生工程通过官方 Automation Interface 生成。厂商 DLL、SDK 互操作程序集、
许可证和机器生成的完整工程保留本地；公开仓库提供 ST 与工具源码。
`Create-DemoProject.ps1` 需要本机 XAE 及 Automation Interface 互操作程序集，
可通过 `-InteropAssembly` 指定。本机用户态目标要求 **TwinCAT OS (x64)**。

## 启动和复演

使用 Windows PowerShell 5.1 x64，在仓库根目录执行；示例安装路径应按自己电脑调整。
启动专用实例的终端须保持开着：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Start-DemoRuntime.ps1 -TwinCatRoot "D:\Beckhoff\TwinCAT\3.1"
```

在另一个终端请求运行已保存的 Boot 配置（需要有效 PLC/NC 许可）：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Set-DemoRuntimeState.ps1 -TwinCatRoot "D:\Beckhoff\TwinCAT\3.1" -State Run
```

首次使用需先创建并构建原生工程，确认目标为专用 `Um - ServoAxisDemo`，
AMS 标识 `127.0.0.1.10.22`，通过官方界面激活配置、生成试用许可并由本人输入安全码。
仅出现进程或 Run 图标不足以证明 PLC 已运行；用 `Read-DemoStatus.ps1` 检查周期计数增加。
`Install-DemoBoot.ps1` 可在专用实例停止后，备份并安装与成功构建报告匹配的 Boot 文件。

## 现场演示

```powershell
# 使能、虚拟回零，执行 30→80→0 mm 自动序列
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Invoke-DemoCommand.ps1 -TwinCatRoot "D:\Beckhoff\TwinCAT\3.1" -Command Auto

# 读取实际反馈
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Invoke-DemoCommand.ps1 -TwinCatRoot "D:\Beckhoff\TwinCAT\3.1" -Command Status

# 运动中停止；等 StopDone，再显式释放停止保持
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Invoke-DemoCommand.ps1 -TwinCatRoot "D:\Beckhoff\TwinCAT\3.1" -Command Stop
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Invoke-DemoCommand.ps1 -TwinCatRoot "D:\Beckhoff\TwinCAT\3.1" -Command ReleaseStop
```

手动操作：`Enable` → `Home`，等 Homed/Step=20 后执行 `Move -Position 30 -Velocity 20`。
用 `Move -Position 101` 演示越界拒绝，错误 A001 后执行 `Reset`，复位不会自动重新启动。
演示结束用 `Disable` 撤销使能；`Stop-DemoRuntime.ps1` 只退出自有实例。
完整验收工具是 `Invoke-DemoAcceptance.ps1`，原始 JSON/CSV 保存到 `.local/evidence`。

在线打开 PLC 的 GVL_Monitor：ActualPosition、ActualVelocity、TargetPosition、Step、Enabled、
Busy、Done、Error、ErrorID。保存曲线的实际采样间隔约一秒，属于顺序 ADS 观测，
不能宣称为同一 PLC 周期的原子快照或高精度动态测量。

## 面试常问

- **位置怎么来的？** 从 NC 的 Axis.NcToPlc 读取；运动由官方 NC 与 MC 功能块执行。
- **为什么不按延时判完成？** 距离和动态参数改变完成时间，状态机必须等 Busy/Done/Error。
- **回零没有开关？** MC_Direct 直接建立模拟坐标零点；不代表机械寻原点动作已经验证。
- **停止后为什么要释放？** MC_Stop 的 Execute 保持会锁轴，Done 与 Busy 可同时为真；
  ReleaseStop 撤销 Execute 后还要等 Busy 解除。
- **限位和复位怎么处理？** 应用拒绝 0～100 mm 外的新目标，NC 也配置软件限位；
  应用错误与原生 ErrorID 分开。本次验证应用越界错误和 MC_Reset Done，原生故障注入待验。
- **以后接真伺服？** 独立配置驱动器、编码器、EtherCAT、比例、方向与回零，再验证
  整定、负载和安全系统；仿真结果不能延伸为这些硬件项目通过。

本机试用许可到 **2026-10-20**，22 日展示前需通过官方界面重新生成并复演。
整机 Windows 重启、原生故障/复位失败路径仍待验。

需求与保护边界见 [当前有效需求](../../docs/REQUIREMENTS.md)。
没有真实电机、驱动器和 EtherCAT 硬件；不以本示例声明实际设备或安全功能已验证。
