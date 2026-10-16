param(
    [string]$TwinCatRoot=$env:TWINCAT3DIR,
    [string]$Solution,
    [string]$XaePublicAssemblies='C:\Program Files\Beckhoff\TcXaeShell\Common7\IDE\PublicAssemblies'
)
$ErrorActionPreference='Stop'
if($PSVersionTable.PSEdition -eq 'Core'){throw '请使用 Windows PowerShell 5.1 x64 或仓库根目录的 Start-ServoDemo.cmd。'}
if(-not [Environment]::Is64BitProcess){throw '需要 64 位 Windows PowerShell。'}
$repo=Split-Path $PSScriptRoot
$local=Join-Path $repo '.local'
if(-not $TwinCatRoot){$TwinCatRoot='D:\Beckhoff\TwinCAT\3.1'}
if(-not(Test-Path -LiteralPath $TwinCatRoot)){throw '找不到 TwinCAT，请通过 -TwinCatRoot 指定本机安装目录。'}
$windowStatus=Join-Path $local 'native-visu-status.json'
if(-not $Solution){
    if(-not(Test-Path -LiteralPath $windowStatus)){throw '缺少已保存的演示工程记录；请先生成、构建并配置工程，或指定 -Solution。'}
    $Solution=(Get-Content -LiteralPath $windowStatus -Raw|ConvertFrom-Json).Solution
}
$Solution=[IO.Path]::GetFullPath($Solution)
if(-not $Solution.StartsWith($repo+'\',[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($Solution) -ne 'ServoAxisDemo.sln' -or -not(Test-Path -LiteralPath $Solution)){throw '演示解决方案不存在或不属于此仓库。'}
foreach($file in @('Boot\CurrentConfig.xml','Boot\Plc\Port_851.app')){
    if(-not(Test-Path -LiteralPath (Join-Path $local ('runtime\ServoAxis-Demo\3.1\'+$file)))){throw '缺少专用实例的已安装 Boot 配置；启动入口不会代替首次部署。'}
}
$runtimeStatus=Join-Path $local 'runtime-status.json'
$old=if(Test-Path -LiteralPath $runtimeStatus){Get-Content -LiteralPath $runtimeStatus -Raw|ConvertFrom-Json}else{$null}
$running=if($old -and $old.RuntimePid){Get-Process -Id $old.RuntimePid -ErrorAction SilentlyContinue}else{$null}
if($running -and $running.ProcessName -ne 'TcSystemServiceUm'){throw '旧运行记录的 PID 被其他程序占用，请先核查记录；不会结束该程序。'}
if($running -and [Math]::Abs(($running.StartTime-([datetimeoffset]::Parse($old.StartedAt)).LocalDateTime).TotalSeconds) -gt 5){throw '运行记录与进程创建时间不符，可能是重启后 PID 被复用；不会操作该进程。'}
if(-not $running){
    Write-Host '启动专用 NC/PLC 仿真后台……'
    $hostArgs=@('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+(Join-Path $PSScriptRoot 'Start-DemoRuntime.ps1')+'"'),'-TwinCatRoot',('"'+$TwinCatRoot+'"'))
    $hostProcess=Start-Process -FilePath powershell.exe -ArgumentList $hostArgs -WindowStyle Hidden -PassThru
    $watch=[Diagnostics.Stopwatch]::StartNew()
    do{
        Start-Sleep -Milliseconds 200
        if($hostProcess.HasExited){throw '仿真宿主退出，请检查 .local/runtime-stderr.log。'}
        try{$now=Get-Content -LiteralPath $runtimeStatus -Raw|ConvertFrom-Json}catch{$now=$null}
        if($now -and $now.HostPid -eq $hostProcess.Id -and $now.RuntimePid){break}
    }while($watch.Elapsed.TotalSeconds -lt 20)
    if(-not $now -or $now.HostPid -ne $hostProcess.Id){throw '仿真实例启动超时。'}
}
Import-Module (Join-Path $PSScriptRoot 'DemoAds.psm1') -Force
# 出现进程不表示 ADS 已就绪。先等端口注册，再读取实际系统状态。
$watch=[Diagnostics.Stopwatch]::StartNew();$systemState=$null
do{
    $client=$null
    try{$client=New-DemoAdsClient -TwinCatRoot $TwinCatRoot -Port 10000;$systemState=$client.ReadState();break}
    catch{if($watch.Elapsed.TotalSeconds -ge 20){throw};Start-Sleep -Milliseconds 250}
    finally{if($client){$client.Dispose()}}
}while($watch.Elapsed.TotalSeconds -lt 21)
if(-not $systemState){throw '专用 Runtime 的 ADS 端口未就绪。'}
if($systemState.AdsState.ToString() -ne 'Run'){& (Join-Path $PSScriptRoot 'Set-DemoRuntimeState.ps1') -State Run -TwinCatRoot $TwinCatRoot}
$client=New-DemoAdsClient -TwinCatRoot $TwinCatRoot
try{
    if($client.ReadState().AdsState.ToString() -ne 'Run'){throw 'PLC 没有进入 Run，请检查官方许可与 Boot 配置。'}
    $before=Read-DemoSymbol $client 'GVL_Monitor.CycleCounter' ([uint32]);$watch=[Diagnostics.Stopwatch]::StartNew()
    do{Start-Sleep -Milliseconds 100;$after=Read-DemoSymbol $client 'GVL_Monitor.CycleCounter' ([uint32])}while($after -eq $before -and $watch.Elapsed.TotalSeconds -lt 5)
    if($after -eq $before){throw 'PLC 周期计数没有增加。'}
}finally{$client.Dispose()}
$sdk=Join-Path $local 'sdk\TCatSysManagerLib.dll'
$interop=Join-Path $XaePublicAssemblies 'Microsoft.VisualStudio.Interop.dll'
Add-Type -Path $sdk;Add-Type -Path $interop
Add-Type -Path (Join-Path $PSScriptRoot 'DemoSession.cs') -ReferencedAssemblies @($sdk,$interop)
Write-Host '打开已保存的演示工程并在线登录……'
$dte=[ServoDemoSession]::OpenSaved($Solution)
$online=[ServoDemoSession]::LoginAndShow($dte,$Solution)
[ordered]@{Schema='servo-native-visu-v1';Solution=$Solution;XaePid=[ServoDemoSession]::Pid($dte);CreatedAt=(Get-Date).ToString('o')}|ConvertTo-Json|Set-Content -LiteralPath $windowStatus -Encoding UTF8
[ordered]@{ObservedAt=(Get-Date).ToString('o');Solution=$Solution;RuntimeStartedNow=(-not [bool]$running);PlcState='Run';CycleBefore=$before;CycleAfter=$after;Online=$online;MotionStarted=$false}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $local 'session-start.json') -Encoding UTF8
Write-Host '演示已在线。点击 TwinCAT 面板里的“自动演示”开始；本入口不会自动发起运动。'
