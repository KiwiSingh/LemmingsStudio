param(
    [Parameter(Mandatory=$true)][string]$BuildRoot,
    [Parameter(Mandatory=$true)][string]$SourceRoot,
    [Parameter(Mandatory=$true)][string]$StageRoot,
    [Parameter(Mandatory=$true)][string]$OutputRoot,
    [Parameter(Mandatory=$true)][string]$SourceRun,
    [string]$BuildVersion = '0.1.0.0',
    [string]$Iscc = "${env:ProgramFiles(x86)}/Inno Setup 6/ISCC.exe"
)
$ErrorActionPreference = 'Stop'
if ($BuildVersion -notmatch '^\d+\.\d+\.\d+\.\d+$') { throw 'Use a four-part numeric version.' }
if ($SourceRun -notmatch '^\d+$') { throw 'SourceRun must be a GitHub Actions run number.' }
if (Test-Path $StageRoot) { throw 'Use a new staging directory; existing files will not be removed.' }
if (!(Test-Path $Iscc -PathType Leaf)) { throw 'Install Inno Setup 6.5.4 or pass -Iscc.' }
$BuildRoot = (Resolve-Path $BuildRoot).Path
$SourceRoot = (Resolve-Path $SourceRoot).Path
$StageRoot = [IO.Path]::GetFullPath($StageRoot)
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
$sourceCommit = (& git -C $SourceRoot rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0) { throw 'SourceRoot must be the exact source checkout for the binaries.' }
$juceRevision = 'f72bad64d29715216226685810c5196bd0d79d77'
$cmake = Get-Content (Join-Path $SourceRoot 'NativeStudio/CMakeLists.txt') -Raw
if (!$cmake.Contains("GIT_TAG $juceRevision")) { throw 'Update source packaging for the JUCE revision used by this build.' }
foreach ($folder in @('App','Diagnostics','Devices','Licenses','Source')) {
    New-Item -ItemType Directory -Path (Join-Path $StageRoot $folder) -Force | Out-Null
}
New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
function Copy-RequiredFile([string]$Relative, [string]$Destination) {
    $inputFile = Join-Path $BuildRoot $Relative
    if (!(Test-Path $inputFile -PathType Leaf)) { throw "Required build output missing: $Relative" }
    Copy-Item -LiteralPath $inputFile -Destination $Destination
}
Copy-RequiredFile 'LemmingsNative_artefacts/Release/LemmingsStudio Native Preview.exe' (Join-Path $StageRoot 'App')
Copy-RequiredFile 'StudioChecks_artefacts/Release/StudioChecks.exe' (Join-Path $StageRoot 'Diagnostics')
foreach ($device in @(
    @('LemmingAmp','Lemming Amp'),
    @('LemmingGuitar','LemmingGuitar Preview'),
    @('LemmingRockDrums','LemmingRockDrums Preview')
)) {
    $target = Join-Path $StageRoot "Devices/$($device[0])"
    New-Item -ItemType Directory -Path $target | Out-Null
    Copy-RequiredFile "$($device[0])_artefacts/Release/Standalone/$($device[1]).exe" $target
    $bundle = Join-Path $BuildRoot "$($device[0])_artefacts/Release/VST3/$($device[1]).vst3"
    if (!(Test-Path (Join-Path $bundle "Contents/x86_64-win/$($device[1]).vst3"))) { throw "VST3 binary missing: $bundle" }
    Copy-Item -LiteralPath $bundle -Destination $target -Recurse
}
# Reject accidental 32-bit or ARM payloads before compiling the wizard.
foreach ($binary in Get-ChildItem $StageRoot -Recurse -File | Where-Object { $_.Extension -in '.exe','.vst3' }) {
    $bytes = [IO.File]::ReadAllBytes($binary.FullName)
    if ($bytes.Length -lt 64 -or [BitConverter]::ToUInt16($bytes,0) -ne 0x5a4d) { throw "Invalid PE: $binary" }
    $offset = [BitConverter]::ToInt32($bytes,60)
    if ($offset -lt 0 -or $offset + 6 -gt $bytes.Length -or [BitConverter]::ToUInt32($bytes,$offset) -ne 0x4550 -or [BitConverter]::ToUInt16($bytes,$offset+4) -ne 0x8664) { throw "Expected an AMD64 PE: $binary" }
}
Copy-Item (Join-Path $SourceRoot 'LICENSE') (Join-Path $StageRoot 'Licenses/LemmingsStudio-GPL-3.0.txt')
Copy-Item (Join-Path $SourceRoot 'THIRD_PARTY_NOTICES.md') (Join-Path $StageRoot 'Licenses')
Copy-Item (Join-Path $PSScriptRoot 'PREVIEW.txt') $StageRoot
& git -C $SourceRoot archive --format=zip "--output=$StageRoot/Source/LemmingsStudio-Source.zip" HEAD NativeStudio LICENSE THIRD_PARTY_NOTICES.md Docs/Recovery
if ($LASTEXITCODE -ne 0) { throw 'Could not archive the matching native sources.' }
Invoke-WebRequest "https://codeload.github.com/juce-framework/JUCE/zip/$juceRevision" -OutFile (Join-Path $StageRoot 'Source/JUCE-Source.zip')
Invoke-WebRequest 'https://www.gnu.org/licenses/agpl-3.0.txt' -OutFile (Join-Path $StageRoot 'Licenses/JUCE-AGPL-3.0.txt')
@"
Native source revision: $sourceCommit
JUCE source revision: $juceRevision
Build artifact run: https://github.com/KiwiSingh/LemmingsStudio/actions/runs/$SourceRun

