{attribute 'qualified_only'}
VAR_GLOBAL
    ActualPosition : LREAL;         // 来自 NC，不自行积分
    ActualVelocity : LREAL;
    TargetPosition : LREAL;
    Step : UINT;
    AutoIndex : UINT;
    Enabled : BOOL;
    Homed : BOOL;
    AutoActive : BOOL;
    Busy : BOOL;
    Done : BOOL;                    // 本次请求完成保持，来自真实 Done
    MoveBusy : BOOL;
    MoveDone : BOOL;
    HomeBusy : BOOL;
    HomeDone : BOOL;
    StopBusy : BOOL;
    StopDone : BOOL;
    StopHeld : BOOL;
    ResetBusy : BOOL;
    ResetDone : BOOL;
    CommandAborted : BOOL;
    Error : BOOL;
    ErrorID : UDINT;
    ApplicationErrorID : UDINT;     // 应用拒绝错误，与 NC ErrorID 区分
    NativeErrorID : UDINT;
    CompletedMoves : UDINT;
    RejectedCommands : UDINT;
    CompletedAutoCycles : UDINT;
    CycleCounter : UDINT;
END_VAR
