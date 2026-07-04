using System.Diagnostics;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace LemmingsStudio.Windows;

/// <summary>Result of probing the machine for the best stem-splitting accelerator.</summary>
public sealed class HardwareInfo
{
    [JsonPropertyName("cpu")] public string Cpu { get; set; } = "Unknown CPU";
    [JsonPropertyName("gpus")] public string[] Gpus { get; set; } = Array.Empty<string>();
    [JsonPropertyName("arch")] public string Arch { get; set; } = "";
    [JsonPropertyName("npuLikely")] public bool NpuLikely { get; set; }
    [JsonPropertyName("recommended")] public string Recommended { get; set; } = "cpu";

    public string Summary =>
        $"CPU: {Cpu} | GPU: {(Gpus.Length > 0 ? string.Join(", ", Gpus) : "none")} | " +
        $"Arch: {Arch} | NPU: {(NpuLikely ? "likely" : "no")} | Recommended backend: {Recommended}";
}

/// <summary>
/// Runs scripts/detect-hardware.ps1 -Json and parses its recommendation so the app can
/// auto-select the right backend flavor (cuda / directml / openvino / qnn / cpu).
/// </summary>
public sealed class HardwareDetector
{
    private static readonly JsonSerializerOptions JsonOpts = new() { PropertyNameCaseInsensitive = true };

    public async Task<HardwareInfo> DetectAsync(CancellationToken token = default)
    {
        var script = ResolveScript();
        if (script == null) return new HardwareInfo();

        var shell = OperatingSystem.IsWindows() ? "powershell.exe" : "pwsh";
        var psi = new ProcessStartInfo
        {
            FileName = shell,
            Arguments = $"-NoProfile -ExecutionPolicy Bypass -File \"{script}\" -Json",
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true,
            StandardOutputEncoding = Encoding.UTF8
        };

        try
        {
            using var process = new Process { StartInfo = psi };
            process.Start();
            string output = await process.StandardOutput.ReadToEndAsync(token);
            await process.WaitForExitAsync(token);

            // The JSON is the last non-empty line the script prints.
            var line = output
                .Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
                .LastOrDefault(l => l.StartsWith("{"));
            if (line == null) return new HardwareInfo();
            return JsonSerializer.Deserialize<HardwareInfo>(line, JsonOpts) ?? new HardwareInfo();
        }
        catch
        {
            return new HardwareInfo();
        }
    }

    private static string? ResolveScript()
    {
        var candidate = Path.Combine(AppContext.BaseDirectory, "scripts", "detect-hardware.ps1");
        if (File.Exists(candidate)) return candidate;
        candidate = Path.GetFullPath(Path.Combine("Ports", "Windows", "scripts", "detect-hardware.ps1"));
        return File.Exists(candidate) ? candidate : null;
    }
}
