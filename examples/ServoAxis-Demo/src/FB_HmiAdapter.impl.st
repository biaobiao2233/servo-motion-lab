// 此层只适配现成画面的点击，运动逻辑与完成判断仍由 FB_ServoAxis 和 NC 执行。
// 空闲时不覆盖 GVL_Command，保留命令行/ADS 的原有调试入口。
GVL_Hmi.CanStart := (stage = 0) AND NOT GVL_Monitor.Busy AND NOT GVL_Monitor.StopHeld AND NOT GVL_Monitor.Error;
GVL_Hmi.CanMove := GVL_Hmi.CanStart AND GVL_Monitor.Enabled AND GVL_Monitor.Homed;
GVL_Hmi.CanStop := GVL_Monitor.Enabled;
GVL_Hmi.CanRelease := (stage = 0) AND GVL_Monitor.StopHeld AND (GVL_Monitor.StopDone OR (GVL_Monitor.Step = 90));
GVL_Hmi.CanReset := (stage = 0) AND GVL_Monitor.Error AND NOT GVL_Monitor.StopHeld AND NOT GVL_Monitor.Busy;

// 停止优先，取消尚未发出的自动启动；停止保持交给原状态机处理。
IF GVL_Hmi.StopRequest OR GVL_Hmi.DisableRequest THEN
    IF GVL_Hmi.StopRequest AND GVL_Monitor.Enabled THEN GVL_Command.Stop := TRUE; END_IF
    IF GVL_Hmi.DisableRequest THEN GVL_Command.Enable := FALSE; END_IF
    IF stage = 10 THEN stage := 0;
    ELSIF stage = 20 THEN stage := 21; pulseCycles := 0; END_IF
    GVL_Hmi.UiResult := 1;
    GVL_Hmi.EnableRequest := FALSE;
    GVL_Hmi.HomeRequest := FALSE;
    GVL_Hmi.AutoRequest := FALSE;
    GVL_Hmi.MoveRequest := FALSE;
    GVL_Hmi.Move0Request := FALSE;
    GVL_Hmi.Move30Request := FALSE;
    GVL_Hmi.Move80Request := FALSE;
    GVL_Hmi.RejectRequest := FALSE;
END_IF
GVL_Hmi.StopRequest := FALSE;
GVL_Hmi.DisableRequest := FALSE;

IF GVL_Hmi.EnableRequest THEN
    IF GVL_Hmi.CanStart THEN GVL_Command.Enable := TRUE; GVL_Hmi.UiResult := 1;
    ELSE GVL_Hmi.UiResult := 2; GVL_Hmi.UiRejected := GVL_Hmi.UiRejected + 1; END_IF
END_IF
IF GVL_Hmi.AutoRequest THEN
    IF GVL_Hmi.CanStart THEN
        GVL_Command.Velocity := GVL_Hmi.Velocity;
        GVL_Command.Enable := TRUE; stage := 10; GVL_Hmi.UiResult := 1;
    ELSE GVL_Hmi.UiResult := 2; GVL_Hmi.UiRejected := GVL_Hmi.UiRejected + 1; END_IF
END_IF
IF GVL_Hmi.HomeRequest THEN
    IF GVL_Hmi.CanStart AND GVL_Monitor.Enabled THEN pulseCommand := 1; stage := 20; pulseCycles := 0; GVL_Hmi.UiResult := 1;
    ELSE GVL_Hmi.UiResult := 2; GVL_Hmi.UiRejected := GVL_Hmi.UiRejected + 1; END_IF
END_IF
IF GVL_Hmi.MoveRequest OR GVL_Hmi.Move0Request OR GVL_Hmi.Move30Request OR GVL_Hmi.Move80Request OR GVL_Hmi.RejectRequest THEN
    IF GVL_Hmi.CanMove THEN
        IF GVL_Hmi.Move0Request THEN GVL_Hmi.TargetPosition := 0.0;
        ELSIF GVL_Hmi.Move30Request THEN GVL_Hmi.TargetPosition := 30.0;
        ELSIF GVL_Hmi.Move80Request THEN GVL_Hmi.TargetPosition := 80.0;
        ELSIF GVL_Hmi.RejectRequest THEN GVL_Hmi.TargetPosition := 101.0; END_IF
        // 101 mm 也送入原 PLC 的范围检查，以展示真实的越界拒绝。
        GVL_Command.TargetPosition := GVL_Hmi.TargetPosition;
        GVL_Command.Velocity := GVL_Hmi.Velocity;
        pulseCommand := 3; stage := 20; pulseCycles := 0; GVL_Hmi.UiResult := 1;
    ELSE GVL_Hmi.UiResult := 2; GVL_Hmi.UiRejected := GVL_Hmi.UiRejected + 1; END_IF
END_IF
IF GVL_Hmi.ReleaseRequest THEN
    IF GVL_Hmi.CanRelease THEN GVL_Command.Stop := FALSE; pulseCommand := 4; stage := 20; pulseCycles := 0; GVL_Hmi.UiResult := 1;
    ELSE GVL_Hmi.UiResult := 2; GVL_Hmi.UiRejected := GVL_Hmi.UiRejected + 1; END_IF
END_IF
IF GVL_Hmi.ResetRequest THEN
    IF GVL_Hmi.CanReset THEN pulseCommand := 5; stage := 20; pulseCycles := 0; GVL_Hmi.UiResult := 1;
    ELSE GVL_Hmi.UiResult := 2; GVL_Hmi.UiRejected := GVL_Hmi.UiRejected + 1; END_IF
END_IF
GVL_Hmi.EnableRequest := FALSE; GVL_Hmi.HomeRequest := FALSE; GVL_Hmi.AutoRequest := FALSE;
GVL_Hmi.MoveRequest := FALSE; GVL_Hmi.Move0Request := FALSE; GVL_Hmi.Move30Request := FALSE; GVL_Hmi.Move80Request := FALSE;
GVL_Hmi.ReleaseRequest := FALSE; GVL_Hmi.ResetRequest := FALSE; GVL_Hmi.RejectRequest := FALSE;

enableTimeout(IN := stage = 10, PT := T#5S);
IF stage = 10 THEN
    // 使能必须先获得 MC_Power 的真实反馈，避免同周期脉冲被未就绪状态忽略。
    IF GVL_Monitor.Enabled AND ((GVL_Monitor.Step = 10) OR (GVL_Monitor.Step = 20)) THEN
        pulseCommand := 2; stage := 20; pulseCycles := 0;
    ELSIF enableTimeout.Q OR GVL_Monitor.Error THEN stage := 0; GVL_Hmi.UiResult := 3; END_IF
END_IF
IF (stage = 20) OR (stage = 21) THEN
    // Execute 命令高、低各跨两个实际 PLC 周期；此计数不用于判断运动完成。
    CASE pulseCommand OF
        1: GVL_Command.Home := stage = 20;
        2: GVL_Command.AutoStart := stage = 20;
        3: GVL_Command.MoveRequest := stage = 20;
        4: GVL_Command.ReleaseStop := stage = 20;
        5: GVL_Command.Reset := stage = 20;
    END_CASE
    pulseCycles := pulseCycles + 1;
    IF pulseCycles >= 2 THEN
        pulseCycles := 0;
        IF stage = 20 THEN stage := 21; ELSE stage := 0; END_IF
    END_IF
END_IF
GVL_Hmi.UiBusy := stage <> 0;
