param(
    [ValidateSet("cpu", "directml", "cuda", "qnn", "openvino")]
    [string]$Backend = "directml",
    [string]$Python = "python",
    [ValidateSet("win-x64", "win-arm64", "auto")]
    [string]$Runtime = "auto",
    [switch]$PreloadModels,
    [string[]]$ModelNames = @("htdemucs", "htdemucs_ft", "htdemucs_6s")
)

$ErrorActionPreference = "Stop"

function Write-Step($Text) { Write-Host "==> $Text" }
function Write-Warn($Text) { Write-Host "WARNING: $Text" -ForegroundColor Yellow }

function Invoke-PipRequired([string[]]$ArgsList, [string]$What) {
    Write-Step $What
    & $venvPython -m pip @ArgsList
    if ($LASTEXITCODE -ne 0) { throw "$What failed." }
}

function Invoke-PipOptional([string[]]$ArgsList, [string]$What) {
    Write-Step $What
    & $venvPython -m pip @ArgsList
    if ($LASTEXITCODE -ne 0) { Write-Warn "$What failed; continuing without this optional capability."; return $false }
    return $true
}

function Get-PythonMachineForExe([string]$Exe) {
    try { return (& $Exe -c "import platform; print(platform.machine().lower())").Trim() } catch { return "unknown" }
}

