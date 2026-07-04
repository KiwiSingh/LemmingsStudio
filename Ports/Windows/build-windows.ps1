param(
    [ValidateSet("cpu", "directml", "cuda", "qnn", "openvino")]
    [string]$Backend = "directml",
    [ValidateSet("win-x64", "win-arm64")]
    [string]$Runtime = "win-x64",
    [switch]$BundleModels,
    [switch]$SkipInstaller,
    [switch]$SkipFfmpeg,
    [string]$FfmpegSource = "",
    [string[]]$ModelNames = @("htdemucs", "htdemucs_ft", "htdemucs_6s"),
    [string]$Version = "1.1.0",
    [switch]$SkipNativeVst3Host,
    [switch]$RequireNativeVst3Host,
    [switch]$SkipNativeVst3ToolchainBootstrap,
    [string]$NativeVst3HostPath = ""
)

$script = Join-Path $PSScriptRoot "build-installer.ps1"
& $script -Backend $Backend -Runtime $Runtime -PreloadModels:$BundleModels -SkipInstaller:$SkipInstaller -SkipFfmpeg:$SkipFfmpeg -FfmpegSource $FfmpegSource -ModelNames $ModelNames -Version $Version -SkipNativeVst3Host:$SkipNativeVst3Host -RequireNativeVst3Host:$RequireNativeVst3Host -SkipNativeVst3ToolchainBootstrap:$SkipNativeVst3ToolchainBootstrap -NativeVst3HostPath $NativeVst3HostPath
