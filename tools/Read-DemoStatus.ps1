param([string]$TwinCatRoot=$env:TWINCAT3DIR,[switch]$SystemOnly)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'DemoAds.psm1') -Force
$port=if($SystemOnly){10000}else{851}
$client=New-DemoAdsClient -TwinCatRoot $TwinCatRoot -Port $port
try{
    $state=$client.ReadState()
    if($SystemOnly){[pscustomobject]@{AmsNetId='127.0.0.1.10.22';AdsState=$state.AdsState.ToString();DeviceState=$state.DeviceState}|ConvertTo-Json}
    else{Read-DemoMonitor $client|ConvertTo-Json}
}finally{$client.Dispose()}
