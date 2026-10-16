FUNCTION_BLOCK FB_ServoAxis
VAR_IN_OUT
    Axis : AXIS_REF;
END_VAR
VAR_INPUT
    Enable : BOOL;
    Home : BOOL;
    MoveRequest : BOOL;
    AutoStart : BOOL;
    Stop : BOOL;
    ReleaseStop : BOOL;
    Reset : BOOL;
    RequestedPosition : LREAL;
    RequestedVelocity : LREAL;
END_VAR
VAR_OUTPUT
    Step : UINT;
    AutoIndex : UINT;
    TargetPosition : LREAL;
    Enabled : BOOL;
    Homed : BOOL;
    AutoActive : BOOL;
    Busy : BOOL;
    Done : BOOL;
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
    ApplicationErrorID : UDINT;
    NativeErrorID : UDINT;
    CompletedMoves : UDINT;
    RejectedCommands : UDINT;
    CompletedAutoCycles : UDINT;
END_VAR
VAR
    fbPower : MC_Power;
    fbHome : MC_Home;
    fbMove : MC_MoveAbsolute;
    fbStop : MC_Stop;
    fbReset : MC_Reset;
    edgeHome : R_TRIG;
    edgeMove : R_TRIG;
    edgeAuto : R_TRIG;
    edgeStop : R_TRIG;
    edgeRelease : R_TRIG;
    edgeReset : R_TRIG;
    watchdog : TON;
    resetWatchdog : TON;
    homeExecute : BOOL;
    moveExecute : BOOL;
    stopExecute : BOOL;
    resetExecute : BOOL;
    velocity : LREAL := 60.0;
    requestStop : BOOL;
    currentNativeError : UDINT;
END_VAR
