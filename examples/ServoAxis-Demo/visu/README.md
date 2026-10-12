# 原生单轴操作面板

`ServoDashboard.TcVIS` 是 TwinCAT 3.1.4026.27 可加载的原生 Visualization 源文件。
新建工程时由 `Create-DemoProject.ps1` 自动导入；已有工程可从 PLC 项目导入该文件，
同时加入本例全部 ST 源码。它依赖 `GVL_Hmi` 与 `GVL_Monitor`，不包含轴或 Runtime 配置。

在线显示实际 NC 位置/速度、已接受目标、步骤、使能、回零、Busy、Done、停止保持、
错误码与完成/拒绝计数。按钮通过一次请求交给 `FB_HmiAdapter`，运动完成不按界面延时判断。
手动输入采用官方 Text input；点击数值、键盘输入、按 Enter 确认。

复用 MTCS 的点击及输入动作配置后适配 4026 控件、中文布局和本例变量。
该衍生 TcVIS 按 LGPL v3 提供，具体来源、修改及许可见
[third_party/MTCS](../../../third_party/MTCS/README.md)。

完整操作步骤与仿真边界见 [示例说明](../README.md)。
