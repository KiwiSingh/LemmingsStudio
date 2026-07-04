param(
  [string]$SourceVideo = "",
  [string]$AssetsDir = "",
  [int[]]$RefreshRates = @(60,75,90,120,144,165,240),
  [switch]$SkipIfExisting
)
$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($AssetsDir)) {
  $AssetsDir = Join-Path $PSScriptRoot "..\src\LemmingsStudio.Windows\Assets"
}
$AssetsDir = [IO.Path]::GetFullPath($AssetsDir)
if ([string]::IsNullOrWhiteSpace($SourceVideo)) {
  $SourceVideo = Join-Path $AssetsDir "MagmaVancePreSplash.mp4"
}
if (!(Test-Path $SourceVideo)) {
  Write-Warning "MagmaVance pre-splash source video not found: $SourceVideo"
  exit 0
}
$ffmpeg = Get-Command ffmpeg -ErrorAction SilentlyContinue
if (-not $ffmpeg) {
  Write-Warning "ffmpeg not found; keeping existing pre-splash frames and falling back to 60 fps if needed."
  exit 0
}
foreach ($fps in $RefreshRates) {
  if ($fps -lt 24) { continue }
  $outDir = Join-Path $AssetsDir ("PreSplashFrames_{0}" -f $fps)
  if ($SkipIfExisting -and (Test-Path $outDir) -and ((Get-ChildItem $outDir -Filter 'frame_*.jpg' -ErrorAction SilentlyContinue).Count -gt 0)) {
    continue
  }
  New-Item -ItemType Directory -Force $outDir | Out-Null
  Remove-Item (Join-Path $outDir 'frame_*.jpg') -ErrorAction SilentlyContinue
  Write-Host "Generating MagmaVance pre-splash frames at $fps fps → $outDir"
  & $ffmpeg.Source -y -i $SourceVideo -vf "fps=$fps,scale=360:640:flags=lanczos" -q:v 5 (Join-Path $outDir 'frame_%04d.jpg') | Out-Host
}
