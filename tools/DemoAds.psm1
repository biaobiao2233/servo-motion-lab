$ErrorActionPreference='Stop'
$script:RepoRoot=Split-Path -Parent $PSScriptRoot
function New-DemoAdsClient {
    param([string]$TwinCatRoot=$env:TWINCAT3DIR,[ValidateSet(851,10000)][int]$Port=851)
    $statusPath=Join-Path $script:RepoRoot '.local\runtime-status.json'
    $status=Get-Content -LiteralPath $statusPath -Raw|ConvertFrom-Json
    if($status.Schema -ne 'servo-motion-lab-runtime-v1' -or $status.AmsNetId -ne '127.0.0.1.10.22' -or -not $status.RuntimePid){throw 'Unexpected demo instance identity.'}
    if(-not(Get-Process -Id $status.RuntimePid -ErrorAction SilentlyContinue)){throw 'The recorded demo Runtime is not alive.'}
    if(-not $TwinCatRoot){throw 'Supply the installed TwinCAT 3.1 root.'}
    $expectedRoot=Join-Path $script:RepoRoot '.local\runtime\ServoAxis-Demo\3.1'
    if($status.ConfigurationRoot -ne $expectedRoot){throw 'Unexpected demo configuration directory.'}
    $marker=Get-Content -LiteralPath (Join-Path (Split-Path -Parent $expectedRoot) 'servo-instance.json') -Raw|ConvertFrom-Json
    if($marker.AmsNetId -ne $status.AmsNetId -or $marker.ConfigurationRoot -ne $expectedRoot){throw 'Demo ownership marker mismatch.'}
    if(-not ('ServoAdsLoader' -as [type])){
        Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; public static class ServoAdsLoader { [DllImport("kernel32", CharSet=CharSet.Unicode, SetLastError=true)] public static extern IntPtr LoadLibrary(string path); }'
    }
    $parent=Split-Path -Parent $TwinCatRoot
    if([ServoAdsLoader]::LoadLibrary((Join-Path $parent 'Common64\TcAdsDll.dll')) -eq [IntPtr]::Zero){throw 'Official ADS native DLL not available.'}
    if(-not ('TwinCAT.Ads.TcAdsClient' -as [type])){
        $gac=Join-Path $TwinCatRoot 'Components\Plc\LacBinaries\GAC_MSIL\TwinCAT.Ads'
        $dll=Get-ChildItem -LiteralPath $gac -Recurse -File -Filter 'TwinCAT.Ads.dll'|Sort-Object FullName -Descending|Select-Object -First 1
        if(-not $dll){throw 'The installed ADS .NET client is unavailable.'}
        Add-Type -Path $dll.FullName
    }
    $client=New-Object TwinCAT.Ads.TcAdsClient
    $client.Connect($status.AmsNetId,$Port)
    return $client
}
function Read-DemoSymbol {
    param($Client,[string]$Name,[type]$Type)
    if($Name -notmatch '^GVL_(Command|Monitor|Motion)\.') {throw 'Only demo symbols are allowed.'}
    $handle=$Client.CreateVariableHandle($Name)
    try{return $Client.ReadAny($handle,$Type)}finally{$Client.DeleteVariableHandle($handle)}
}
function Write-DemoSymbol {
    param($Client,[string]$Name,$Value)
    $allowed=@('Enable','Home','MoveRequest','AutoStart','Stop','ReleaseStop','Reset','TargetPosition','Velocity')
    if($Name -notmatch '^GVL_Command\.(.+)$' -or $Matches[1] -notin $allowed){throw 'Only whitelisted demo commands can be written.'}
    $handle=$Client.CreateVariableHandle($Name)
    try{$Client.WriteAny($handle,$Value)}finally{$Client.DeleteVariableHandle($handle)}
}
function Read-DemoMonitor {
    param($Client)
    $row=[ordered]@{ObservedAt=(Get-Date).ToString('o')}
    foreach($name in @('ActualPosition','ActualVelocity','TargetPosition')){$row[$name]=Read-DemoSymbol $Client ('GVL_Monitor.'+$name) ([double])}
    foreach($name in @('Step','AutoIndex')){$row[$name]=Read-DemoSymbol $Client ('GVL_Monitor.'+$name) ([uint16])}
    foreach($name in @('Enabled','Homed','AutoActive','Busy','Done','MoveBusy','MoveDone','HomeBusy','HomeDone','StopBusy','StopDone','StopHeld','ResetBusy','ResetDone','CommandAborted','Error')){$row[$name]=Read-DemoSymbol $Client ('GVL_Monitor.'+$name) ([bool])}
    foreach($name in @('ErrorID','ApplicationErrorID','NativeErrorID','CompletedMoves','RejectedCommands','CompletedAutoCycles','CycleCounter')){$row[$name]=Read-DemoSymbol $Client ('GVL_Monitor.'+$name) ([uint32])}
    return [pscustomobject]$row
}
Export-ModuleMember -Function New-DemoAdsClient,Read-DemoSymbol,Write-DemoSymbol,Read-DemoMonitor
