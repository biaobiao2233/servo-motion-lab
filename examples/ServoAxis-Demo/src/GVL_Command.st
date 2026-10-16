{attribute 'qualified_only'}
VAR_GLOBAL
    Enable : BOOL;                  // 使能保持信号；上电默认不使能
    Home : BOOL;                    // 上升沿：仿真直接回零
    MoveRequest : BOOL;             // 上升沿：手动绝对定位，避开内置 MOVE 指令名称
    AutoStart : BOOL;               // 上升沿：回零后 30→80→0 mm
    Stop : BOOL;                    // 上升沿停止；保持 TRUE 禁止释放
    ReleaseStop : BOOL;             // 上升沿解除应用停止保持
    Reset : BOOL;                   // 上升沿错误复位；不会自动恢复运动
    TargetPosition : LREAL := 30.0;
    Velocity : LREAL := 60.0;        // 仿真展示默认 60 mm/s，允许 0 < v <= 100
END_VAR
