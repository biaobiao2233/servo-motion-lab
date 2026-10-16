param([Parameter(Mandatory=$true)][string]$BuildDirectory)
$ErrorActionPreference='Stop'
$repoRoot=Split-Path -Parent $PSScriptRoot
$localRoot=Join-Path $repoRoot '.local'
$BuildDirectory=[IO.Path]::GetFullPath($BuildDirectory)
if(-not $BuildDirectory.StartsWith($repoRoot+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Build must belong to this repository.'}
$status=Get-Content -LiteralPath (Join-Path $localRoot 'runtime-status.json') -Raw|ConvertFrom-Json
$configRoot=Join-Path $localRoot 'runtime\ServoAxis-Demo\3.1'
if($status.Schema -ne 'servo-motion-lab-runtime-v1' -or $status.AmsNetId -ne '127.0.0.1.10.22' -or $status.ConfigurationRoot -ne $configRoot){throw 'Unexpected demo instance.'}
if($status.RuntimePid -and (Get-Process -Id $status.RuntimePid -ErrorAction SilentlyContinue)){throw 'Stop the dedicated demo Runtime before installing its boot files.'}
$marker=Get-Content -LiteralPath (Join-Path (Split-Path -Parent $configRoot) 'servo-instance.json') -Raw|ConvertFrom-Json
if($marker.ConfigurationRoot -ne $configRoot -or $marker.AmsNetId -ne $status.AmsNetId){throw 'Demo ownership marker mismatch.'}
$report=Get-Content -LiteralPath (Join-Path $localRoot 'native-build-report.json') -Raw|ConvertFrom-Json
if(-not $report.BuildSuccess -or -not $report.AxisBound -or $report.OutputDirectory -ne $BuildDirectory){throw 'A matching successful native build with axis binding is required.'}
foreach($source in $report.SourceFiles){
    $sourcePath=Join-Path (Join-Path $repoRoot 'examples\ServoAxis-Demo\src') $source.Name
    if((Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash -ne $source.Sha256){throw 'PLC source changed after the build.'}
}
$builtBoot=Join-Path $BuildDirectory 'ServoConfiguration\_Boot\TwinCAT OS (x64)'
$builtConfig=Join-Path $builtBoot 'CurrentConfig.xml'
[xml]$configuration=Get-Content -LiteralPath $builtConfig -Raw
$drivers=@($configuration.TcBootProject.Drivers.Driver|ForEach-Object{$_.ServiceName})
if($configuration.TcBootProject.ProjectInfo.ProjectName -ne 'ServoConfiguration' -or 'TcNc' -notin $drivers -or 'TcPlc30' -notin $drivers){throw 'Expected NC/PLC demo configuration is missing.'}
$builtPlc=Join-Path $builtBoot 'Plc'
if(-not(Test-Path -LiteralPath (Join-Path $builtPlc 'Port_851.app'))){throw 'Built PLC application is missing.'}
$destinationBoot=Join-Path $configRoot 'Boot'
$backup=Join-Path 'E:\AGENT\Backups\Servo-Motion-Lab' ('Boot-'+(Get-Date -Format 'yyyyMMdd-HHmmss'))
if(Test-Path -LiteralPath $backup){throw 'Backup destination already exists.'}
New-Item -ItemType Directory -Path $backup -Force|Out-Null
Copy-Item -LiteralPath $destinationBoot -Destination $backup -Recurse
# 仅安装已验证候选到自有实例；Boot 文件保持原生构建生成的内容。
Copy-Item -LiteralPath $builtConfig -Destination (Join-Path $destinationBoot 'CurrentConfig.xml') -Force
$destinationPlc=Join-Path $destinationBoot 'Plc'
New-Item -ItemType Directory -Path $destinationPlc -Force|Out-Null
Get-ChildItem -LiteralPath $builtPlc -File|Copy-Item -Destination $destinationPlc -Force
$receipt=[ordered]@{Stage='BOOT_INSTALLED_RUNTIME_NOT_RUN';ObservedAt=(Get-Date).ToString('o');AmsNetId=$status.AmsNetId;BuildDirectory=$BuildDirectory;Backup=$backup;SourceFiles=$report.SourceFiles;ConfigSha256=(Get-FileHash -LiteralPath $builtConfig -Algorithm SHA256).Hash;PlcSha256=(Get-FileHash -LiteralPath (Join-Path $builtPlc 'Port_851.app') -Algorithm SHA256).Hash}
if((Get-FileHash -LiteralPath (Join-Path $destinationBoot 'CurrentConfig.xml') -Algorithm SHA256).Hash -ne $receipt.ConfigSha256){throw 'Configuration readback mismatch.'}
if((Get-FileHash -LiteralPath (Join-Path $destinationPlc 'Port_851.app') -Algorithm SHA256).Hash -ne $receipt.PlcSha256){throw 'PLC application readback mismatch.'}
$receipt|ConvertTo-Json -Depth 10|Set-Content -LiteralPath (Join-Path $localRoot 'deployment-receipt.json') -Encoding UTF8
$receipt|ConvertTo-Json -Depth 10
