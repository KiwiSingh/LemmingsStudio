param(
    [ValidateSet("cpu", "directml", "cuda", "qnn", "openvino")]
    [string]$Backend = "directml",
    [ValidateSet("win-x64", "win-arm64")]
    [string]$Runtime = "win-x64",
    [switch]$BundleModels
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $Root

$Project = Join-Path $Root "src\LemmingsStudio.Windows\LemmingsStudio.Windows.csproj"
$Installer = Join-Path $Root "installer\LemmingsStudio.iss"

$projectText = Get-Content -Raw $Project
$installerText = Get-Content -Raw $Installer
if ($projectText -notmatch '<Version>2\.0\.0</Version>') { throw "Windows project version is not 2.0.0" }
if ($projectText -notmatch '<AssemblyVersion>2\.0\.0\.0</AssemblyVersion>') { throw "Windows assembly version is not 2.0.0.0" }
if ($installerText -notmatch '#define AppVersion "2\.0\.0"') { throw "Installer version is not 2.0.0" }

& (Join-Path $Root "build-windows.ps1") -Backend $Backend -Runtime $Runtime -BundleModels:$BundleModels -Version "2.0.0"
if ($LASTEXITCODE -ne 0) { throw "Windows build failed with exit code $LASTEXITCODE" }

$sanity = Join-Path $Root "scripts\test-release-sanity.ps1"
if (Test-Path $sanity) {
    & $sanity
    if ($LASTEXITCODE -ne 0) { throw "Release sanity test failed with exit code $LASTEXITCODE" }
}

$out = Join-Path $Root "release-dist"
New-Item -ItemType Directory -Force -Path $out | Out-Null
$artifacts = Get-ChildItem -Path $Root -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Extension -in @('.exe', '.msix', '.zip') -and $_.Name -match 'LemmingsStudio' } |
    Sort-Object LastWriteTime -Descending

if (-not $artifacts) { throw "No Windows release artifact was found after the build." }
$hashLines = foreach ($artifact in $artifacts) {
    $hash = Get-FileHash -Algorithm SHA256 -LiteralPath $artifact.FullName
    "{0}  {1}" -f $hash.Hash.ToLowerInvariant(), $artifact.FullName
}
$hashFile = Join-Path $out "LemmingsStudio-Windows-v2.0-$Runtime-$Backend.sha256.txt"
$hashLines | Set-Content -Encoding UTF8 $hashFile
Write-Host "Windows release verification passed. Hash manifest: $hashFile" -ForegroundColor Green
