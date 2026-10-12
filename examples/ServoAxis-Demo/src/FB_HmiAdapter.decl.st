FUNCTION_BLOCK FB_HmiAdapter
VAR
    stage : UINT;
    pulseCommand : UINT;           // 1=Home，2=AutoStart，3=MoveRequest，4=ReleaseStop，5=Reset
    pulseCycles : UINT;
    enableTimeout : TON;
END_VAR
