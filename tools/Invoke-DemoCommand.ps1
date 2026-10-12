param(
    [Parameter(Mandatory=$true)][ValidateSet('Status','Enable','Disable','Home','Move','Auto','Stop','ReleaseStop','Reset')][string]$Command,
    [double]$Position=30.0,[double]$Velocity=20.0,[string]$TwinCatRoot=$env:TWINCAT3DIR
)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'DemoAds.psm1') -Force
$client=New-DemoAdsClient -TwinCatRoot $TwinCatRoot -Port 851
function Write-Command([string]$Name,$Value){Write-DemoSymbol $client ('GVL_Command.'+$Name) $Value}
function Read-Cycle {Read-DemoSymbol $client 'GVL_Monitor.CycleCounter' ([uint32])}
function Wait-Cycles([uint32]$Previous){
    $watch=[Diagnostics.Stopwatch]::StartNew()
    while((Read-Cycle) -le $Previous+2){if($watch.Elapsed.TotalSeconds -gt 3){throw 'PLC cycles did not advance.'};Start-Sleep -Milliseconds 20}
}
function Pulse([string]$Name){
    Write-Command $Name ([bool]$false);Wait-Cycles (Read-Cycle)
    Write-Command $Name ([bool]$true)
    try{Wait-Cycles (Read-Cycle)}finally{Write-Command $Name ([bool]$false)}
}
try{
    if($client.ReadState().AdsState.ToString() -ne 'Run'){throw 'Dedicated demo PLC is not running.'}
    switch($Command){
        'Enable' {Write-Command 'Enable' ([bool]$true)}
        'Disable' {Write-Command 'Enable' ([bool]$false)}
        'Home' {Pulse 'Home'}
        'Move' {Write-Command 'TargetPosition' ([double]$Position);Write-Command 'Velocity' ([double]$Velocity);Pulse 'MoveRequest'}
        'Auto' {
            Write-Command 'Enable' ([bool]$true)
            $watch=[Diagnostics.Stopwatch]::StartNew()
            while((Read-DemoSymbol $client 'GVL_Monitor.Step' ([uint16])) -notin @(10,20)){
                if($watch.Elapsed.TotalSeconds -gt 5){throw 'Demo did not become ready; inspect Status.'}
                Start-Sleep -Milliseconds 30
            }
            Pulse 'AutoStart'
        }
        'Stop' {Write-Command 'Stop' ([bool]$true)}
        'ReleaseStop' {Write-Command 'Stop' ([bool]$false);Pulse 'ReleaseStop'}
        'Reset' {Pulse 'Reset'}
    }
    Read-DemoMonitor $client|ConvertTo-Json
}finally{$client.Dispose()}
