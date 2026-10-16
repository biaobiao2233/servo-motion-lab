param([string]$TwinCatRoot=$env:TWINCAT3DIR,[ValidateRange(20,1000)][int]$SampleIntervalMs=50)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'DemoAds.psm1') -Force
$repoRoot=Split-Path -Parent $PSScriptRoot
$evidenceRoot=Join-Path $repoRoot ('.local\evidence\run-'+(Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $evidenceRoot -Force|Out-Null
$client=New-DemoAdsClient -TwinCatRoot $TwinCatRoot -Port 851
$handles=@{};$types=[ordered]@{}
foreach($name in @('ActualPosition','ActualVelocity','TargetPosition')){$types[$name]=[double]}
foreach($name in @('Step','AutoIndex')){$types[$name]=[uint16]}
foreach($name in @('Enabled','Homed','AutoActive','Busy','Done','MoveBusy','MoveDone','HomeBusy','HomeDone','StopBusy','StopDone','StopHeld','ResetBusy','ResetDone','CommandAborted','Error')){$types[$name]=[bool]}
foreach($name in @('ErrorID','ApplicationErrorID','NativeErrorID','CompletedMoves','RejectedCommands','CompletedAutoCycles','CycleCounter')){$types[$name]=[uint32]}
$rows=[Collections.Generic.List[object]]::new()
$tests=[Collections.Generic.List[object]]::new()
$script:phase='INITIAL'
$report=[ordered]@{Status='NOT_RUN';StartedAt=(Get-Date).ToString('o');PositionToleranceMm=0.02;StoppedVelocityThresholdMmPerSec=0.01;RequestedSampleIntervalMs=$SampleIntervalMs;Tests=$tests;Hardware='NC simulation only';EvidenceDirectory=$evidenceRoot}
function Sample {
    $row=[ordered]@{ObservedAt=(Get-Date).ToString('o');Phase=$script:phase}
    foreach($name in $types.Keys){$row[$name]=$client.ReadAny($handles[$name],$types[$name])}
    $value=[pscustomobject]$row
    $rows.Add($value)
    return $value
}
function Wait-Monitor([scriptblock]$Condition,[int]$TimeoutSeconds=25,[switch]$AllowError){
    $watch=[Diagnostics.Stopwatch]::StartNew()
    do{
        $value=Sample
        if($value.Error -and -not $AllowError){throw ('PLC error: '+$value.ErrorID+' / native '+$value.NativeErrorID+' in '+$script:phase)}
        if(& $Condition $value){return $value}
        Start-Sleep -Milliseconds $SampleIntervalMs
    }while($watch.Elapsed.TotalSeconds -lt $TimeoutSeconds)
    throw ('Feedback timeout in '+$script:phase+'; last step='+$value.Step)
}
function Write-Command([string]$Name,$Value){Write-DemoSymbol $client ('GVL_Command.'+$Name) $Value}
function Pulse([string]$Name,[switch]$AllowError){
    $before=Sample
    Write-Command $Name ([bool]$true)
    try{[void](Wait-Monitor {param($r) $r.CycleCounter -gt $before.CycleCounter+2} -TimeoutSeconds 3 -AllowError:$AllowError)}
    finally{Write-Command $Name ([bool]$false)}
}
function Record([string]$Name,$Actual){
    $tests.Add([pscustomobject]@{Name=$Name;Status='PASS';ObservedAt=(Get-Date).ToString('o');Actual=$Actual})
    Write-Output ('PASS '+$Name)
}
try{
    if($client.ReadState().AdsState.ToString() -ne 'Run'){throw 'PLC is not Run.'}
    foreach($name in $types.Keys){$handles[$name]=$client.CreateVariableHandle('GVL_Monitor.'+$name)}
    $initial=Sample
    if($initial.Busy -or $initial.StopHeld -or $initial.Error){throw 'Demo must start idle with no error or stop lock.'}
    $report.SourceFiles=@(Get-ChildItem -LiteralPath (Join-Path $repoRoot 'examples\ServoAxis-Demo\src') -File|ForEach-Object{[pscustomobject]@{Name=$_.Name;Sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash}})
    $runtimeStatus=Get-Content -LiteralPath (Join-Path $repoRoot '.local\runtime-status.json') -Raw|ConvertFrom-Json
    $boot=Join-Path $runtimeStatus.ConfigurationRoot 'Boot'
    $report.RuntimePid=$runtimeStatus.RuntimePid
    $report.AmsNetId=$runtimeStatus.AmsNetId
    $report.PlcAppSha256=(Get-FileHash -LiteralPath (Join-Path $boot 'Plc\Port_851.app') -Algorithm SHA256).Hash
    $report.ConfigSha256=(Get-FileHash -LiteralPath (Join-Path $boot 'CurrentConfig.xml') -Algorithm SHA256).Hash
    foreach($command in @('Home','MoveRequest','AutoStart','Stop','ReleaseStop','Reset')){Write-Command $command ([bool]$false)}
    $script:phase='ENABLE'
    Write-Command 'Enable' ([bool]$true)
    $enabled=Wait-Monitor {param($r) $r.Enabled -and $r.Step -in @(10,20)}
    Record 'ENABLE' $enabled
    $script:phase='DIRECT_HOME'
    Pulse 'Home'
    $homed=Wait-Monitor {param($r) $r.Homed -and $r.HomeDone -and $r.Step -eq 20}
    if([Math]::Abs($homed.ActualPosition) -gt 0.02){throw 'Direct home position mismatch.'}
    Record 'DIRECT_HOME' $homed
    foreach($target in @(30.0,80.0,0.0)){
        $script:phase='MANUAL_'+$target
        $before=Sample
        Write-Command 'TargetPosition' ([double]$target)
        Write-Command 'Velocity' ([double]20.0)
        Pulse 'MoveRequest'
        $done=Wait-Monitor {param($r) $r.CompletedMoves -eq $before.CompletedMoves+1 -and $r.MoveDone -and $r.Step -eq 20 -and -not $r.Busy}
        if([Math]::Abs($done.ActualPosition-$target) -gt 0.02){throw 'Position mismatch.'}
        $moving=@($rows|Where-Object{$_.Phase -eq $script:phase -and $_.MoveBusy -and [Math]::Abs($_.ActualVelocity) -gt 0.01})
        if($moving.Count -eq 0){throw 'No observed Busy and actual velocity during positioning.'}
        Record $script:phase $done
    }
    $script:phase='AUTO_30_80_0'
    $before=Sample
    Pulse 'AutoStart'
    $autoDone=Wait-Monitor {param($r) $r.CompletedAutoCycles -eq $before.CompletedAutoCycles+1 -and $r.CompletedMoves -eq $before.CompletedMoves+3 -and $r.Done -and $r.Step -eq 20 -and -not $r.AutoActive}
    if([Math]::Abs($autoDone.ActualPosition) -gt 0.02){throw 'Auto final position mismatch.'}
    foreach($target in @(30.0,80.0,0.0)){
        if(@($rows|Where-Object{$_.Phase -eq $script:phase -and $_.TargetPosition -eq $target -and $_.MoveBusy}).Count -eq 0){throw 'Missing observed auto leg.'}
    }
    Record $script:phase $autoDone
    $script:phase='STOP_DURING_MOTION'
    Write-Command 'TargetPosition' ([double]80.0)
    Write-Command 'Velocity' ([double]20.0)
    Pulse 'MoveRequest'
    $moving=Wait-Monitor {param($r) $r.MoveBusy -and [Math]::Abs($r.ActualVelocity) -gt 1.0 -and $r.ActualPosition -gt 2.0}
    Write-Command 'Stop' ([bool]$true)
    $stopped=Wait-Monitor {param($r) $r.StopDone -and $r.StopHeld -and $r.Step -eq 61 -and [Math]::Abs($r.ActualVelocity) -le 0.01}
    if($stopped.ActualPosition -ge 79.98){throw 'Stop test reached commanded end before stopping.'}
    $heldPosition=$stopped.ActualPosition
    $heldCycle=$stopped.CycleCounter
    Write-Command 'TargetPosition' ([double]30.0)
    Pulse 'MoveRequest'
    $held=Wait-Monitor {param($r) $r.CycleCounter -gt $heldCycle+40}
    if(-not $held.StopHeld -or [Math]::Abs($held.ActualPosition-$heldPosition) -gt 0.02){throw 'Stop lock did not hold.'}
    Record 'STOP_HOLD' ([pscustomobject]@{CommandedAt=$moving;Stopped=$stopped;Held=$held})
    $script:phase='RELEASE_STOP'
    Write-Command 'Stop' ([bool]$false)
    Pulse 'ReleaseStop'
    $released=Wait-Monitor {param($r) -not $r.StopHeld -and -not $r.StopBusy -and $r.Step -eq 20}
    Record $script:phase $released
    foreach($target in @(-1.0,101.0)){
        $script:phase='REJECT_'+$target
        $before=Sample
        Write-Command 'TargetPosition' ([double]$target)
        Pulse 'MoveRequest' -AllowError
        $rejected=Wait-Monitor {param($r) $r.Error -and $r.ApplicationErrorID -eq 40961 -and $r.RejectedCommands -eq $before.RejectedCommands+1} -AllowError
        if($rejected.CompletedMoves -ne $before.CompletedMoves -or $rejected.MoveBusy -or [Math]::Abs($rejected.ActualPosition-$before.ActualPosition) -gt 0.02){throw 'Out-of-range request caused movement.'}
        Record $script:phase $rejected
        $script:phase='RESET_AFTER_REJECTION'
        Pulse 'Reset' -AllowError
        $reset=Wait-Monitor {param($r) -not $r.Error -and $r.ResetDone -and $r.Step -in @(10,20)} -AllowError
        Record ($script:phase+'_'+$target) $reset
    }
    $script:phase='RETURN_ZERO'
    $before=Sample
    Write-Command 'TargetPosition' ([double]0.0)
    Pulse 'MoveRequest'
    $zero=Wait-Monitor {param($r) $r.CompletedMoves -eq $before.CompletedMoves+1 -and $r.Step -eq 20 -and [Math]::Abs($r.ActualPosition) -le 0.02}
    Record $script:phase $zero
    $script:phase='DISABLE'
    Write-Command 'Enable' ([bool]$false)
    $disabled=Wait-Monitor {param($r) -not $r.Enabled -and $r.Step -eq 0}
    Record $script:phase $disabled
    $report.Status='PASS'
}catch{
    $report.Status='FAIL';$report.FailedPhase=$script:phase;$report.Error=$_.Exception.ToString()
    try{Write-Command 'Stop' ([bool]$true)}catch{}
    Write-Warning $report.Error
}finally{
    $report.CompletedAt=(Get-Date).ToString('o')
    $report.SampleCount=$rows.Count
    $csvPath=Join-Path $evidenceRoot 'monitor.csv'
    $rows|Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8
    $report.MonitorCsvSha256=(Get-FileHash -LiteralPath $csvPath -Algorithm SHA256).Hash
    $report|ConvertTo-Json -Depth 12|Set-Content -LiteralPath (Join-Path $evidenceRoot 'acceptance.json') -Encoding UTF8
    foreach($handle in $handles.Values){try{$client.DeleteVariableHandle($handle)}catch{}}
    $client.Dispose()
}
[pscustomobject]@{Status=$report.Status;EvidenceDirectory=$evidenceRoot;TestCount=$tests.Count;SampleCount=$rows.Count;FailedPhase=$report.FailedPhase}|ConvertTo-Json
if($report.Status -ne 'PASS'){exit 1}
