param([Parameter(Mandatory=$true)][string]$Installer,[Parameter(Mandatory=$true)][string]$TestRoot)
$ErrorActionPreference = 'Stop'
if (Test-Path $TestRoot) { throw 'Use a new lifecycle test directory.' }
New-Item -ItemType Directory $TestRoot | Out-Null
$destination = Join-Path $TestRoot 'Application'
function Install-Preview([string]$LogName) {
    $process = Start-Process $Installer -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART','/TASKS=desktopicon',"/DIR=`"$destination`"", "/LOG=`"$TestRoot/$LogName`"") -PassThru
    if (!$process.WaitForExit(180000)) { $process.Kill(); throw 'Setup timed out.' }
    if ($process.ExitCode -ne 0) { throw "Setup failed: $($process.ExitCode)" }
}
Install-Preview 'install.log'
$app = Join-Path $destination 'LemmingsStudio Windows Preview.exe'
if (!(Test-Path $app)) { throw 'Application executable missing after install.' }
$desktop = Join-Path ([Environment]::GetFolderPath('Desktop')) 'LemmingsStudio Python Preview.lnk'
$start = Join-Path ([Environment]::GetFolderPath('Programs')) 'LemmingsStudio Python Preview/LemmingsStudio Python Preview.lnk'
if (!(Test-Path $desktop) -or !(Test-Path $start)) { throw 'Shortcut missing.' }
$shortcut = (New-Object -ComObject WScript.Shell).CreateShortcut($desktop)
if ($shortcut.TargetPath -ne $app) { throw 'Shortcut target is incorrect.' }
$registry = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\{DA561E1D-BE12-4C74-92A4-5671D020A391}_is1'
if (!(Test-Path $registry)) { throw 'Per-user uninstall registration missing.' }
$report = Join-Path $TestRoot 'installed-smoke.json'
$process = Start-Process $app -ArgumentList @('--self-test-report',"`"$report`"") -PassThru
if (!$process.WaitForExit(180000)) { $process.Kill(); throw 'Installed app test timed out.' }
if ($process.ExitCode -ne 0) { throw 'Installed app failed its checks.' }
if ((Get-Content $report -Raw | ConvertFrom-Json).status -ne 'passed') { throw 'Installed app did not report success.' }
$userFile = Join-Path $destination 'User project - preserve.lemmingspy'
Set-Content $userFile 'User-owned sentinel; setup must not remove this file.' -Encoding utf8
$hash = (Get-FileHash $userFile).Hash
Install-Preview 'reinstall.log'
if ((Get-FileHash $userFile).Hash -ne $hash) { throw 'Reinstall changed user data.' }
$uninstaller = Join-Path $destination 'unins000.exe'
$process = Start-Process $uninstaller -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART',"/LOG=`"$TestRoot/uninstall.log`"") -PassThru
if (!$process.WaitForExit(180000)) { $process.Kill(); throw 'Uninstall timed out.' }
if ($process.ExitCode -ne 0) { throw "Uninstall failed: $($process.ExitCode)" }
for ($attempt=0; $attempt -lt 20 -and (Test-Path $app); $attempt++) { Start-Sleep -Milliseconds 500 }
if (Test-Path $app) { throw 'Executable remains after uninstall.' }
if ((Test-Path $desktop) -or (Test-Path $start) -or (Test-Path $registry)) { throw 'Shortcuts or uninstall registration remain.' }
if (!(Test-Path $userFile) -or (Get-FileHash $userFile).Hash -ne $hash) { throw 'Uninstall deleted user data.' }
'PASS: install, shortcuts, registration, installed app, reinstall and uninstall preservation.'
