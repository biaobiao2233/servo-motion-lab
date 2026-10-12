# 当前有效需求

用户要求建立公开、长期维护的伺服运动控制作品集。当前唯一实施目标为
**ServoAxis-Demo**；2026-10-22 线下双选会是第一阶段展示里程碑。

## ServoAxis-Demo

1. 检查 Windows 11 上 TwinCAT XAE/XAR、NC/PTP、试用许可和 Runtime。
2. 建立独立 Solution、PLC Project、一根真实 NC/PTP 虚拟轴并完成 AXIS_REF 映射。
3. 使用 Tc2_MC2：MC_Power、MC_Home、MC_MoveAbsolute、MC_Stop、MC_Reset，
   遵循官方沿触发与反馈语义。
4. 手动/自动状态机：轴使能、虚拟回零、0→30→80→0 mm 顺序定位。
   新目标必须在 0～100 mm，支持运动中停止、错误反馈和复位。
5. 步骤以真实 Busy/Done/Error 等反馈推进；定时器仅可用于超时保护，不能作为完成依据。
6. 监控：目标/实际位置、速度、当前步骤、使能、Busy、Done、Error、ErrorID。
   条件允许保留实际采样的位置/速度 CSV 与曲线。
7. 至少三次实际定位、运动中停止及越界拒绝，输出真实构建日志和测试记录。
8. 中文 README、中文代码注释、仿真操作说明和面试常问问题。

## 保护边界

- 不修改已有 TwinCAT 学习工程、TIA-Guard、其他仓库或现有 Runtime 配置。
- 没有真实硬件，不声称完成真实 EtherCAT 通信、电机整定或安全急停验收。
- 环境阻塞先记录；无真实运行证据不得 PASS。
- HMI 美化、双轴联动和复杂算法不在当前最低验收范围。
