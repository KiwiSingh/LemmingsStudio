param([switch]$Json)

# Detect CPU, GPU vendor(s), and whether an NPU is likely present, then recommend a
# backend flavor. With -Json, emits a single machine-readable line the app parses.

$cpu = (Get-CimInstance Win32_Processor | Select-Object -First 1).Name
$gpuNames = @(Get-CimInstance Win32_VideoController | ForEach-Object { $_.Name })
$gpus = ($gpuNames -join " | ")

# NPU heuristic: Copilot+ / Snapdragon parts, or a video controller advertising an NPU.
$arch = $env:PROCESSOR_ARCHITECTURE
$isArm = $arch -match "ARM"
$npuLikely = $isArm -or ($cpu -match "Snapdragon|Hexagon|Copilot|Ryzen AI|Core Ultra")

if ($gpus -match "NVIDIA") { $recommended = "cuda" }
elseif ($npuLikely)        { $recommended = "qnn" }
elseif ($gpus -match "Intel|Arc|Iris|UHD") { $recommended = "openvino" }
elseif ($gpus -match "AMD|Radeon") { $recommended = "directml" }
else { $recommended = "cpu" }

if ($Json) {
    [pscustomobject]@{
        cpu         = $cpu
        gpus        = $gpuNames
        arch        = $arch
        npuLikely   = [bool]$npuLikely
        recommended = $recommended
    } | ConvertTo-Json -Compress
    return
}

Write-Host "LemmingsStudio Windows hardware sanity check"
Write-Host "-------------------------------------------"
Write-Host "CPU:  $cpu"
Write-Host "Arch: $arch"
Write-Host "GPU(s): $gpus"
Write-Host ("NPU likely: " + ($(if ($npuLikely) { "yes" } else { "no" })))
Write-Host "Recommended backend: $recommended"
Write-Host ""
Write-Host "Flavors: cuda (NVIDIA) | directml (AMD/Intel/any DX12 GPU) | openvino (Intel) | qnn (ARM NPU) | cpu (always works)"
