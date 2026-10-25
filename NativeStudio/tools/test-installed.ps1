param([Parameter(Mandatory=$true)][string]$ArtifactRoot, [switch]$Launch)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path $ArtifactRoot).Path
$logRoot = Join-Path $root 'VM-Test-Results'
New-Item -ItemType Directory -Force $logRoot | Out-Null
Start-Transcript -Path (Join-Path $logRoot 'checks.log') -Force
try {
  Write-Output "Architecture: $env:PROCESSOR_ARCHITECTURE"
  Write-Output "Windows: $([Environment]::OSVersion.VersionString)"
  $checks = @(Get-ChildItem $root -Recurse -File -Filter StudioChecks.exe)
  if ($checks.Count -ne 1) { throw 'Expected exactly one StudioChecks.exe in extracted artifacts.' }
  & $checks[0].FullName
  if ($LASTEXITCODE -ne 0) { throw 'Native session/audio checks failed.' }
  $plugins = @(Get-ChildItem $root -Recurse -Directory -Filter '*.vst3')
  if ($plugins.Count -lt 3) { throw 'Expected at least the three native plugin products.' }
  foreach ($plugin in $plugins) {
    & $checks[0].FullName $plugin.FullName
    if ($LASTEXITCODE -ne 0) { throw "Plugin wrapper check failed: $($plugin.Name)" }
  }
  $voxChecks = @(Get-ChildItem $root -Recurse -File -Filter VoxGardenCheck.exe)
  foreach ($check in $voxChecks) {
    & $check.FullName
    if ($LASTEXITCODE -ne 0) { throw 'VoxGarden DSP/state checks failed.' }
  }
  if ($Launch) {
    $application = @(Get-ChildItem $root -Recurse -File -Filter 'LemmingsStudio Native Preview.exe')
    if ($application.Count -ne 1) { throw 'Expected exactly one native application.' }
    Start-Process $application[0].FullName
  }
} finally { Stop-Transcript }
