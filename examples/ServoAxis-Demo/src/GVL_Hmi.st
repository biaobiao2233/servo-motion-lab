{attribute 'qualified_only'}
VAR_GLOBAL
    // 内置画面的点击请求；适配器消费后清零，画面不直接维持 MC 的 Execute。
    EnableRequest, DisableRequest, HomeRequest, AutoRequest : BOOL;
    MoveRequest, Move0Request, Move30Request, Move80Request : BOOL;
    StopRequest, ReleaseRequest, ResetRequest, RejectRequest : BOOL;
    TargetPosition : LREAL := 30.0;
    Velocity : LREAL := 60.0;       // 仿真展示默认速度，最初 20 mm/s 的 3 倍
    CanStart, CanMove, CanStop, CanRelease, CanReset : BOOL;
    UiBusy : BOOL;
    UiResult : UINT;                // 0=无拒绝，1=命令已交给PLC，2=界面请求被状态拒绝，3=使能等待超时
    UiRejected : UDINT;
END_VAR
