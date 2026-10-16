param([Parameter(Mandatory=$true)][ValidateSet('Config','Run')][string]$State,[string]$TwinCatRoot=$env:TWINCAT3DIR)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'DemoAds.psm1') -Force
$client=New-DemoAdsClient -TwinCatRoot $TwinCatRoot -Port 10000
try{
    # 系统服务使用 Reset/Reconfig；PLC 851 的 Run/Stop 命令不能用于系统服务。
    $requested=if($State -eq 'Run'){[TwinCAT.Ads.AdsState]::Reset}else{[TwinCAT.Ads.AdsState]::Reconfig}
    $client.WriteControl([TwinCAT.Ads.StateInfo]::new($requested,[int16]0))
    # 用户态实例切换会重建 ADS 服务；旧客户端不可作为新服务的状态证据。
    $client.Dispose();$client=$null
    $watch=[Diagnostics.Stopwatch]::StartNew()
    $observed=$null
    while($watch.Elapsed.TotalSeconds -lt 15){
        Start-Sleep -Milliseconds 100
        try{
            if(-not $client){$client=New-DemoAdsClient -TwinCatRoot $TwinCatRoot -Port 10000}
            $observed=$client.ReadState()
        }catch{
            if($client){$client.Dispose();$client=$null}
            # 重启期间 ADS 端口可能暂时消失；在有限时间内等待恢复。
            if($watch.Elapsed.TotalSeconds -ge 15){throw}
            continue
        }
        if($observed.AdsState.ToString() -eq $State){break}
    }
    if(-not $observed){throw 'The dedicated Runtime ADS port did not recover.'}
    [pscustomobject]@{AmsNetId='127.0.0.1.10.22';Requested=$State;Command=$requested.ToString();Observed=$observed.AdsState.ToString();DeviceState=$observed.DeviceState}|ConvertTo-Json
    if($observed.AdsState.ToString() -ne $State){throw 'The dedicated Runtime did not reach the requested state.'}
}finally{if($client){$client.Dispose()}}