function Get-PythonVersionForExe([string]$Exe) {
    try { return (& $Exe -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}')").Trim() } catch { return "unknown" }
}

function Get-PythonMinorForExe([string]$Exe) {
    try { return (& $Exe -c "import sys; print(sys.version_info.minor)").Trim() } catch { return "0" }
}

function Get-PythonExecutableFromPyLauncher([string]$Selector) {
    $py = Get-Command py -ErrorAction SilentlyContinue
    if (-not $py) { return $null }
    try {
        $exe = (& $py.Source $Selector -c "import sys; print(sys.executable)").Trim()
        if ($LASTEXITCODE -eq 0 -and $exe -and (Test-Path $exe)) { return $exe }
    } catch { }
    return $null
}

function Install-ManagedPythonX64 {
    $targetDir = Join-Path $env:LOCALAPPDATA "LemmingsStudio\Python\Python311-x64"
    $pythonExe = Join-Path $targetDir "python.exe"
    if (Test-Path $pythonExe) { return $pythonExe }

    Write-Warn "No x64 Python was found, but Runtime=win-x64 was requested. Installing a user-local Python 3.11 x64 for the LemmingsStudio backend."
    New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
    $installer = Join-Path $env:TEMP "python-3.11.9-amd64-lemmings.exe"
    $url = "https://www.python.org/ftp/python/3.11.9/python-3.11.9-amd64.exe"
    Write-Step "Downloading Python 3.11 x64"
    Invoke-WebRequest -Uri $url -OutFile $installer -UseBasicParsing -TimeoutSec 300
    Write-Step "Installing Python 3.11 x64 for current user"
    $args = @("/quiet", "InstallAllUsers=0", "PrependPath=0", "Include_launcher=0", "Include_pip=1", "Include_test=0", "TargetDir=$targetDir")
    $p = Start-Process -FilePath $installer -ArgumentList $args -Wait -PassThru
    if ($p.ExitCode -ne 0 -or -not (Test-Path $pythonExe)) {
        throw "Could not install user-local Python x64. Install Python 3.11 x64 manually from python.org and rerun setup."
    }
    return $pythonExe
}

function Resolve-PythonForRuntime {
    if ($Runtime -eq "auto") {
        $manifest = Join-Path $appRoot "windows-build-manifest.json"
        if (Test-Path $manifest) {
            try {
                $json = Get-Content -Raw $manifest | ConvertFrom-Json
                if ($json.runtime) { $script:Runtime = [string]$json.runtime }
            } catch { }
        }
    }
    if ($Runtime -eq "auto") { $script:Runtime = "win-x64" }

    $explicitPython = -not [string]::Equals($Python, "python", [System.StringComparison]::OrdinalIgnoreCase)
    if ($explicitPython) {
        $cmd = Get-Command $Python -ErrorAction SilentlyContinue
        if (-not $cmd) { throw "Python was not found at '$Python'." }
        return $cmd.Source
    }

    $wantX64 = ($Runtime -eq "win-x64")
    $candidates = New-Object System.Collections.Generic.List[string]

    if ($wantX64) {
        foreach ($sel in @("-3.11-64", "-3.12-64", "-3.10-64", "-3-64")) {
            $hit = Get-PythonExecutableFromPyLauncher $sel
            if ($hit) { $candidates.Add($hit) }
        }
        foreach ($path in @(
            "$env:LOCALAPPDATA\Programs\Python\Python312\python.exe",
            "$env:LOCALAPPDATA\Programs\Python\Python311\python.exe",
            "$env:LOCALAPPDATA\Programs\Python\Python310\python.exe",
            "$env:ProgramFiles\Python312\python.exe",
            "$env:ProgramFiles\Python311\python.exe",
            "$env:ProgramFiles\Python310\python.exe"
        )) { if ($path -and (Test-Path $path)) { $candidates.Add($path) } }
    }

    $cmdDefault = Get-Command python -ErrorAction SilentlyContinue
    if ($cmdDefault) { $candidates.Add($cmdDefault.Source) }

    foreach ($candidate in ($candidates | Select-Object -Unique)) {
        $machine = Get-PythonMachineForExe $candidate
        if ($wantX64) {
            if ($machine -eq "amd64" -or $machine -eq "x86_64") { return $candidate }
        } else {
            if ($machine -eq "arm64" -or $machine -eq "aarch64") { return $candidate }
        }
    }

    if ($wantX64) { return Install-ManagedPythonX64 }

    if ($cmdDefault) { return $cmdDefault.Source }
    throw "Python was not found. Install Python 3.11 from python.org, tick 'Add python.exe to PATH', then rerun this setup."
}


function Install-VCRedistX64IfNeeded {
    if (-not ($IsWindows -or $env:OS -eq "Windows_NT")) { return }
    if (-not ($Runtime -eq "win-x64" -or $isWindowsX64Python)) { return }

    # PyTorch's Windows x64 CPU wheels depend on the Microsoft Visual C++ runtime.
    # Fresh Windows/Parallels VMs often do not have it, which causes torch import to
    # fail with c10.dll / WinError 126 during Demucs model preloading.
    $redistCandidates = @(
        (Join-Path $appRoot "redist\vc_redist.x64.exe"),
        (Join-Path $PSScriptRoot "..\redist\vc_redist.x64.exe"),
        (Join-Path $env:LOCALAPPDATA "LemmingsStudio\Redist\vc_redist.x64.exe")
    )
    $redist = $redistCandidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
    if (-not $redist) {
        $cacheDir = Join-Path $env:LOCALAPPDATA "LemmingsStudio\Redist"
        New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null
        $redist = Join-Path $cacheDir "vc_redist.x64.exe"
        Write-Step "Downloading Microsoft Visual C++ Redistributable x64"
        try {
            Invoke-WebRequest -Uri "https://aka.ms/vs/17/release/vc_redist.x64.exe" -OutFile $redist -UseBasicParsing -TimeoutSec 300
        } catch {
            Write-Warn "Could not download Microsoft Visual C++ Redistributable x64: $($_.Exception.Message)"
            return
        }
    }

    Write-Step "Installing/checking Microsoft Visual C++ Redistributable x64"
    try {
        $p = Start-Process -FilePath $redist -ArgumentList @("/install", "/quiet", "/norestart") -Wait -PassThru
        if ($p.ExitCode -eq 0 -or $p.ExitCode -eq 3010 -or $p.ExitCode -eq 1638) {
            if ($p.ExitCode -eq 3010) { Write-Warn "Visual C++ Redistributable installed and requested a reboot. Torch may still work immediately, but reboot if DLL loading still fails." }
            return
        }
        Write-Warn "Visual C++ Redistributable installer exited with code $($p.ExitCode). If torch still fails with c10.dll / WinError 126, install it manually from https://aka.ms/vs/17/release/vc_redist.x64.exe and rerun setup."
    } catch {
        Write-Warn "Could not run Visual C++ Redistributable installer: $($_.Exception.Message)"
    }
}

function Test-TorchImport {
    try {
        & $venvPython -c "import torch; print('torch-ok', torch.__version__)" | Out-Host
        return ($LASTEXITCODE -eq 0)
    } catch { return $false }
}

function Install-TorchCodecIfNeeded {
    if (-not $demucsCapable) { return }
    Write-Host "Skipping TorchCodec install: LemmingsStudio patches Demucs stem saving through soundfile on Windows, avoiding TorchCodec/FFmpeg shared-DLL compatibility issues."
}

function Write-BackendCapability([string]$StemStatus, [string]$Reason) {
@"
backend=$Backend
runtime=$Runtime
python=$pyVersion
pythonMachine=$pythonMachine
created=$(Get-Date -Format o)
venv=$venv
torchHome=$torchHome
preloadModels=$($PreloadModels.IsPresent)
models=$($ModelNames -join ",")
stems=$StemStatus
stemReason=$Reason
"@ | Set-Content -Encoding UTF8 $stamp
}


$root = Join-Path $env:LOCALAPPDATA "LemmingsStudio"
$backendRoot = Join-Path $root "Backends"
$venv = Join-Path $backendRoot $Backend
$stamp = Join-Path $venv "lemmings-backend-$Backend.txt"
$appRoot = Split-Path $PSScriptRoot -Parent
$Python = Resolve-PythonForRuntime
$bundledModelCache = Join-Path $appRoot "model-cache"
$torchHome = if ($env:TORCH_HOME) { $env:TORCH_HOME } else { Join-Path $env:USERPROFILE ".cache\torch" }
New-Item -ItemType Directory -Force -Path $backendRoot | Out-Null

Write-Step "Preparing LemmingsStudio backend: $Backend ($Runtime)"
Write-Host "Install location: $venv"
Write-Host "Torch/model cache: $torchHome"

# If the installer bundled offline model weights, seed the user's cache before any
# Python/Demucs run. Demucs/PyTorch honors TORCH_HOME, so this avoids a first-run
# network download when model-cache\torch exists next to the installed app.
if (Test-Path (Join-Path $bundledModelCache "torch")) {
    Write-Step "Installing bundled model cache"
    New-Item -ItemType Directory -Force -Path $torchHome | Out-Null
    Copy-Item -Recurse -Force (Join-Path $bundledModelCache "torch\*") $torchHome
    Write-Host "Model cache: $torchHome"
}
$env:TORCH_HOME = $torchHome

$pyVersion = Get-PythonVersionForExe $Python
$pythonMachine = Get-PythonMachineForExe $Python
Write-Host "Python: $pyVersion ($pythonMachine) at $Python"

$minor = Get-PythonMinorForExe $Python
if ([int]$minor -lt 10 -or [int]$minor -gt 12) {
    Write-Warn "Python 3.10–3.12 is recommended for audio/ML packages. You are using $pyVersion."
}

$isWindowsArm64Python = ($IsWindows -or $env:OS -eq "Windows_NT") -and ($pythonMachine -eq "arm64" -or $pythonMachine -eq "aarch64")
$isWindowsX64Python = ($IsWindows -or $env:OS -eq "Windows_NT") -and ($pythonMachine -eq "amd64" -or $pythonMachine -eq "x86_64")
if ($Runtime -eq "win-x64" -and -not $isWindowsX64Python) {
    throw "Runtime=win-x64 requires x64 Python, but resolved Python is '$pythonMachine' at $Python. Install Python 3.11 x64 or pass -Python C:\Path\To\x64\python.exe."
}
if ($isWindowsArm64Python) {
    Write-Warn "Detected native Windows ARM64 Python ($pythonMachine). The current Python audio/ML ecosystem does not provide all wheels needed by Demucs here: torchaudio is unavailable, and packages such as numba/llvmlite/soxr fall back to native source builds. Stem splitting will be disabled on this backend instead of breaking setup. Use a win-x64 build/Python under emulation for full Demucs support, or set LEMMINGS_EXPERIMENTAL_WINARM64_STEMS=1 to try source builds."
}

if ($isWindowsX64Python) {
    Install-VCRedistX64IfNeeded
}

$venvPython = Join-Path $venv "Scripts\python.exe"
$venvPip = Join-Path $venv "Scripts\pip.exe"
if (Test-Path $venvPython) {
    $venvMachine = Get-PythonMachineForExe $venvPython
    if (($Runtime -eq "win-x64" -and $venvMachine -ne "amd64" -and $venvMachine -ne "x86_64") -or
        ($Runtime -eq "win-arm64" -and $venvMachine -ne "arm64" -and $venvMachine -ne "aarch64")) {
        Write-Warn "Existing backend venv uses $venvMachine Python but this setup needs $Runtime. Recreating $venv."
        Remove-Item -Recurse -Force $venv
    }
}

if (-not (Test-Path $venv)) {
    Write-Step "Creating virtual environment"
    & $Python -m venv $venv
}

$venvPython = Join-Path $venv "Scripts\python.exe"
$venvPip = Join-Path $venv "Scripts\pip.exe"

Write-Step "Updating pip"
& $venvPython -m pip install --upgrade pip setuptools wheel certifi

Write-Step "Installing core audio dependencies"
# On native Windows ARM64, avoid packages that currently lack reliable wheels and
# trigger local C++/CMake builds (librosa -> numba/llvmlite/soxr). The app can
# still run, export audio via ffmpeg, use Ollama/agentic UI, and install/repair
# the backend; Demucs stems are marked unavailable below unless the user opts in.
if ($isWindowsArm64Python -and -not $env:LEMMINGS_EXPERIMENTAL_WINARM64_STEMS) {
    Invoke-PipRequired @("install", "--upgrade", "--prefer-binary", "numpy", "scipy", "soundfile", "ffmpeg-python", "tqdm", "pyyaml", "requests") "Installing Windows ARM64 safe Python packages"
} else {
    Invoke-PipRequired @("install", "--upgrade", "--prefer-binary", "numpy", "scipy", "soundfile", "librosa", "ffmpeg-python", "tqdm", "pyyaml", "requests") "Installing full audio/stem Python packages"
}

$demucsCapable = $true
$stemReason = "available"
if ($isWindowsArm64Python -and -not $env:LEMMINGS_EXPERIMENTAL_WINARM64_STEMS) {
    $demucsCapable = $false
    $stemReason = "Demucs disabled on native Windows ARM64 because torchaudio has no matching wheel and numba/llvmlite/soxr fall back to source builds. Use win-x64 Python/runtime under emulation for stems, or set LEMMINGS_EXPERIMENTAL_WINARM64_STEMS=1 to try unsupported source builds."
}

switch ($Backend) {
    "cpu" {
        Write-Step "Installing PyTorch CPU backend"
        if ($demucsCapable) {
            Invoke-PipRequired @("install", "--upgrade", "torch", "torchaudio", "--index-url", "https://download.pytorch.org/whl/cpu") "Installing PyTorch + torchaudio CPU wheels"
        } else {
            Invoke-PipOptional @("install", "--upgrade", "torch", "--index-url", "https://download.pytorch.org/whl/cpu") "Installing optional PyTorch CPU wheel"
        }
        Invoke-PipOptional @("install", "--upgrade", "onnxruntime") "Installing optional ONNX Runtime CPU"
    }
    "directml" {
        Write-Step "Installing DirectML backend"
        Write-Host "DirectML is the broad Windows choice for AMD, Intel, NVIDIA, and many iGPU systems."
        if ($demucsCapable) {
            Invoke-PipRequired @("install", "--upgrade", "torch", "torchaudio", "--index-url", "https://download.pytorch.org/whl/cpu") "Installing PyTorch + torchaudio CPU wheels"
        } else {
            Invoke-PipOptional @("install", "--upgrade", "torch", "--index-url", "https://download.pytorch.org/whl/cpu") "Installing optional PyTorch CPU wheel"
        }
        Invoke-PipOptional @("install", "--upgrade", "onnxruntime-directml") "Installing optional ONNX Runtime DirectML"
    }
    "cuda" {
        Write-Step "Installing CUDA backend"
        Write-Host "CUDA requires an NVIDIA GPU and compatible NVIDIA drivers."
        if ($demucsCapable) {
            Invoke-PipRequired @("install", "--upgrade", "torch", "torchaudio", "--index-url", "https://download.pytorch.org/whl/cu121") "Installing PyTorch + torchaudio CUDA wheels"
        } else {
            Invoke-PipOptional @("install", "--upgrade", "torch", "--index-url", "https://download.pytorch.org/whl/cpu") "Installing optional PyTorch CPU wheel"
        }
        Invoke-PipOptional @("install", "--upgrade", "onnxruntime-gpu") "Installing optional ONNX Runtime GPU"
    }
    "qnn" {
        Write-Step "Installing QNN (Snapdragon / Copilot+ NPU) backend"
        Write-Host "QNN targets the ARM64 NPU via ONNX Runtime. Requires a win-arm64 Python and real Copilot+ hardware to actually engage the NPU."
        if ($demucsCapable) {
            Invoke-PipRequired @("install", "--upgrade", "torch", "torchaudio", "--index-url", "https://download.pytorch.org/whl/cpu") "Installing PyTorch + torchaudio CPU wheels"
        } else {
            Invoke-PipOptional @("install", "--upgrade", "torch", "--index-url", "https://download.pytorch.org/whl/cpu") "Installing optional PyTorch CPU wheel"
        }
        Invoke-PipOptional @("install", "--upgrade", "onnxruntime-qnn") "Installing optional ONNX Runtime QNN"
    }
    "openvino" {
        Write-Step "Installing OpenVINO (Intel CPU/iGPU/Arc) backend"
        Write-Host "OpenVINO gives native Intel acceleration via ONNX Runtime's OpenVINO provider."
        if ($demucsCapable) {
            Invoke-PipRequired @("install", "--upgrade", "torch", "torchaudio", "--index-url", "https://download.pytorch.org/whl/cpu") "Installing PyTorch + torchaudio CPU wheels"
        } else {
            Invoke-PipOptional @("install", "--upgrade", "torch", "--index-url", "https://download.pytorch.org/whl/cpu") "Installing optional PyTorch CPU wheel"
        }
        Invoke-PipOptional @("install", "--upgrade", "onnxruntime-openvino") "Installing optional ONNX Runtime OpenVINO"
    }
}

if ($demucsCapable) {
    Write-Step "Verifying PyTorch import"
    if (-not (Test-TorchImport)) {
        Write-Warn "PyTorch did not import cleanly. Attempting Visual C++ Redistributable repair before continuing."
        Install-VCRedistX64IfNeeded
        if (-not (Test-TorchImport)) {
            $demucsCapable = $false
            $stemReason = "PyTorch could not load on this machine, usually because the Microsoft Visual C++ Redistributable x64 is missing or Windows needs a reboot after installing it. Stem splitting disabled for this backend until setup is rerun successfully."
            Write-Warn $stemReason
        }
    }
}

function Install-DemucsPackage {
    Write-Step "Installing Demucs"

    # First try normal PyPI. Use --prefer-binary so pip avoids building
    # dependencies from source whenever a compatible wheel exists.
    & $venvPython -m pip install --upgrade --prefer-binary demucs
    if ($LASTEXITCODE -eq 0) { return }

    Write-Warn "PyPI Demucs install failed. Retrying from the official GitHub source archive because the PyPI source package can be missing requirements_minimal.txt on some Windows setups."

    # Avoid requiring git.exe on a fresh Windows install: pip can install directly
    # from GitHub's source zip, which contains requirements_minimal.txt.
    $demucsZip = "https://github.com/facebookresearch/demucs/archive/refs/heads/main.zip"
    & $venvPython -m pip install --upgrade --prefer-binary $demucsZip
    if ($LASTEXITCODE -ne 0) {
        throw "Could not install Demucs from PyPI or GitHub source archive. Check Python version, internet access, and package build tools, then rerun backend setup."
    }
}

if ($demucsCapable) {
    Install-TorchCodecIfNeeded
    Install-DemucsPackage
} else {
    Write-Warn $stemReason
}

if ($PreloadModels -and -not $demucsCapable) {
    Write-Warn "Skipping Demucs model preload because this backend is not Demucs-capable."
}

if ($PreloadModels -and $demucsCapable) {
    Write-Step "Preloading Demucs model weights"
    $testDir = Join-Path $env:TEMP "LemmingsStudioBackendPreload"
    New-Item -ItemType Directory -Force -Path $testDir | Out-Null
    $wav = Join-Path $testDir "preload_probe.wav"
    $pySnippet = @"
import math, os, pathlib, random, struct, wave

# Do not use absolute digital silence here. Some Demucs/HTDemucs builds can trip
# an internal reflect-padding assertion on tiny or perfectly-flat probe files.
# A short, quiet, non-silent stereo tone is enough to force model download/cache
# without producing a meaningful output artifact.
p = pathlib.Path(os.environ['LS_PRELOAD_WAV'])
p.parent.mkdir(parents=True, exist_ok=True)
sr = 44100
duration = 12.0
frames = int(sr * duration)
amp = 0.015
rng = random.Random(12345)
with wave.open(str(p), 'wb') as w:
    w.setnchannels(2)
    w.setsampwidth(2)
    w.setframerate(sr)
    buf = bytearray()
    for i in range(frames):
        t = i / sr
        # Two different low-level tones plus tiny deterministic noise, duplicated
        # with a small channel difference so the file is not mono-flat either.
        left = amp * (math.sin(2 * math.pi * 220.0 * t) + 0.25 * math.sin(2 * math.pi * 440.0 * t)) + rng.uniform(-0.001, 0.001)
        right = amp * (math.sin(2 * math.pi * 330.0 * t) + 0.20 * math.sin(2 * math.pi * 550.0 * t)) + rng.uniform(-0.001, 0.001)
        left_i = max(-32768, min(32767, int(left * 32767)))
        right_i = max(-32768, min(32767, int(right * 32767)))
        buf.extend(struct.pack('<hh', left_i, right_i))
    w.writeframes(bytes(buf))
"@
    $env:LS_PRELOAD_WAV = $wav
    & $venvPython -c $pySnippet
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $wav)) {
        Write-Warn "Could not generate Demucs preload probe WAV. Skipping model preload; the backend can still download models on first use."
    } else {
        foreach ($modelName in $ModelNames) {
            if ([string]::IsNullOrWhiteSpace($modelName)) { continue }
            Write-Step "Preloading Demucs model weights: $modelName"
            $env:LS_DEMUCS_MODEL = $modelName
            $preloadSnippet = @"
import os
from demucs.pretrained import get_model
name = os.environ.get('LS_DEMUCS_MODEL', 'htdemucs')
model = get_model(name)
print(f'demucs-model-ok {name}')
"@
            & $venvPython -c $preloadSnippet
            if ($LASTEXITCODE -ne 0) {
                Write-Warn "Model weight preload failed for $modelName. This is non-fatal; the backend can still download/cache it on first real use if internet/certs work."
            }
        }
    }
}

if ($demucsCapable) {
    Write-BackendCapability "available" $stemReason
} else {
    Write-BackendCapability "unavailable" $stemReason
}

Write-Step "Verifying accelerator selection"
$backendDir = Join-Path (Split-Path $PSScriptRoot -Parent) "backend"
$runner = Join-Path $backendDir "stem_runner.py"
if (Test-Path $runner) {
    & $venvPython $runner --probe $Backend
} else {
    Write-Warn "stem_runner.py not found next to scripts; provider probe skipped."
}

Write-Step "Backend setup complete"
Write-Host "Venv Python: $venvPython"
