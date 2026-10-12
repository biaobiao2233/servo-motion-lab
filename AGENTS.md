# Servo Motion Lab — Agent 工作约定

- 默认中文。目标是可复现、可解释的伺服运动控制作品集；当前优先真实 NC 单轴仿真。
- 持续项目使用 canonical `~/.agents/skills/project-workbench`。GitHub Issue/PR 是任务记录；
  不把旧聊天、worker 完成声明或文档中的计划当成当前代码/运行证据。
- 当前有效需求在 `docs/REQUIREMENTS.md`，验证标准在 `docs/VALIDATION.md`。
- 初始空仓库建立 main 基线后，实质开发使用短分支；并行写入使用不同 worktree。
- 工程、脚本、临时构建和专用 Runtime 的文件均位于本仓库或该任务明确分配的新目录。
  不修改 TIA-Guard、已有学习示例、其他项目或现有 Runtime 的配置。
- Runtime 与工作树分别分配资源。专用用户态 Runtime 必须使用独立配置目录及唯一 AmsNetId；
  不接管已有 IDE/Runtime，不扫描或控制远程 PLC/真实设备。
- 需要安装组件、变更系统/许可或影响已有服务时，先记录具体动作、依赖与影响；
  当前授权不明确的动作不得凭工具权限或旧会话执行。
- 遵循 PLCopen 官方 Execute/Busy/Done/CommandAborted/Error 语义；所有功能块周期调用，
  不使用定时延迟伪造完成，不使用手写位置积分假装真实 NC 反馈。
- PASS 必须绑定准确源版本、软件/许可环境和实际运行证据。未运行标 NOT_RUN，
  缺环境标 BLOCKED，证据不完整标 UNKNOWN，不生成假的曲线或测试结果。
- 公开提交不得含用户凭据、许可文件、完整系统配置、私有端点、聊天历史或厂商 DLL。
  本机 SDK/interop、临时缓存、Runtime Boot 文件和原始敏感日志均不提交。
- 图形化界面、双轴及复杂算法是后续事项，不阻塞单轴最低验收。
- 达成当前目标或真实阻塞后记录证据、下一步与资源清理，不扩大范围。
