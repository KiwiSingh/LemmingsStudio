param(
    [ValidateSet("cpu", "directml", "cuda", "qnn", "openvino")]
    [string]$Backend = "directml",
    [ValidateSet("win-x64", "win-arm64")]
    [string]$Runtime = "win-x64",
    [string]$Version = "1.1.0",
    [string]$Configuration = "Release",
    [switch]$PreloadModels,
    [switch]$SkipInstaller,
    [string]$InnoSetupPath = "",
    [string]$OutputDir = "",
    [switch]$SkipFfmpeg,
    [string]$FfmpegSource = "",
    [string[]]$ModelNames = @("htdemucs", "htdemucs_ft", "htdemucs_6s"),
    [switch]$SkipNativeVst3Host,
    [switch]$RequireNativeVst3Host,
    [switch]$SkipNativeVst3ToolchainBootstrap,
    [string]$NativeVst3HostPath = ""
)

$ErrorActionPreference = "Stop"

function Step($Text) { Write-Host "`n==> $Text" -ForegroundColor Cyan }
function Warn($Text) { Write-Host "WARNING: $Text" -ForegroundColor Yellow }

function Expand-ZipWithShellFallback([string]$ZipPath, [string]$Destination) {
    Remove-Item -Recurse -Force $Destination -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    try {
        Expand-Archive -LiteralPath $ZipPath -DestinationPath $Destination -Force
    } catch {
        throw "Could not extract $ZipPath. Error: $($_.Exception.Message)"
    }
}

function Find-FfmpegInFolder([string]$Folder) {
    if (-not (Test-Path $Folder)) { return $null }
    $hit = Get-ChildItem -Path $Folder -Filter ffmpeg.exe -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($hit) { return $hit.FullName }
    return $null
}


function Try-WingetInstall([string]$Id, [string]$Name, [string[]]$ExtraArgs = @()) {
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $winget) { Warn "winget was not found; cannot auto-install $Name."; return $false }
    Step "Installing/verifying $Name via winget"
    $args = @("install", "--id", $Id, "--exact", "--source", "winget", "--accept-package-agreements", "--accept-source-agreements") + $ExtraArgs
    & $winget.Source @args
    if ($LASTEXITCODE -eq 0) { return $true }
    Warn "winget install for $Name returned exit code $LASTEXITCODE. Continuing with whatever is already installed."
    return $false
}

function Refresh-PathFromMachineAndUserEnvironment() {
    $machine = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $user = [Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = (($machine, $user, $env:Path) -join ";")
}

function Find-VisualStudioCMakeGenerator() {
    $vswhereCandidates = @(
        "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe",
        "$env:ProgramFiles\Microsoft Visual Studio\Installer\vswhere.exe"
    )
    foreach ($vswhere in $vswhereCandidates) {
        if (-not (Test-Path $vswhere)) { continue }
        $install = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2>$null
        if ($LASTEXITCODE -eq 0 -and $install) { return (($install | Select-Object -First 1).ToString().Trim()) }
    }
    return $null
}

function Ensure-NativeVst3Toolchain([switch]$SkipBootstrap, [switch]$RequireHost) {
    if ($SkipBootstrap) { return }

    $needsRefresh = $false
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Warn "Git was not found; JUCE FetchContent needs it unless LEMMINGS_JUCE_DIR points at a local JUCE checkout."
        if (Try-WingetInstall -Id "Git.Git" -Name "Git") { $needsRefresh = $true }
    }
    if (-not (Get-Command cmake -ErrorAction SilentlyContinue)) {
        Warn "CMake was not found; native VST3 host cannot compile without it."
        if (Try-WingetInstall -Id "Kitware.CMake" -Name "CMake" -ExtraArgs @("--scope", "machine")) { $needsRefresh = $true }
    }
    if (-not (Find-VisualStudioCMakeGenerator)) {
        Warn "Visual Studio C++ Build Tools were not found; native VST3 host cannot compile without MSVC v143/C++ desktop tools."
        $override = "--add Microsoft.VisualStudio.Workload.VCTools --add Microsoft.VisualStudio.Component.VC.CMake.Project --add Microsoft.VisualStudio.Component.Windows11SDK.26100 --includeRecommended --quiet --wait --norestart"
        if (Try-WingetInstall -Id "Microsoft.VisualStudio.2022.BuildTools" -Name "Visual Studio 2022 Build Tools" -ExtraArgs @("--override", $override)) { $needsRefresh = $true }
    }
    if ($needsRefresh) { Refresh-PathFromMachineAndUserEnvironment }

    if ($RequireHost) {
        if (-not (Get-Command git -ErrorAction SilentlyContinue) -and -not $env:LEMMINGS_JUCE_DIR) { throw "Git is still missing after bootstrap. Install Git or set LEMMINGS_JUCE_DIR." }
        if (-not (Get-Command cmake -ErrorAction SilentlyContinue)) { throw "CMake is still missing after bootstrap. Install CMake or rerun in a fresh PowerShell window." }
        if (-not (Find-VisualStudioCMakeGenerator)) { throw "Visual Studio C++ Build Tools are still missing after bootstrap. Install Desktop development with C++ and CMake tools." }
    }
}

