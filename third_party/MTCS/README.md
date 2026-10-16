# MTCS 原生面板的复用范围

上游：[IvS-KULeuven/MTCS-public](https://github.com/IvS-KULeuven/MTCS-public)，
固定版本 `779fbfa58e17fd11c9e3eabe9c91619b0ca58bd3`，GNU LGPL v3。
原许可保存在 LICENSE，配套 GNU GPL v3 文本保存在 COPYING。

参考并适配了以下原生画面的按钮点击与数值输入配置：

- `MTCS/MTCS/MTCS/MTCS/Common/Visu/VISU_BaseAxis_Stop.TcVIS`
- `MTCS/MTCS/MTCS/MTCS/Common/Visu/VISU_BaseAxis_Status.TcVIS`
- `MTCS/MTCS/MTCS/MTCS/Common/Visu/VISU_BaseAxis_MoveAbsolute.TcVIS`

衍生文件是 `examples/ServoAxis-Demo/visu/ServoDashboard.TcVIS`，按 LGPL v3 提供源文件。
2026-10-13 的修改包括：替换为本机 4026 的控件格式、中文文字与布局、绑定
GVL_Hmi/GVL_Monitor、停止保持/复位门控、0/30/80 mm 定位和 101 mm 拒绝演示。
旧版样式与数值属性没有整块复制到新版本；保留交互配置并使用当前版本的原生控件。

本项目没有导入上游的望远镜控制框架、硬件配置、许可证、SLALIB 或厂商二进制。
运动控制仍由本仓库的 FB_ServoAxis、Tc2_MC2 和专用 NC 仿真轴执行；FB_HmiAdapter
只是把点击请求转换为 PLC 命令，并不产生位置或伪造运动完成。
