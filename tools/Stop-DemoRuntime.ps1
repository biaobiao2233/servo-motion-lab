$ErrorActionPreference='Stop'
$localRoot=Join-Path (Split-Path -Parent $PSScriptRoot) '.local'
$statusPath=Join-Path $localRoot 'runtime-status.json'
if (-not (Test-Path -LiteralPath $statusPath)) { throw 'No recorded demo Runtime.' }
$status=Get-Content -LiteralPath $statusPath -Raw | ConvertFrom-Json
if ($status.Schema -ne 'servo-motion-lab-runtime-v1') { throw 'Unknown Runtime ownership marker.' }
# 向本项目宿主请求官方 x 命令，不停止系统服务，也不按进程名称批量结束。
Set-Content -LiteralPath (Join-Path $localRoot 'runtime-command.txt') -Value 'x' -Encoding ASCII
Write-Output 'Requested graceful exit of the owned demo Runtime.'
