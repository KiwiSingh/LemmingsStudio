param([string]$OutputRoot = "$PSScriptRoot/dist")
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { throw 'Build the Windows bundle on Windows x64.' }
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
$buildRoot = Join-Path $OutputRoot 'intermediate'
$applicationRoot = Join-Path $OutputRoot 'application'
$mediaRoot = Join-Path $OutputRoot 'startup-media'
$repositoryRoot = Split-Path $PSScriptRoot -Parent
& python "$repositoryRoot/tools/stage_startup_resources.py" --output $mediaRoot
if ($LASTEXITCODE -ne 0) { throw 'Original startup resource staging failed.' }
New-Item -ItemType Directory -Force $OutputRoot | Out-Null
$nativeRoot = Join-Path $OutputRoot 'native-audio'
& cmake -S "$PSScriptRoot/native" -B $nativeRoot -A x64
if ($LASTEXITCODE -ne 0) { throw 'Native audio configure failed.' }
& cmake --build $nativeRoot --config Release
if ($LASTEXITCODE -ne 0) { throw 'Native audio build failed.' }
$nativeLibrary = Join-Path $nativeRoot 'Release/lemmings_audio.dll'
if (!(Test-Path $nativeLibrary)) { throw 'Native drum engine is missing.' }
$arguments = @(
    '-m','PyInstaller','--noconfirm','--clean','--windowed','--onedir',
    '--name','LemmingsStudio Windows Preview',
    '--distpath',$applicationRoot,'--workpath',$buildRoot,'--specpath',$buildRoot,
    '--paths',"$PSScriptRoot/src",
    '--collect-all','_sounddevice_data','--collect-all','_soundfile_data',
    '--copy-metadata','PySide6-Essentials','--copy-metadata','PySide6-Addons','--copy-metadata','shiboken6',
    '--collect-data','lemmings_studio',
    '--add-data',"${mediaRoot}:startup-media",
    '--add-data',"${nativeLibrary}:native-audio",
    '--copy-metadata','numpy','--copy-metadata','soundfile',
    '--copy-metadata','sounddevice','--copy-metadata','cffi',
    '--copy-metadata','pycparser',
    '--add-data',"$PSScriptRoot/LICENSE:licenses",
    "$PSScriptRoot/windows_entry.py"
)
& python @arguments
if ($LASTEXITCODE -ne 0) { throw 'Windows application bundling failed.' }
$app = Join-Path $applicationRoot 'LemmingsStudio Windows Preview/LemmingsStudio Windows Preview.exe'
if (!(Test-Path $app)) { throw 'The application executable is missing.' }
$report = Join-Path $OutputRoot 'bundle-smoke.json'
$process = Start-Process $app -ArgumentList @('--self-test-report',"`"$report`"") -PassThru
if (!$process.WaitForExit(180000)) { $process.Kill(); throw 'Bundle smoke test timed out.' }
if ($process.ExitCode -ne 0) {
    if (Test-Path $report) { Get-Content $report }
    throw "Bundle smoke test failed: $($process.ExitCode)"
}
$result = Get-Content $report -Raw | ConvertFrom-Json
if ($result.status -ne 'passed') { throw 'Bundle did not report successful checks.' }
Copy-Item "$PSScriptRoot/README.md" (Join-Path $applicationRoot 'README.md')
Get-FileHash $app -Algorithm SHA256 | ForEach-Object { "$($_.Hash.ToLowerInvariant())  LemmingsStudio Windows Preview/LemmingsStudio Windows Preview.exe" } | Set-Content (Join-Path $applicationRoot 'SHA256SUMS.txt') -Encoding ascii
Get-Content $report

# Offscreen checks cannot establish that the actual Windows presentation opens.
$startupReport = Join-Path $OutputRoot 'startup-check.json'
$previousPlatform = $env:QT_QPA_PLATFORM
try {
    $env:QT_QPA_PLATFORM = 'windows'
    $env:LEMMINGS_DIAGNOSTICS_DIR = Join-Path $OutputRoot 'launch-diagnostics'
    $env:QML_DISK_CACHE_PATH = Join-Path $OutputRoot 'qml-cache'
    $startup = Start-Process $app -ArgumentList @('--software-rendering','--startup-check-report',"`"$startupReport`"") -PassThru
    if (!$startup.WaitForExit(120000)) { $startup.Kill(); throw 'Real Windows startup check timed out.' }
    if ($startup.ExitCode -ne 0) {
        if (Test-Path $startupReport) { Get-Content $startupReport }
        throw "Real Windows startup check failed: $($startup.ExitCode)"
    }
    $startupResult = Get-Content $startupReport -Raw | ConvertFrom-Json
    if ($startupResult.status -ne 'passed') { throw 'Original media or Qt Quick presentation failed.' }
    $platformEvent = @($startupResult.events | Where-Object phase -eq 'application_created')[0]
    if ($platformEvent.platform -ne 'windows') { throw 'Startup was not tested with the real Windows platform.' }
    Get-Content $startupReport
} finally {
    $env:QT_QPA_PLATFORM = $previousPlatform
}