function Test-NativeVst3Host([string]$HostPath) {
    if (-not (Test-Path $HostPath)) { return $false }
    try {
        $psi = [Diagnostics.ProcessStartInfo]::new()
        $psi.FileName = $HostPath
        $psi.WorkingDirectory = Split-Path -Parent $HostPath
        $psi.UseShellExecute = $false
        $psi.RedirectStandardInput = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.CreateNoWindow = $true
        $p = [Diagnostics.Process]::Start($psi)
        if (-not $p) { return $false }
        $ready = $p.StandardOutput.ReadLine()
        $p.StandardInput.WriteLine('{"op":"ping","id":"smoke"}')
        $p.StandardInput.Flush()
        $pong = $p.StandardOutput.ReadLine()
        try { $p.StandardInput.WriteLine('{"op":"quit"}'); $p.StandardInput.Flush() } catch {}
        if (-not $p.WaitForExit(3000)) { try { $p.Kill() } catch {} }
        return (($ready -match '"ready"') -and ($pong -match '"pong"'))
    } catch {
        Warn "Native VST3 host smoke test failed: $($_.Exception.Message)"
        return $false
    }
}


function Build-NativeVst3Host([string]$Runtime, [string]$WinRoot, [string]$OutputRoot, [string]$ExplicitHost, [switch]$SkipBuild, [switch]$RequireHost, [switch]$SkipBootstrap) {
    $hostName = "LemmingsVst3Host.exe"
    if ($ExplicitHost -and (Test-Path $ExplicitHost)) {
        $resolvedExplicit = (Resolve-Path $ExplicitHost).Path
        if ($RequireHost -and -not (Test-NativeVst3Host $resolvedExplicit)) { throw "Explicit native VST3 host did not pass the JSONL ping smoke test: $resolvedExplicit" }
        return $resolvedExplicit
    }
    if ($SkipBuild) { return $null }

    $nativeRoot = Join-Path $WinRoot "native\LemmingsVst3Host"
    $cmakeLists = Join-Path $nativeRoot "CMakeLists.txt"
    if (-not (Test-Path $cmakeLists)) {
        $msg = "Native VST3 host source was not found at $nativeRoot"
        if ($RequireHost) { throw $msg } else { Warn $msg; return $null }
    }
    Ensure-NativeVst3Toolchain -SkipBootstrap:$SkipBootstrap -RequireHost:$RequireHost

    if (-not (Get-Command cmake -ErrorAction SilentlyContinue)) {
        $msg = "CMake was not found. Install Visual Studio 2022 Build Tools with Desktop C++ and CMake, or pass -NativeVst3HostPath."
        if ($RequireHost) { throw $msg } else { Warn $msg; return $null }
    }

    $arch = if ($Runtime -eq "win-arm64") { "ARM64" } else { "x64" }
    $buildDir = Join-Path $OutputRoot "native-vst3-host-$Runtime"
    $installDir = Join-Path $OutputRoot "native-vst3-host-bin-$Runtime"
    New-Item -ItemType Directory -Force -Path $buildDir | Out-Null
    New-Item -ItemType Directory -Force -Path $installDir | Out-Null

    Step "Building native JUCE VST3 host helper ($Runtime / $arch)"
    try {
        & cmake -S $nativeRoot -B $buildDir -G "Visual Studio 17 2022" -A $arch -DCMAKE_BUILD_TYPE=Release
        if ($LASTEXITCODE -ne 0) { throw "CMake configure failed with exit code $LASTEXITCODE" }
        & cmake --build $buildDir --config Release --target LemmingsVst3Host --parallel
        if ($LASTEXITCODE -ne 0) { throw "CMake build failed with exit code $LASTEXITCODE" }
        $built = Get-ChildItem -Path $buildDir -Filter $hostName -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $built) { throw "Built helper was not found under $buildDir" }
        $dest = Join-Path $installDir $hostName
        Copy-Item -Force $built.FullName $dest
        if (-not (Test-NativeVst3Host $dest)) { throw "Built helper did not pass the JSONL ping smoke test." }
        return $dest
    } catch {
        $msg = "Native VST3 helper build failed: $($_.Exception.Message)"
        if ($RequireHost) { throw $msg } else { Warn $msg; return $null }
    }
}

