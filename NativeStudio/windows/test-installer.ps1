param(
    [Parameter(Mandatory=$true)][string]$Installer,
    [Parameter(Mandatory=$true)][string]$TestRoot
)
$ErrorActionPreference = 'Stop'
if (Test-Path $TestRoot) { throw 'Use a new installer test directory.' }
New-Item -ItemType Directory $TestRoot | Out-Null
$destination = Join-Path $TestRoot 'Installed'
function Run-Setup([string]$LogName) {
    $arguments = @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART','/TYPE=full','/TASKS=desktopicon',"/DIR=`"$destination`"", "/LOG=`"$TestRoot/$LogName`"")
    $process = Start-Process -FilePath $Installer -ArgumentList $arguments -PassThru
    if (!$process.WaitForExit(180000)) { $process.Kill(); throw 'Installer timed out.' }
    if ($process.ExitCode -ne 0) { throw "Installer failed: $($process.ExitCode)" }
}
Run-Setup 'install.log'
$app = Join-Path $destination 'LemmingsStudio Native Preview.exe'
if (!(Test-Path $app)) { throw 'Application was not installed.' }
$desktopLink = Join-Path ([Environment]::GetFolderPath('Desktop')) 'LemmingsStudio Developer Preview.lnk'
if (!(Test-Path $desktopLink)) { throw 'Desktop shortcut missing.' }
$shortcut = (New-Object -ComObject WScript.Shell).CreateShortcut($desktopLink)
if ($shortcut.TargetPath -ne $app) { throw 'Desktop shortcut points to the wrong application.' }
$startLink = Join-Path ([Environment]::GetFolderPath('Programs')) 'LemmingsStudio Developer Preview/LemmingsStudio Developer Preview.lnk'
if (!(Test-Path $startLink)) { throw 'Start menu shortcut missing.' }
$registry = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\{E483DC89-9A5F-4DB3-9AC0-8D25F257B304}_is1'
if (!(Test-Path $registry)) { throw 'Per-user uninstall registration missing.' }
$manifest = Get-Content (Join-Path $destination 'build-manifest.json') -Raw | ConvertFrom-Json
foreach ($entry in $manifest.files) {
    $relative = $entry.path -replace '^App/','' -replace '^Diagnostics/','Diagnostics/'
    $installedFile = Join-Path $destination $relative
    if (!(Test-Path $installedFile -PathType Leaf)) { throw "Installed payload missing: $relative" }
    if ((Get-FileHash $installedFile -Algorithm SHA256).Hash.ToLowerInvariant() -ne $entry.sha256) { throw "Installed payload hash mismatch: $relative" }
}
$checks = Join-Path $destination 'Diagnostics/StudioChecks.exe'
& $checks
if ($LASTEXITCODE -ne 0) { throw 'Installed native audio/session checks failed.' }
$plugins = @(Get-ChildItem (Join-Path $destination 'Devices') -Recurse -Directory -Filter '*.vst3')
if ($plugins.Count -ne 3) { throw 'Expected three installed VST3 bundles.' }
& $checks @($plugins.FullName)
if ($LASTEXITCODE -ne 0) { throw 'Installed VST3 checks failed.' }
# Exercise launch from the installed path; this is not a real audio-device test.
$application = Start-Process -FilePath $app -PassThru
Start-Sleep -Seconds 8
if ($application.HasExited) { throw "Installed application exited unexpectedly: $($application.ExitCode)" }
$null = $application.CloseMainWindow()
if (!$application.WaitForExit(10000)) { $application.Kill(); $application.WaitForExit() }
# Both upgrade and uninstall must preserve files that setup did not install.
$userFile = Join-Path $destination 'User recording - keep.txt'
Set-Content $userFile 'Simulated user project: do not delete.' -Encoding utf8
$userHash = (Get-FileHash $userFile).Hash
Run-Setup 'upgrade.log'
if ((Get-FileHash $userFile).Hash -ne $userHash) { throw 'Reinstall changed user data.' }
$uninstaller = Join-Path $destination 'unins000.exe'
$process = Start-Process $uninstaller -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART',"/LOG=`"$TestRoot/uninstall.log`"") -PassThru
if (!$process.WaitForExit(180000)) { $process.Kill(); throw 'Uninstaller timed out.' }
if ($process.ExitCode -ne 0) { throw "Uninstall failed: $($process.ExitCode)" }
for ($attempt=0; $attempt -lt 20 -and (Test-Path $app); $attempt++) { Start-Sleep -Milliseconds 500 }
if (Test-Path $app) { throw 'Uninstall left the application executable behind.' }
if ((Test-Path $desktopLink) -or (Test-Path $startLink) -or (Test-Path $registry)) { throw 'Uninstall left shortcuts or registration behind.' }
if (!(Test-Path $userFile) -or (Get-FileHash $userFile).Hash -ne $userHash) { throw 'Uninstall deleted user data.' }
'PASS: payload hashes, shortcuts, per-user registration, installed checks, launch, reinstall and uninstall preservation.'
