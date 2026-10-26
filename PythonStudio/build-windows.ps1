param([string]$OutputRoot = "$PSScriptRoot/dist")
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { throw 'Build the Windows bundle on Windows x64.' }
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
$buildRoot = Join-Path $OutputRoot 'intermediate'
$applicationRoot = Join-Path $OutputRoot 'application'
New-Item -ItemType Directory -Force $OutputRoot | Out-Null
$arguments = @(
    '-m','PyInstaller','--noconfirm','--clean','--windowed','--onedir',
    '--name','LemmingsStudio Windows Preview',
    '--distpath',$applicationRoot,'--workpath',$buildRoot,'--specpath',$buildRoot,
    '--paths',"$PSScriptRoot/src",
    '--collect-all','_sounddevice_data','--collect-all','_soundfile_data',
    '--copy-metadata','PySide6-Essentials','--copy-metadata','shiboken6',
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
