param([string]$Destination = "$PSScriptRoot/../../../../VoxGarden-native")
$ErrorActionPreference = 'Stop'
function Run-Git { & git @args; if ($LASTEXITCODE -ne 0) { throw "git failed: $args" } }
$revision = '8ab73f3a123a92655f5d340183a91f9a01848152'
if (Test-Path $Destination) { throw 'Use a new destination so an existing VoxGarden checkout is not modified.' }
Run-Git clone https://github.com/KiwiSingh/VoxGarden.git $Destination
Run-Git -C $Destination checkout --detach $revision
Run-Git -C $Destination apply "$PSScriptRoot/../patches/voxgarden-windows-dsp.patch"
$dependencies = @(
 @('JUCE','https://github.com/juce-framework/JUCE.git','f72bad64d29715216226685810c5196bd0d79d77'),
 @('linear','https://github.com/Signalsmith-Audio/linear.git','7bb1c8f36794d6980080ce817c91f8da8fe56a66'),
 @('signalsmith-stretch','https://github.com/Signalsmith-Audio/signalsmith-stretch.git','88061fd4eda56a2353c5d65c74aa3f4ccf76f9da'))
foreach ($dep in $dependencies) {
 $path = Join-Path $Destination "ThirdParty/$($dep[0])"
 Run-Git clone --no-checkout $dep[1] $path
 Run-Git -C $path checkout --detach $dep[2]
}
& cmake -S $Destination -B "$Destination/build" -A x64
if ($LASTEXITCODE -ne 0) { throw 'VoxGarden configure failed' }
& cmake --build "$Destination/build" --config Release --target VoxGarden_VST3 VoxGarden_Standalone VoxGardenCheck --parallel 2
if ($LASTEXITCODE -ne 0) { throw 'VoxGarden build failed' }
& ctest --test-dir "$Destination/build" -C Release --output-on-failure
if ($LASTEXITCODE -ne 0) { throw 'VoxGarden checks failed' }
