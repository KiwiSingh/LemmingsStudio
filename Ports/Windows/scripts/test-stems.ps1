param(
    [ValidateSet("cpu", "directml", "cuda", "qnn", "openvino")]
    [string]$Backend = "directml",
    [ValidateSet("win-x64", "win-arm64", "auto")]
    [string]$Runtime = "auto",
    [Parameter(Mandatory=$true)]
    [string]$InputPath
)

$ErrorActionPreference = "Stop"
$venvPython = Join-Path $env:LOCALAPPDATA "LemmingsStudio\Backends\$Backend\Scripts\python.exe"
if (-not (Test-Path $venvPython)) {
    throw "Backend '$Backend' is not installed yet. Run Install / Repair Backend first."
}
if (-not (Test-Path $InputPath)) { throw "Input file not found: $InputPath" }

$backendDir = Join-Path (Split-Path $PSScriptRoot -Parent) "backend"
$runner = Join-Path $backendDir "stem_runner.py"
if (-not (Test-Path $runner)) { throw "stem_runner.py not found at $runner" }

$outDir = Join-Path $env:TEMP ("LemmingsStudioStemTest-" + [guid]::NewGuid().ToString())
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
Write-Host "Backend flavor: $Backend"
Write-Host "Runtime: $Runtime"
Write-Host "Input: $InputPath"
Write-Host "Output: $outDir"
Write-Host "Running accelerator-aware stem split..."

# The runner picks CUDA/DirectML/QNN/OpenVINO/CPU based on this flavor + what the
# machine actually exposes, and prints the provider it engaged.
& $venvPython $runner --flavor $Backend --input $InputPath --output $outDir

Write-Host "Done. Output files:"
Get-ChildItem -Path $outDir -Recurse -File | ForEach-Object { Write-Host $_.FullName }