function Resolve-VCRedistX64Source([string]$WinRoot) {
    $candidates = @()
    if ($env:LEMMINGS_VCREDIST_X64) { $candidates += $env:LEMMINGS_VCREDIST_X64 }
    $candidates += (Join-Path $WinRoot "redist\vc_redist.x64.exe")
    $candidates += (Join-Path $WinRoot "vc_redist.x64.exe")
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path $candidate)) { return (Resolve-Path $candidate).Path }
    }

    $cacheDir = Join-Path $WinRoot "redist"
    $cached = Join-Path $cacheDir "vc_redist.x64.exe"
    if (Test-Path $cached) { return $cached }

    Step "Downloading Microsoft Visual C++ Redistributable x64 for bundling"
    New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null
    try {
        Invoke-WebRequest -Uri "https://aka.ms/vs/17/release/vc_redist.x64.exe" -OutFile $cached -UseBasicParsing -TimeoutSec 300
        return $cached
    } catch {
        Warn "Could not download Visual C++ Redistributable x64: $($_.Exception.Message). The installer will still build, but PyTorch/Demucs users may need to install it manually."
        return $null
    }
}

function Resolve-FfmpegSource([string]$Runtime, [string]$WinRoot, [string]$ExplicitSource, [switch]$SkipDownload) {
    $candidates = @()
    if ($ExplicitSource) { $candidates += $ExplicitSource }
    if ($env:LEMMINGS_FFMPEG_SRC) { $candidates += $env:LEMMINGS_FFMPEG_SRC }
    $candidates += (Join-Path $WinRoot "ffmpeg\ffmpeg.exe")
    $candidates += (Join-Path $WinRoot "ffmpeg\$Runtime\ffmpeg.exe")

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path $candidate)) { return (Resolve-Path $candidate).Path }
    }

    $where = Get-Command ffmpeg -ErrorAction SilentlyContinue
    if ($where -and $where.Source -and (Test-Path $where.Source)) { return $where.Source }

    if ($SkipDownload) { return $null }

    $cacheDir = Join-Path $WinRoot "ffmpeg\$Runtime"
    $cachedExe = Join-Path $cacheDir "ffmpeg.exe"
    if (Test-Path $cachedExe) { return $cachedExe }

    Step "Downloading ffmpeg for bundling"
    New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null

    $archPatterns = if ($Runtime -eq "win-arm64") {
        @("winarm64", "windows-arm64", "win-arm64", "arm64")
    } else {
        @("win64", "windows-x64", "win-x64", "x64")
    }

    $downloadUrl = $null
    try {
        $release = Invoke-RestMethod -Uri "https://api.github.com/repos/BtbN/FFmpeg-Builds/releases/latest" -Headers @{ "User-Agent" = "LemmingsStudio-Windows-Build" } -TimeoutSec 30
        $asset = $release.assets | Where-Object {
            $name = $_.name.ToLowerInvariant()
            ($archPatterns | Where-Object { $name.Contains($_) }) -and
            $name.Contains("gpl") -and
            -not $name.Contains("shared") -and
            ($name.EndsWith(".zip") -or $name.EndsWith(".7z"))
        } | Select-Object -First 1
        if (-not $asset) {
            $asset = $release.assets | Where-Object {
                $name = $_.name.ToLowerInvariant()
                ($archPatterns | Where-Object { $name.Contains($_) }) -and
                ($name.EndsWith(".zip") -or $name.EndsWith(".7z"))
            } | Select-Object -First 1
        }
        if ($asset) { $downloadUrl = $asset.browser_download_url }
    } catch {
        Warn "Could not query BtbN ffmpeg releases: $($_.Exception.Message)"
    }

    if (-not $downloadUrl -and $Runtime -eq "win-x64") {
        $downloadUrl = "https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip"
    }

    if (-not $downloadUrl) {
        Warn "Could not find a downloadable ffmpeg archive for $Runtime. Set LEMMINGS_FFMPEG_SRC or pass -FfmpegSource to bundle manually."
        return $null
    }

    $archiveExt = if ($downloadUrl.ToLowerInvariant().EndsWith(".7z")) { ".7z" } else { ".zip" }
    $archivePath = Join-Path $cacheDir ("ffmpeg-download" + $archiveExt)
    Write-Host "Downloading ffmpeg: $downloadUrl"
    Invoke-WebRequest -Uri $downloadUrl -OutFile $archivePath -UseBasicParsing -TimeoutSec 300

    $extractDir = Join-Path $cacheDir "extract"
    if ($archiveExt -eq ".zip") {
        Expand-ZipWithShellFallback $archivePath $extractDir
    } else {
        $sevenZip = Get-Command 7z -ErrorAction SilentlyContinue
        if (-not $sevenZip) {
            Warn "Downloaded a .7z ffmpeg archive, but 7z was not found. Install 7-Zip or set LEMMINGS_FFMPEG_SRC manually."
            return $null
        }
        Remove-Item -Recurse -Force $extractDir -ErrorAction SilentlyContinue
        New-Item -ItemType Directory -Force -Path $extractDir | Out-Null
        & $sevenZip.Source x $archivePath "-o$extractDir" -y | Out-Null
    }

    $downloadedExe = Find-FfmpegInFolder $extractDir
    if (-not $downloadedExe) {
        Warn "ffmpeg.exe was not found inside the downloaded archive."
        return $null
    }
    Copy-Item -Force $downloadedExe $cachedExe
    Write-Host "Cached ffmpeg at $cachedExe"
    return $cachedExe
}

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$winRoot = Join-Path $repoRoot "Ports\Windows"
$project = Join-Path $winRoot "src\LemmingsStudio.Windows\LemmingsStudio.Windows.csproj"
if (-not $OutputDir) { $OutputDir = Join-Path $winRoot "artifacts" }
$publishDir = Join-Path $OutputDir "publish-$Runtime-$Backend"
$installerOut = Join-Path $OutputDir "installer"
$stagingDocs = Join-Path $publishDir "Docs"
$modelCacheRoot = Join-Path $publishDir "model-cache"
$torchModelCache = Join-Path $modelCacheRoot "torch"
$canBundleDemucsModels = -not ($Runtime -eq "win-arm64" -and -not $env:LEMMINGS_EXPERIMENTAL_WINARM64_STEMS)

