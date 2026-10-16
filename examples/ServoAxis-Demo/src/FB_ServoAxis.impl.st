// 每周期刷新真实 NC 状态；所有 MC 功能块在下方无条件周期调用。
Axis.ReadStatus();
edgeHome(CLK := Home);
edgeMove(CLK := MoveRequest);
edgeAuto(CLK := AutoStart);
edgeStop(CLK := Stop);
edgeRelease(CLK := ReleaseStop);
edgeReset(CLK := Reset);
watchdog(IN := (Step = 30) OR (Step = 50), PT := T#30S);
resetWatchdog(IN := Step = 70, PT := T#10S);
requestStop := Stop OR edgeStop.Q OR watchdog.Q;

// 运动中撤销使能先请求受控停止，停止完成后才允许 MC_Power 关闭。
IF NOT Enable AND Enabled AND ((Step = 30) OR (Step = 40) OR (Step = 50) OR AutoActive) THEN
    requestStop := TRUE;
END_IF
IF watchdog.Q THEN
    ApplicationErrorID := 16#A005; // 回零/定位超时，不能当作完成
END_IF

// 停止优先于同周期的运动请求，并取消自动序列；应用锁需要显式释放。
IF requestStop AND Enabled AND (Step <> 60) AND (Step <> 61) AND (Step <> 62) THEN
    AutoActive := FALSE;
    homeExecute := FALSE;
    moveExecute := FALSE;
    stopExecute := TRUE;
    StopHeld := TRUE;
    Done := FALSE;
    Step := 60;
END_IF

// 复位不自动启动，且应用停止保持必须先显式释放。
IF edgeReset.Q AND NOT StopHeld AND NOT fbStop.Busy AND NOT fbMove.Busy AND NOT fbHome.Busy THEN
    resetExecute := TRUE;
    ResetDone := FALSE;
    Done := FALSE;
    AutoActive := FALSE;
    Step := 70;
END_IF

CASE Step OF
    0: // 未使能
        IF Enable THEN Step := 5; END_IF
    5: // 等待真实 MC_Power.Status
        IF NOT Enable THEN Step := 0;
        ELSIF fbPower.Status THEN Step := 10; END_IF
    10, 20: // 10=尚未回零，20=准备就绪
        IF NOT Enable THEN
            Step := 0;
        ELSIF NOT requestStop AND NOT StopHeld AND (ApplicationErrorID = 0) AND (NativeErrorID = 0) THEN
            IF edgeAuto.Q AND NOT ((RequestedVelocity > 0.0) AND (RequestedVelocity <= 100.0)) THEN
                ApplicationErrorID := 16#A004; // 自动/手动使用同一速度范围检查
                RejectedCommands := RejectedCommands + 1;
            ELSIF edgeHome.Q OR edgeAuto.Q THEN
                AutoActive := edgeAuto.Q;
                IF edgeAuto.Q THEN velocity := RequestedVelocity; END_IF // 一次序列锁存操作者速度
                AutoIndex := 1;
                homeExecute := TRUE;
                Done := FALSE;
                HomeDone := FALSE;
                CommandAborted := FALSE;
                Step := 30;
            ELSIF edgeMove.Q THEN
                Done := FALSE;
                IF NOT ((RequestedPosition >= 0.0) AND (RequestedPosition <= 100.0)) THEN
                    ApplicationErrorID := 16#A001; // 软件位置范围拒绝；不发送 MC_MoveAbsolute
                    RejectedCommands := RejectedCommands + 1;
                ELSIF NOT ((RequestedVelocity > 0.0) AND (RequestedVelocity <= 100.0)) THEN
                    ApplicationErrorID := 16#A004;
                    RejectedCommands := RejectedCommands + 1;
                ELSIF NOT Homed THEN
                    ApplicationErrorID := 16#A003;
                    RejectedCommands := RejectedCommands + 1;
                ELSE
                    TargetPosition := RequestedPosition;
                    velocity := RequestedVelocity;
                    moveExecute := TRUE;
                    MoveDone := FALSE;
                    CommandAborted := FALSE;
                    AutoActive := FALSE;
                    Step := 50;
                END_IF
            END_IF
        END_IF
    31:
        homeExecute := FALSE; // 释放 Execute，等功能块恢复后再发下一命令
    40: // 自动定位命令，只在上一 MC_MoveAbsolute 完全释放后进入
        CASE AutoIndex OF
            1: TargetPosition := 30.0;
            2: TargetPosition := 80.0;
            3: TargetPosition := 0.0;
        END_CASE
        // 使用启动时锁存的自定义速度；各段仍等待实际 MoveDone。
        moveExecute := TRUE;
        MoveDone := FALSE;
        Step := 50;
    51:
        moveExecute := FALSE;
    61:
        IF edgeRelease.Q AND NOT Stop THEN
            stopExecute := FALSE;
            Step := 62;
        END_IF
    62:
        stopExecute := FALSE;
    71:
        resetExecute := FALSE;
    90:
        // 停止过程自身报错时，也保留显式释放路径，避免应用锁无法复位。
        IF edgeRelease.Q AND NOT Stop THEN stopExecute := FALSE; END_IF
        IF NOT stopExecute AND NOT fbStop.Busy THEN StopHeld := FALSE; END_IF
END_CASE

// MC_Direct 是官方仿真直接回零：无物理原点开关，不宣传为真实机械回零。
fbPower(Axis := Axis, Enable := Enable OR ((Step >= 60) AND (Step <= 62)),
        Enable_Positive := TRUE, Enable_Negative := TRUE, Override := 100.0);
fbHome(Axis := Axis, Execute := homeExecute, Position := 0.0, HomingMode := MC_Direct);
fbMove(Axis := Axis, Execute := moveExecute, Position := TargetPosition,
       Velocity := velocity, Acceleration := 240.0, Deceleration := 240.0, Jerk := 1200.0);
fbStop(Axis := Axis, Execute := stopExecute, Deceleration := 300.0, Jerk := 1500.0);
fbReset(Axis := Axis, Execute := resetExecute);

// 读取本周期真实反馈。MC_Stop 的 Done 与 Busy 可以同时为 TRUE。
Enabled := fbPower.Status;
MoveBusy := fbMove.Busy;
HomeBusy := fbHome.Busy;
StopBusy := fbStop.Busy;
ResetBusy := fbReset.Busy;
IF fbMove.CommandAborted OR fbHome.CommandAborted THEN CommandAborted := TRUE; END_IF

CASE Step OF
    30:
        IF fbHome.Done THEN
            Homed := TRUE;
            HomeDone := TRUE;
            homeExecute := FALSE;
            Step := 31;
        END_IF
    31:
        IF NOT fbHome.Busy AND NOT fbHome.Done THEN
            IF AutoActive THEN Step := 40; ELSE Step := 20; Done := TRUE; END_IF
        END_IF
    50:
        IF fbMove.Done THEN
            MoveDone := TRUE;
            CompletedMoves := CompletedMoves + 1;
            moveExecute := FALSE;
            Step := 51;
        ELSIF fbMove.CommandAborted THEN
            AutoActive := FALSE;
            moveExecute := FALSE;
            Step := 51;
        END_IF
    51:
        IF NOT fbMove.Busy AND NOT fbMove.Done AND NOT fbMove.CommandAborted THEN
            IF AutoActive AND (AutoIndex < 3) THEN
                AutoIndex := AutoIndex + 1;
                Step := 40;
            ELSE
                IF AutoActive THEN CompletedAutoCycles := CompletedAutoCycles + 1; END_IF
                AutoActive := FALSE;
                Done := MoveDone AND NOT CommandAborted;
                Step := 20;
            END_IF
        END_IF
    60:
        IF fbStop.Done THEN StopDone := TRUE; Step := 61; END_IF
    62:
        IF NOT fbStop.Busy THEN
            StopHeld := FALSE;
            StopDone := FALSE;
            IF Enable THEN
                IF Homed THEN Step := 20; ELSE Step := 10; END_IF
            ELSE Step := 0; END_IF
        END_IF
    70:
        IF fbReset.Done THEN
            ResetDone := TRUE;
            ApplicationErrorID := 0;
            NativeErrorID := 0;
            CommandAborted := FALSE;
            resetExecute := FALSE;
            Step := 71;
        ELSIF resetWatchdog.Q THEN
            ApplicationErrorID := 16#A006; // 复位超时也必须退出等待，不能假定成功
            resetExecute := FALSE;
            Step := 90;
        END_IF
    71:
        IF NOT fbReset.Busy AND NOT fbReset.Done THEN
            IF Enable THEN Step := 5; ELSE Step := 0; END_IF
        END_IF
END_CASE

currentNativeError := 0;
IF fbPower.Error THEN currentNativeError := fbPower.ErrorID;
ELSIF fbHome.Error THEN currentNativeError := fbHome.ErrorID;
ELSIF fbMove.Error THEN currentNativeError := fbMove.ErrorID;
ELSIF fbStop.Error THEN currentNativeError := fbStop.ErrorID;
ELSIF fbReset.Error THEN currentNativeError := fbReset.ErrorID;
ELSIF Axis.Status.ErrorStop THEN currentNativeError := Axis.NcToPlc.ErrorCode;
END_IF
// 复位期间暂缓旧轴错误，但 MC_Reset 自身失败必须立即反馈并退出。
IF (currentNativeError <> 0) AND (((Step <> 70) AND (Step <> 71)) OR fbReset.Error) THEN
    NativeErrorID := currentNativeError;
    AutoActive := FALSE;
    homeExecute := FALSE;
    moveExecute := FALSE;
    resetExecute := FALSE;
    Done := FALSE;
    Step := 90;
END_IF
Error := (ApplicationErrorID <> 0) OR (NativeErrorID <> 0);
IF NativeErrorID <> 0 THEN ErrorID := NativeErrorID; ELSE ErrorID := ApplicationErrorID; END_IF
Busy := fbHome.Busy OR fbMove.Busy OR fbStop.Busy OR fbReset.Busy OR AutoActive;
