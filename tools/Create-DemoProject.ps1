param(
    [string]$TwinCatRoot=$env:TWINCAT3DIR,
    [string]$InteropAssembly,
    [string]$OutputDirectory,
    [switch]$SkipBuild,
    [switch]$BuildExisting,
    [switch]$Activate,
    [string]$XaePublicAssemblies='C:\Program Files\Beckhoff\TcXaeShell\Common7\IDE\PublicAssemblies'
)
$ErrorActionPreference='Stop'
$repoRoot=Split-Path -Parent $PSScriptRoot
$localRoot=Join-Path $repoRoot '.local'
if(-not $InteropAssembly){$InteropAssembly=Join-Path $localRoot 'sdk\TCatSysManagerLib.dll'}
if(-not $OutputDirectory){$OutputDirectory=Join-Path $repoRoot 'examples\ServoAxis-Demo\TwinCAT'}
if(-not $TwinCatRoot){throw 'Supply the installed TwinCAT 3.1 root.'}
$OutputDirectory=[IO.Path]::GetFullPath($OutputDirectory)
if(-not $OutputDirectory.StartsWith($repoRoot+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Output must be inside this repository.'}
if((Test-Path -LiteralPath $OutputDirectory) -and -not $BuildExisting){throw 'Refusing to overwrite an existing project directory.'}
if(-not $BuildExisting){New-Item -ItemType Directory -Path $OutputDirectory|Out-Null}
New-Item -ItemType Directory -Path $localRoot -Force|Out-Null
$env:TEMP=Join-Path $localRoot 'temp';$env:TMP=$env:TEMP
New-Item -ItemType Directory -Path $env:TEMP -Force|Out-Null
Add-Type -Path $InteropAssembly
Add-Type -Path (Join-Path $XaePublicAssemblies 'Microsoft.VisualStudio.Interop.dll')
Add-Type -Path (Join-Path $PSScriptRoot 'NativeEngineering.cs') -ReferencedAssemblies @($InteropAssembly,(Join-Path $XaePublicAssemblies 'Microsoft.VisualStudio.Interop.dll'),'System.Xml.Linq.dll','System.Xml.dll')
$reportPath=Join-Path $localRoot 'native-build-report.json'
$report=[ordered]@{Stage='START';ProjectCreated=$false;BuildExecuted=$false;BuildSuccess=$false;ConfigurationActivationRequested=$false;OutputDirectory=$OutputDirectory;StartedAt=(Get-Date).ToString('o')}
if($Activate -and $SkipBuild){throw 'Activation requires native build.'}
function Save-Report{$report|ConvertTo-Json -Depth 10|Set-Content -LiteralPath $reportPath -Encoding UTF8}
function Invoke-ComRetry([scriptblock]$Call){
    $watch=[Diagnostics.Stopwatch]::StartNew()
    while($true){try{return (& $Call)}catch{
        if($_.Exception.HResult -notin @(-2147418111,-2147417846) -or $watch.Elapsed.TotalSeconds -gt 90){throw}
        Start-Sleep -Milliseconds 300
    }}
}
$dte=$null
try{
    $report.Stage='CREATE_OWN_DTE';Save-Report
    $dte=New-Object -ComObject 'TcXaeShell.DTE.17.0'
    Invoke-ComRetry {$dte.SuppressUI=$true}
    Invoke-ComRetry {$dte.UserControl=$false}
    Invoke-ComRetry {$dte.MainWindow.Visible=$false}
    $solution=$dte.Solution
    if($solution.Projects.Count -ne 0 -or $solution.FullName){throw 'Expected a new empty IDE session.'}
    $solutionPath=Join-Path $OutputDirectory 'ServoAxisDemo.sln'
    if($BuildExisting){
        Invoke-ComRetry {$solution.Open($solutionPath)}
        $expectedProject=Join-Path $OutputDirectory 'ServoConfiguration\ServoConfiguration.tsproj'
        $report.Stage='WAIT_FOR_OWN_PROJECT_LOAD';Save-Report
        $loadWatch=[Diagnostics.Stopwatch]::StartNew();$project=$null
        while(-not $project -and $loadWatch.Elapsed.TotalSeconds -lt 90){
            for($i=1;$i -le $solution.Projects.Count;$i++){
                $candidate=$solution.Projects.Item($i)
                $candidatePath=$candidate.FullName
                if($candidatePath -and [IO.Path]::GetFullPath($candidatePath) -eq [IO.Path]::GetFullPath($expectedProject)){$project=$candidate;break}
            }
            if(-not $project){Start-Sleep -Milliseconds 300}
        }
        if(-not $project){throw 'The expected owned TwinCAT project did not load.'}
        $objectWatch=[Diagnostics.Stopwatch]::StartNew()
        while(-not $project.Object -and $objectWatch.Elapsed.TotalSeconds -lt 90){Start-Sleep -Milliseconds 300}
        if(-not $project.Object){throw 'The TwinCAT Automation Interface object did not become ready.'}
    }else{
        $solution.Create($OutputDirectory,'ServoAxisDemo');$solution.SaveAs($solutionPath)
        $report.Stage='CREATE_CONFIGURATION';Save-Report
        $template=Join-Path $TwinCatRoot 'Components\Base\PrjTemplate\TwinCAT Project.tsproj'
        $project=Invoke-ComRetry {$solution.AddFromTemplate($template,(Join-Path $OutputDirectory 'ServoConfiguration'),'ServoConfiguration')}
    }
    $report.Stage='AUTHOR_AXIS_AND_PLC';Save-Report
    $sourceRoot=Join-Path $repoRoot 'examples\ServoAxis-Demo\src'
    if($BuildExisting){
        [ServoNativeEngineering]::SynchronizeSources($project.Object,$sourceRoot)
        $report.TargetNetId='127.0.0.1.10.22'
    }else{
        $result=[ServoNativeEngineering]::CreateAxisAndPlc($project.Object,$sourceRoot,$localRoot)
        $report.AxisPath=$result[0];$report.PlcPath=$result[1];$report.TargetNetId=$result[2]
    }
    $report.SourceFiles=@(Get-ChildItem -LiteralPath $sourceRoot -File|ForEach-Object{[pscustomobject]@{Name=$_.Name;Sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash}})
    Invoke-ComRetry {$dte.ExecuteCommand('File.SaveAll')}
    $solution.SaveAs($solutionPath)
    $report.ProjectCreated=$true
    if($Activate){
        Import-Module (Join-Path $PSScriptRoot 'DemoAds.psm1') -Force
        $systemClient=New-DemoAdsClient -TwinCatRoot $TwinCatRoot -Port 10000
        try{$report.RuntimeBefore=$systemClient.ReadState().AdsState.ToString()}finally{$systemClient.Dispose()}
        [ServoNativeEngineering]::PrepareDemoBoot($project.Object)
    }
    if(-not $SkipBuild){
        # 本机专用用户态目标报告 TwinCAT OS (x64)，必须与解决方案构建平台一致。
        $report.BuildContexts=@([ServoNativeEngineering]::SelectBuildConfiguration($dte))
        $report.Stage='PLC_CHECK_ALL_OBJECTS';Save-Report
        try{$report.PlcCheckResult=[ServoNativeEngineering]::CheckPlcObjects($project.Object)}
        catch{$report.PlcCheckError=$_.Exception.ToString()}
        [void][ServoNativeEngineering]::CaptureBuildEvidence($dte,$localRoot)
        Copy-Item -LiteralPath (Join-Path $localRoot 'native-diagnostics.xml') -Destination (Join-Path $localRoot 'plc-check-diagnostics.xml')
        Copy-Item -LiteralPath (Join-Path $localRoot 'native-build-output.log') -Destination (Join-Path $localRoot 'plc-check-output.log')
        $report.Stage='NATIVE_BUILD';$report.BuildExecuted=$true;Save-Report
        Invoke-ComRetry {$solution.SolutionBuild.Build($true)}
        $report.BuildState=[int]$solution.SolutionBuild.BuildState
        $report.LastBuildInfo=[int]$solution.SolutionBuild.LastBuildInfo
        [xml]$diagnosticXml=[ServoNativeEngineering]::CaptureBuildEvidence($dte,$localRoot)
        $diagnostics=@($diagnosticXml.Diagnostics.Diagnostic|Where-Object{$_}|ForEach-Object{[pscustomobject]@{Description=$_.Description;Level=[int]$_.Level;FileName=$_.File;Line=[int]$_.Line}})
        $report.Diagnostics=$diagnostics
        $report.BuildSuccess=($report.BuildState -eq 3 -and $report.LastBuildInfo -eq 0 -and @($diagnostics|Where-Object{$_.Level -eq 4}).Count -eq 0)
        $report.OutputCaptured=((Get-Item -LiteralPath (Join-Path $localRoot 'native-build-output.log')).Length -gt 0)
        [ServoNativeEngineering]::ExportPlcInstance($project.Object,$localRoot)
        if($report.BuildSuccess){
            $report.Stage='BIND_AXIS';Save-Report
            $report.AxisMapping=[ServoNativeEngineering]::BindAxis($project.Object,$localRoot)
            $report.AxisBound=$true
        }
    }
    Invoke-ComRetry {$dte.ExecuteCommand('File.SaveAll')}
    $solution.SaveAs($solutionPath)
    if($Activate){
        if(-not $report.BuildSuccess -or -not $report.AxisBound){throw 'Refusing activation without successful native build and axis binding.'}
        $report.Stage='BUILD_BOUND_CONFIGURATION';Save-Report
        Invoke-ComRetry {$solution.SolutionBuild.Build($true)}
        if([int]$solution.SolutionBuild.LastBuildInfo -ne 0){throw 'Bound configuration build failed.'}
        [void][ServoNativeEngineering]::CaptureBuildEvidence($dte,$localRoot)
        $report.Stage='ACTIVATE_CONFIGURATION';Save-Report
        [ServoNativeEngineering]::ActivateDemoConfiguration($project.Object)
        $report.ConfigurationActivationRequested=$true
        $report.Stage='START_DEMO_RUNTIME';Save-Report
        [ServoNativeEngineering]::RestartDemoRuntime($project.Object)
        $report.RestartRequested=$true
    }
    $report.Stage='COMPLETE';$report.CompletedAt=(Get-Date).ToString('o');Save-Report
    $report|ConvertTo-Json -Depth 10
}catch{
    $report.Error=$_.Exception.ToString();Save-Report
    throw
}finally{if($dte){Invoke-ComRetry {$dte.Quit()}}}