Step "Checking prerequisites"
if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
    throw "dotnet was not found. Install .NET 8 SDK from https://dotnet.microsoft.com/download, then open a new PowerShell window."
}
& dotnet --info

Step "Generating dynamic-refresh MagmaVance pre-splash frame variants"
$preSplashScript = Join-Path $winRoot "scripts\generate-presplash-variants.ps1"
if (Test-Path $preSplashScript) {
    try {
        & $preSplashScript -SkipIfExisting
    } catch {
        Warn "Pre-splash frame variant generation failed: $($_.Exception.Message). Existing frames / 60 fps fallback will be used."
    }
} else {
    Warn "Pre-splash frame variant script not found; existing frames / 60 fps fallback will be used."
}

Step "Publishing Windows app ($Runtime / $Backend)"
Remove-Item -Recurse -Force $publishDir -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $publishDir | Out-Null
& dotnet publish $project -c $Configuration -r $Runtime --self-contained true -o $publishDir /p:Version=$Version /p:PublishSingleFile=false

$nativeHost = Build-NativeVst3Host -Runtime $Runtime -WinRoot $winRoot -OutputRoot $OutputDir -ExplicitHost $NativeVst3HostPath -SkipBuild:$SkipNativeVst3Host -RequireHost:$RequireNativeVst3Host -SkipBootstrap:$SkipNativeVst3ToolchainBootstrap
if ($nativeHost -and (Test-Path $nativeHost)) {
    Copy-Item -Force $nativeHost (Join-Path $publishDir "LemmingsVst3Host.exe")
    Write-Host "Bundled native VST3 helper: $nativeHost"
} else {
    Warn "No native VST3 helper was bundled. VST3 discovery/editor bridge UI remains available, but in-process VST3 audio/MIDI hosting will not be active until LemmingsVst3Host.exe is supplied."
}

