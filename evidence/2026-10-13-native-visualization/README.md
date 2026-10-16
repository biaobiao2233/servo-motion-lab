# TwinCAT 内置面板运行验收

**原生面板 16 项交互检查 PASS；同一已运行 PLC 程序的 14 项控制回归 PASS。**
2026-10-13，UTC+08；TwinCAT XAE 3.1.4026.27、NC/PTP 用户态组件 3.1.5049、
Tc2_MC2 3.3.75.0、TwinCAT OS (x64)。没有电机、驱动器或 EtherCAT 硬件。

## 实际操作

界面测试向 XAE 原生 Visualization 画布发送点击，向其原生文本编辑框输入后按 Enter。
运动命令来自画面；另一个后台 ADS 读取器只用于观察和记录本轮反馈，没有用外部窗体替代画面。
控制回归另行从原有 ADS 命令入口执行，不与界面测试同时发命令。

| 界面检查 | 实际反馈 |
|---|---|
| 使能与虚拟回零 | Enabled/Homed/HomeDone 成立，实际坐标 0 mm |
| 目标 / 速度输入 | 原生文本框输入 45 mm、15 mm/s 后读回对应 PLC 变量 |
| 自定义手动定位 | 已完成计数增加，实际位置到 45 mm |
| 自动 30→80→0 mm | 完成计数增加 3、自动轮数增加 1，最终 0 mm |
| 手动 30 / 80 / 0 mm | 三次实际位置与完成反馈均成立 |
| 运动中停止 | 向 80 mm 运动时停止，停在约 22.40334 mm，速度降到零 |
| 停止保持时点击定位 | 禁用的按钮不能发起运动，停止保持与实际位置不变 |
| 显式释放 | 停止保持与 Busy 解除 |
| 101 mm 越界请求 | PLC 应用错误 `0xA001`、拒绝数加 1，未执行越界定位 |
| 错误复位 | ResetDone 成立、Error 清除，不自动重新运动 |
| 结束 | 返回 0 mm、撤销使能，Error=false |

原始判据是实际 PLC/NC 反馈；位置容差 0.02 mm，停止速度阈值 0.01 mm/s。
500 ms 的界面刷新等待只用于避免点击尚未刷新的禁用按钮，不作为运动完成判据。
完整 16 项见 [acceptance.json](acceptance.json)，14 项回归见
[core-regression.json](core-regression.json)。本轮回归也验证 −1 mm 拒绝。

![回归结束后的内置面板，轴在 0 mm 且已撤销使能](panel.png)

[运动过程画面](panel-during-sequence.png)、[停止画面](panel-stop.png)、
[越界画面](panel-limit.png) 是当时的实际界面采样。画面有刷新滞后，
截图与测试线程的完成时间不保证相同；判定以带时间戳的反馈记录为准。

## 版本与构建

10 个 ST 文件、原生工程中的声明/实现文本逐份匹配；公开 TcVIS 与实际打开的画面文件字节相同。
SHA-256 清单见 [source-manifest.json](source-manifest.json)、[build.json](build.json)。
GUI 与控制回归都绑定 PLC App `E1302E3F17EB2FD41E89D400D76BB8EE5DB389386D7F602AA40CEAB5F5422987`。

[原生构建日志](native-build.log) 保留了真实输出。生成窗格报告 0 errors / 0 warnings；
General 窗格另外输出空字体样式提示，日志中有 66 次重复提示。
这些字体提示尚未清理；当前画面实际文字显示与交互已验证。无关输出窗格的读取 E_FAIL 也如实保留。

从相同公开 ST/TcVIS 在新目录重新创建 Solution、PLC、NC 轴、导入面板并绑定 AXIS_REF，
CheckAllObjects 与原生构建成功。该新建副本没有激活配置，运行验收针对上面的专用已部署版本。
厂商 DLL、SDK、许可证及机器配置不公开。

## 采样与未验边界

[monitor.csv](monitor.csv) 是界面测试的 486 个真实 ADS Sum Read 观测点，
实际采样间隔中位数 **92.792 ms**、最大 **128.58 ms**；批量读取不宣称是同一 PLC 周期的原子快照。
[monitor-core.csv](monitor-core.csv) 是回归工具的 72 个顺序 ADS 观测点，采样更慢，以时间戳为准。
CSV 哈希分别保存在对应验收 JSON。

NOT_RUN：输入框越界/非数字/取消输入、同时多源命令、原生 NC 故障注入、
复位失败/超时、整机 Windows 重启、独立 PLC HMI/Web HMI。
无真实 EtherCAT、电流、温度、扭矩、整定、机械精度或安全急停验收。
MC_Direct 是虚拟坐标置零；MC_Stop 是运动控制停止，不是安全急停。

试用许可需在展示前本机复核，必要时经官方界面更新后再次复演。
