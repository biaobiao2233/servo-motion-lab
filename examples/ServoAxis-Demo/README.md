# ServoAxis-Demo

TwinCAT 3.1 Build 4026 的 NC/PTP 单轴定位仿真示例。

**真实 NC 单轴仿真已运行；TwinCAT 内置面板的 16 项交互检查通过。**
详见 [当前内置面板证据](../../evidence/2026-10-13-native-visualization/README.md) 和
[原单轴验收与曲线](../../evidence/2026-10-13-single-axis/README.md)。

## 工程结构

`src` 内的 GVL_Command 是命令入口，GVL_Motion 包含 AXIS_REF，GVL_Monitor 保存
在线反馈。GVL_Hmi / FB_HmiAdapter 把原生面板点击转换为命令，空闲时保留 ADS 命令入口。
FB_ServoAxis 周期调用 MC_Power、MC_Home、MC_MoveAbsolute、MC_Stop、MC_Reset，
负责手动/自动状态机；MAIN 每周期调用适配层和控制块，复制实际 NC 位置、速度与状态。
定时器只作超时保护，完成由功能块反馈决定。

原生工程通过官方 Automation Interface 生成。厂商 DLL、SDK 互操作程序集、
许可证和机器生成的完整工程保留本地；公开仓库提供 ST 与工具源码。
`Create-DemoProject.ps1` 需要本机 XAE 及 Automation Interface 互操作程序集，
可通过 `-InteropAssembly` 指定。本机用户态目标要求 **TwinCAT OS (x64)**。
首次创建会导入 `visu/ServoDashboard.TcVIS`，已在新目录中实际创建、检查及构建成功。
`-BuildExisting` 同步 ST，不替换已有画面；旧工程需要手动导入 TcVIS，或生成新工程。

## TwinCAT 内置面板

打开自己生成的 `ServoAxisDemo.sln`，在解决方案树展开
`PLC → ServoPLC → ServoPLC项目 → VISUs`，双击 `ServoDashboard`。
先核对专用目标、启动 Runtime，再用 PLC 菜单登录，确认 PLC 为 Run。
画面离线时用于编辑，在线登录后才是可操作的实时画面。展示前读取状态并确认周期计数增加。

1. 点「自动演示 30 → 80 → 0 mm」：适配层先等轴使能反馈，执行虚拟回零与三次定位。
   观察实际位置、速度、步骤、Busy/Done 和完成次数。
2. 点「定位到 80 mm」，运动中点「运动停止」。速度降到零后显示停止保持；
   点「释放停止保持」才允许继续定位。
3. 点「发送 101 mm · 越界拒绝」：Error 成立、ErrorID 为 `0xA001`，位置不改变。
   点「错误复位」，不会自动重新运动。结束时定位到 0 mm 并撤销使能。

手动模式先「轴使能」→「虚拟回零」，等待反馈；点击目标或速度数值，键盘输入后按 Enter，
再点「执行手动定位」。目标输入范围 0～100 mm，速度输入范围 1～50 mm/s。
数值显示的「已接受目标」与待发送的手动目标分别保存，修改输入不会立即发起运动。
不满足状态条件的按钮会禁用，停止保持时定位按钮不能操作。

该画面运行在 XAE 内置 Visualization；本轮未配置独立 PLC HMI / Web HMI。
它显示 NC 仿真反馈；无驱动器时没有真实电流、温度、扭矩或 EtherCAT 状态。
面板交互配置改编自 MTCS，来源、修改及 LGPL 许可见 [第三方说明](../../third_party/MTCS/README.md)。
官方配置依据：[输入动作与数值输入](https://infosys.beckhoff.com/content/1033/tc3_plc_intro/3524245643.html)。

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

优先使用上面的内置面板。以下命令保留为调试与自动验收入口；不要同时从两处发命令。

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

试用许可短期有效，展示前需在本机确认有效期，必要时通过官方界面重新生成并复演。
整机 Windows 重启、原生故障/复位失败路径仍待验。

需求与保护边界见 [当前有效需求](../../docs/REQUIREMENTS.md)。
没有真实电机、驱动器和 EtherCAT 硬件；不以本示例声明实际设备或安全功能已验证。