Step "Copying Windows helper scripts and docs"
Copy-Item -Recurse -Force (Join-Path $winRoot "scripts") (Join-Path $publishDir "scripts")
Copy-Item -Recurse -Force (Join-Path $winRoot "backend") (Join-Path $publishDir "backend")

# Bundle the VC++ x64 runtime needed by PyTorch's Windows x64 wheels. This is
# especially important on fresh Windows-on-ARM/Parallels installs where torch
# otherwise fails with c10.dll / WinError 126 during Demucs preload/first use.
if ($Runtime -eq "win-x64") {
    $vcSrc = Resolve-VCRedistX64Source -WinRoot $winRoot
    if ($vcSrc -and (Test-Path $vcSrc)) {
        $redistDir = Join-Path $publishDir "redist"
        New-Item -ItemType Directory -Force -Path $redistDir | Out-Null
        Copy-Item -Force $vcSrc (Join-Path $redistDir "vc_redist.x64.exe")
        Write-Host "Bundled Visual C++ Redistributable x64 from $vcSrc"
    }
}

# Bundle ffmpeg for MP3/FLAC export. Priority:
#   -FfmpegSource / LEMMINGS_FFMPEG_SRC -> Ports\Windows\ffmpeg -> PATH -> auto-download.
# Use -SkipFfmpeg to keep the old no-bundle behavior. WAV/AIFF export never needs ffmpeg.
if ($SkipFfmpeg) {
    Warn "Skipping ffmpeg bundling by request. MP3/FLAC export will need ffmpeg on PATH or LEMMINGS_FFMPEG set. WAV/AIFF export is unaffected."
} else {
    $ffmpegSrc = Resolve-FfmpegSource -Runtime $Runtime -WinRoot $winRoot -ExplicitSource $FfmpegSource
    if ($ffmpegSrc -and (Test-Path $ffmpegSrc)) {
        Copy-Item -Force $ffmpegSrc (Join-Path $publishDir "ffmpeg.exe")
        Write-Host "Bundled ffmpeg from $ffmpegSrc"
    } else {
        Warn "No ffmpeg bundled. MP3/FLAC export will need ffmpeg on PATH or LEMMINGS_FFMPEG set. WAV/AIFF export is unaffected."
    }
}
New-Item -ItemType Directory -Force -Path $stagingDocs | Out-Null
Copy-Item -Force (Join-Path $repoRoot "Docs\WindowsBuildForNoobs.md") $stagingDocs -ErrorAction SilentlyContinue
Copy-Item -Force (Join-Path $repoRoot "Docs\WindowsPortPlan.md") $stagingDocs -ErrorAction SilentlyContinue
Copy-Item -Force (Join-Path $winRoot "README.md") (Join-Path $publishDir "README-WINDOWS.txt")

@{
    app = "LemmingsStudio"
    version = $Version
    runtime = $Runtime
    backend = $Backend
    builtAt = (Get-Date).ToString("o")
    backendInstall = "Use the app's Install / Repair Backend button, or run scripts\\setup-backend.ps1."
    bundledModels = $(if ($PreloadModels) { $ModelNames } else { @() })
    bundledModelCache = $(if ($PreloadModels) { "model-cache\\torch" } else { $null })
} | ConvertTo-Json | Set-Content -Encoding UTF8 (Join-Path $publishDir "windows-build-manifest.json")