Extract LemmingsStudio-Source.zip and JUCE-Source.zip into separate folders.
On Windows install CMake 3.24+, Visual Studio 2022 Desktop C++ tools and Python 3.
From the extracted native source folder, with the path to extracted JUCE substituted:
cmake -S NativeStudio -B native-build -A x64 -DLEMMINGS_JUCE_DIR=C:/path/to/JUCE-$juceRevision
cmake --build native-build --config Release --parallel 2
ctest --test-dir native-build -C Release --output-on-failure
python -m unittest discover -s NativeStudio/tests -p test_*.py

LemmingsStudio's source notices are GPLv3; the JUCE modules are used under their
AGPLv3 option. Preserve both notices and the combined-work obligations. JUCE's
own LICENSE.md and embedded dependency notices are in JUCE-Source.zip.
No commercial JUCE license is claimed by this preview package.
"@ | Set-Content (Join-Path $StageRoot 'Source/README.txt') -Encoding utf8
$files = @(Get-ChildItem $StageRoot -Recurse -File | ForEach-Object {
    @{ path = [IO.Path]::GetRelativePath($StageRoot,$_.FullName).Replace('\','/'); sha256 = (Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant() }
})
@{ version=$BuildVersion; sourceCommit=$sourceCommit; sourceRun=$SourceRun; juceRevision=$juceRevision; files=$files } |
    ConvertTo-Json -Depth 5 | Set-Content (Join-Path $StageRoot 'build-manifest.json') -Encoding utf8
& $Iscc "/DPayloadDir=$StageRoot" "/DOutputDir=$OutputRoot" "/DBuildVersion=$BuildVersion" (Join-Path $PSScriptRoot 'LemmingsStudio.iss')
if ($LASTEXITCODE -ne 0) { throw 'Inno Setup compilation failed.' }
Get-ChildItem $OutputRoot -Filter '*.exe' | Get-FileHash -Algorithm SHA256 |
    ForEach-Object { "$($_.Hash.ToLowerInvariant())  $([IO.Path]::GetFileName($_.Path))" } |
    Set-Content (Join-Path $OutputRoot 'SHA256SUMS.txt') -Encoding ascii
