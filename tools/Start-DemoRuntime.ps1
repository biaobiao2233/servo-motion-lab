param(
    [string]$TwinCatRoot = $env:TWINCAT3DIR,
    [ValidatePattern('^(?:\d{1,3}\.){5}\d{1,3}$')][string]$AmsNetId = '127.0.0.1.10.22',
    [ValidateRange(64,512)][int]$HeapMemoryMB = 128
)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$localRoot = Join-Path $repoRoot '.local'
$instanceRoot = Join-Path $localRoot 'runtime\ServoAxis-Demo'
$configRoot = Join-Path $instanceRoot '3.1'
$marker = Join-Path $instanceRoot 'servo-instance.json'
$statusPath = Join-Path $localRoot 'runtime-status.json'
$commandPath = Join-Path $localRoot 'runtime-command.txt'
if (-not $TwinCatRoot) { throw 'Supply -TwinCatRoot with the installed TwinCAT 3.1 directory.' }
$TwinCatRoot = (Resolve-Path -LiteralPath $TwinCatRoot).Path
$binary = Join-Path $TwinCatRoot 'Runtimes\bin\TcSystemServiceUm.exe'
$template = Join-Path $TwinCatRoot 'Runtimes\UmRT_Template'
if (-not (Test-Path -LiteralPath (Join-Path $TwinCatRoot 'Runtimes\bin\TcNc.tmx'))) { throw 'The official NC usermode component is missing.' }
if (@($AmsNetId.Split('.') | Where-Object { [int]$_ -gt 255 }).Count) { throw 'Invalid AMS octet.' }
if (Test-Path -LiteralPath $statusPath) {
    $old = Get-Content -LiteralPath $statusPath -Raw | ConvertFrom-Json
    if ($old.RuntimePid -and (Get-Process -Id $old.RuntimePid -ErrorAction SilentlyContinue)) { throw 'The recorded demo process is still alive. Stop it first.' }
}
if (Test-Path -LiteralPath $instanceRoot) {
    if (-not (Test-Path -LiteralPath $marker)) { throw 'Refusing to reuse an unowned Runtime directory.' }
    $owned = Get-Content -LiteralPath $marker -Raw | ConvertFrom-Json
    if ($owned.Schema -ne 'servo-motion-lab-runtime-v1' -or $owned.AmsNetId -ne $AmsNetId -or $owned.ConfigurationRoot -ne $configRoot) { throw 'Runtime identity mismatch.' }
} else {
    New-Item -ItemType Directory -Path $instanceRoot -Force | Out-Null
    Get-ChildItem -LiteralPath $template | Copy-Item -Destination $instanceRoot -Recurse
    [ordered]@{ Schema='servo-motion-lab-runtime-v1'; Name='ServoAxisDemo'; AmsNetId=$AmsNetId; ConfigurationRoot=$configRoot } |
        ConvertTo-Json | Set-Content -LiteralPath $marker -Encoding UTF8
}
# 只修改本项目的实例注册表；不修改系统注册表及 UmRT_Default。
$registryPath = Join-Path $configRoot 'TcRegistry.xml'
[xml]$registry = Get-Content -LiteralPath $registryPath -Raw
$systemKey = $registry.SelectSingleNode('//Key[@Name="TwinCAT3"]/Key[@Name="System"]')
foreach ($spec in @(@('HeapMemSizeMB','DW',[string]$HeapMemoryMB),@('AmsNetId','BIN',(($AmsNetId.Split('.') | ForEach-Object { '{0:X2}' -f [int]$_ }) -join '')))) {
    $value = $systemKey.SelectSingleNode('Value[@Name="' + $spec[0] + '"]')
    if (-not $value) { $value=$registry.CreateElement('Value'); [void]$systemKey.AppendChild($value) }
    $value.SetAttribute('Name',$spec[0]); $value.SetAttribute('Type',$spec[1]); $value.InnerText=$spec[2]
}
$registry.Save($registryPath)
$stdoutPath = Join-Path $localRoot 'runtime-stdout.log'
$stderrPath = Join-Path $localRoot 'runtime-stderr.log'
[IO.File]::WriteAllText($stdoutPath,''); [IO.File]::WriteAllText($stderrPath,'')
[IO.File]::WriteAllText($commandPath,'')
$start = New-Object Diagnostics.ProcessStartInfo
$start.FileName = $binary
$start.Arguments = '-t bin -n ServoAxisDemo -i ' + $AmsNetId + ' -c "' + $configRoot + '"'
$start.WorkingDirectory = $instanceRoot
$start.UseShellExecute = $false
$start.CreateNoWindow = $true
$start.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
$start.RedirectStandardInput = $true
$start.RedirectStandardOutput = $true
$start.RedirectStandardError = $true
$runtime = New-Object Diagnostics.Process
$runtime.StartInfo = $start
$runtimeStarted = $false
$status = [ordered]@{ Schema='servo-motion-lab-runtime-v1'; AmsNetId=$AmsNetId; ConfigurationRoot=$configRoot; HostPid=$PID; RuntimePid=$null; Stage='STARTING'; StartedAt=(Get-Date).ToString('o') }
try {
    $runtimeStarted = $runtime.Start()
    if (-not $runtimeStarted) { throw 'Runtime process did not start.' }
    $status.RuntimePid=$runtime.Id; $status.Stage='PROCESS_STARTED'
    $status | ConvertTo-Json | Set-Content -LiteralPath $statusPath -Encoding UTF8
    Write-Output ('Demo Runtime process started: ' + $runtime.Id + '. This is not proof of PLC/NC RUN.')
    $outTask=$runtime.StandardOutput.ReadLineAsync(); $errTask=$runtime.StandardError.ReadLineAsync()
    $lastCommandTime=(Get-Item -LiteralPath $commandPath).LastWriteTimeUtc
    while (-not $runtime.HasExited) {
        foreach ($stream in @('stdout','stderr')) {
            $task=if($stream -eq 'stdout'){$outTask}else{$errTask}
            if ($task -and $task.IsCompleted) {
                $line=$task.Result
                if ($null -ne $line) {
                    $logPath=if($stream -eq 'stdout'){$stdoutPath}else{$stderrPath}
                    [IO.File]::AppendAllText($logPath,$line+[Environment]::NewLine)
                    if($stream -eq 'stdout'){$outTask=$runtime.StandardOutput.ReadLineAsync()}else{$errTask=$runtime.StandardError.ReadLineAsync()}
                } else { if($stream -eq 'stdout'){$outTask=$null}else{$errTask=$null} }
            }
        }
        $commandFile=Get-Item -LiteralPath $commandPath
        if ($commandFile.LastWriteTimeUtc -ne $lastCommandTime) {
            $lastCommandTime=$commandFile.LastWriteTimeUtc
            $command=(Get-Content -LiteralPath $commandPath -Raw).Trim()
            if ($command -in @('s','x')) {
                $runtime.StandardInput.WriteLine($command); $runtime.StandardInput.Flush()
                # 无控制台时官方键盘命令可能不读取管道；退出请求超时仅结束本宿主创建的进程。
                if($command -eq 'x' -and -not $runtime.WaitForExit(3000)){
                    $runtime.Kill();$runtime.WaitForExit();$status.ExitMethod='OWNED_PROCESS_AFTER_X_TIMEOUT'
                }
            }
        }
        Start-Sleep -Milliseconds 100
    }
    $status.Stage='EXITED'; $status.ExitCode=$runtime.ExitCode
} finally {
    if ($runtimeStarted -and -not $runtime.HasExited) {
        $runtime.StandardInput.WriteLine('x'); $runtime.StandardInput.Flush()
        if (-not $runtime.WaitForExit(8000)) { $status.Stage='STOP_TIMEOUT'; Write-Warning 'The owned Runtime did not exit; inspect its recorded PID.' }
        else { $status.Stage='EXITED'; $status.ExitCode=$runtime.ExitCode }
    }
    $status.CompletedAt=(Get-Date).ToString('o')
    $status | ConvertTo-Json | Set-Content -LiteralPath $statusPath -Encoding UTF8
    $runtime.Dispose()
}