if ($PreloadModels -and -not $canBundleDemucsModels) {
    Warn "Skipping Demucs model preload/bundling for native win-arm64. PyTorch currently provides torch, but torchaudio and several Demucs dependencies do not have a usable native Windows ARM64 wheel path here. Build win-x64 under emulation for a full Demucs/stem-splitting installer, or set LEMMINGS_EXPERIMENTAL_WINARM64_STEMS=1 to try unsupported source builds."
}
elseif ($PreloadModels) {
    Step "Preloading and bundling Demucs model weights"
    Warn "This can add hundreds of MB to the installer. Use -ModelNames to narrow the bundled models if needed."
    Remove-Item -Recurse -Force $modelCacheRoot -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path $torchModelCache | Out-Null
    $oldTorchHome = $env:TORCH_HOME
    try {
        $env:TORCH_HOME = $torchModelCache
        & (Join-Path $winRoot "scripts\setup-backend.ps1") -Backend $Backend -Runtime $Runtime -PreloadModels -ModelNames $ModelNames
    } finally {
        if ($null -ne $oldTorchHome) { $env:TORCH_HOME = $oldTorchHome } else { Remove-Item Env:TORCH_HOME -ErrorAction SilentlyContinue }
    }
    if (Test-Path $torchModelCache) {
        $modelFiles = Get-ChildItem -Path $torchModelCache -Recurse -File -ErrorAction SilentlyContinue | Measure-Object
        Write-Host "Bundled Demucs/PyTorch model cache: $($modelFiles.Count) file(s) under $torchModelCache"
    }
}

if ($SkipInstaller) {
    Step "Skipping installer as requested"
    Write-Host "Published app folder: $publishDir"
    exit 0
}

Step "Finding Inno Setup compiler"
$iscc = $InnoSetupPath
if (-not $iscc) {
    # 1) Known install roots, version-agnostic (covers Inno Setup 5/6/7, machine + user scope).
    $globs = @(
        "${env:ProgramFiles(x86)}\Inno Setup*\ISCC.exe",
        "$env:ProgramFiles\Inno Setup*\ISCC.exe",
        "$env:LOCALAPPDATA\Programs\Inno Setup*\ISCC.exe",
        "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\*Inno*\ISCC.exe"
    )
    foreach ($g in $globs) {
        $hit = Get-ChildItem -Path $g -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($hit) { $iscc = $hit.FullName; break }
    }
    # 2) ISCC on PATH (works after opening a fresh shell post-install).
    if (-not $iscc -and (Get-Command iscc -ErrorAction SilentlyContinue)) { $iscc = (Get-Command iscc).Source }
    # 3) Registry: Inno Setup's uninstall key records its InstallLocation.
    if (-not $iscc) {
        $regRoots = @(
            "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
            "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
        )
        foreach ($r in $regRoots) {
            $key = Get-ItemProperty -Path $r -ErrorAction SilentlyContinue |
                   Where-Object { $_.DisplayName -like "Inno Setup*" -and $_.InstallLocation } |
                   Select-Object -First 1
            if ($key) {
                $candidate = Join-Path $key.InstallLocation "ISCC.exe"
                if (Test-Path $candidate) { $iscc = $candidate; break }
            }
        }
    }
}

if (-not $iscc -or -not (Test-Path $iscc)) {
    Warn "Inno Setup was not found, so no installer EXE was created."
    Write-Host "Install it with: winget install JRSoftware.InnoSetup  (then open a NEW terminal)"
    Write-Host "Or pass the path explicitly: -InnoSetupPath 'C:\Path\to\ISCC.exe'"
    Write-Host "Then rerun this script. Published app folder: $publishDir"
    exit 0
}
Write-Host "Using Inno Setup: $iscc"

Step "Building installer EXE"
New-Item -ItemType Directory -Force -Path $installerOut | Out-Null
$iss = Join-Path $winRoot "installer\LemmingsStudio.iss"
& $iscc "/DAppVersion=$Version" "/DBackend=$Backend" "/DRuntime=$Runtime" "/DSourceDir=$publishDir" "/DOutputDir=$installerOut" $iss

Step "Done"
Get-ChildItem $installerOut -Filter "*.exe" | ForEach-Object { Write-Host "Installer: $($_.FullName)" }
