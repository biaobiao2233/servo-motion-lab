hmi(); // 原生 Visualization 点击适配；不替代轴的 NC 反馈和运动状态机。
servo(Axis := GVL_Motion.Axis,
      Enable := GVL_Command.Enable, Home := GVL_Command.Home,
      MoveRequest := GVL_Command.MoveRequest, AutoStart := GVL_Command.AutoStart,
      Stop := GVL_Command.Stop, ReleaseStop := GVL_Command.ReleaseStop,
      Reset := GVL_Command.Reset,
      RequestedPosition := GVL_Command.TargetPosition,
      RequestedVelocity := GVL_Command.Velocity);

GVL_Monitor.ActualPosition := GVL_Motion.Axis.NcToPlc.ActPos;
GVL_Monitor.ActualVelocity := GVL_Motion.Axis.NcToPlc.ActVelo;
GVL_Monitor.TargetPosition := servo.TargetPosition;
GVL_Monitor.Step := servo.Step;
GVL_Monitor.AutoIndex := servo.AutoIndex;
GVL_Monitor.Enabled := servo.Enabled;
GVL_Monitor.Homed := servo.Homed;
GVL_Monitor.AutoActive := servo.AutoActive;
GVL_Monitor.Busy := servo.Busy;
GVL_Monitor.Done := servo.Done;
GVL_Monitor.MoveBusy := servo.MoveBusy;
GVL_Monitor.MoveDone := servo.MoveDone;
GVL_Monitor.HomeBusy := servo.HomeBusy;
GVL_Monitor.HomeDone := servo.HomeDone;
GVL_Monitor.StopBusy := servo.StopBusy;
GVL_Monitor.StopDone := servo.StopDone;
GVL_Monitor.StopHeld := servo.StopHeld;
GVL_Monitor.ResetBusy := servo.ResetBusy;
GVL_Monitor.ResetDone := servo.ResetDone;
GVL_Monitor.CommandAborted := servo.CommandAborted;
GVL_Monitor.Error := servo.Error;
GVL_Monitor.ErrorID := servo.ErrorID;
GVL_Monitor.ApplicationErrorID := servo.ApplicationErrorID;
GVL_Monitor.NativeErrorID := servo.NativeErrorID;
GVL_Monitor.CompletedMoves := servo.CompletedMoves;
GVL_Monitor.RejectedCommands := servo.RejectedCommands;
GVL_Monitor.CompletedAutoCycles := servo.CompletedAutoCycles;
GVL_Monitor.CycleCounter := GVL_Monitor.CycleCounter + 1;
