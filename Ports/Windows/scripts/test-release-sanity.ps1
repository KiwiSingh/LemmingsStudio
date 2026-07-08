param(
    [string]$PublishDir = "",
    [switch]$RequireNativeVst3Host
)
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($PublishDir)) {
    $PublishDir = Join-Path $PSScriptRoot '..\publish'
}
$PublishDir = [IO.Path]::GetFullPath($PublishDir)
Write-Host "LemmingsStudio Windows release sanity check"
Write-Host "PublishDir: $PublishDir"
if (!(Test-Path $PublishDir)) { throw "Publish directory not found: $PublishDir" }

$required = @('LemmingsStudio.exe', 'LemmingsStudio.dll', 'LemmingsStudio.runtimeconfig.json')
foreach ($name in $required) {
    $p = Join-Path $PublishDir $name
    if (!(Test-Path $p)) { throw "Missing required publish artifact: $name" }
    Write-Host "PASS $name"
}

$host = Join-Path $PublishDir 'LemmingsVst3Host.exe'
if ($RequireNativeVst3Host -and !(Test-Path $host)) { throw 'Native VST3 host required but missing.' }
if (Test-Path $host) { Write-Host 'PASS LemmingsVst3Host.exe' } else { Write-Warning 'Native VST3 host not present.' }

$unicodeRoot = Join-Path $env:TEMP 'LemmingsStudio_नमस्ते_音楽'
$longLeaf = ('L' * 90)
$testDir = Join-Path $unicodeRoot $longLeaf
New-Item -ItemType Directory -Force -Path $testDir | Out-Null
$testFile = Join-Path $testDir 'संगीत_é.txt'
Set-Content -LiteralPath $testFile -Value 'ok' -Encoding UTF8
if ((Get-Content -LiteralPath $testFile -Raw).Trim() -ne 'ok') { throw 'Unicode/long-path round trip failed.' }
Remove-Item -LiteralPath $unicodeRoot -Recurse -Force
Write-Host 'PASS Unicode/long-path filesystem smoke test'

Write-Host 'Release sanity checks passed.'
