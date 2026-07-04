using System.Diagnostics;
using System.Text;

namespace LemmingsStudio.Windows;

public sealed class BackendRunner
{
    public event Action<string>? Log;

    public async Task<int> RunPowerShellAsync(string script, string arguments, string workingDirectory, CancellationToken token = default)
    {
        var shell = FindPowerShell();
        var psi = new ProcessStartInfo
        {
            FileName = shell,
            Arguments = $"-NoProfile -ExecutionPolicy Bypass -File \"{script}\" {arguments}",
            WorkingDirectory = workingDirectory,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true,
            StandardOutputEncoding = Encoding.UTF8,
            StandardErrorEncoding = Encoding.UTF8
        };
        Log?.Invoke($"> {shell} {psi.Arguments}");
        using var process = new Process { StartInfo = psi, EnableRaisingEvents = true };
        process.OutputDataReceived += (_, e) => { if (e.Data != null) Log?.Invoke(e.Data); };
        process.ErrorDataReceived += (_, e) => { if (e.Data != null) Log?.Invoke(e.Data); };
        process.Start();
        process.BeginOutputReadLine();
        process.BeginErrorReadLine();
        await process.WaitForExitAsync(token);
        Log?.Invoke($"exit={process.ExitCode}");
        return process.ExitCode;
    }

    private static string FindPowerShell()
    {
        try
        {
            var psi = new ProcessStartInfo
            {
                FileName = "where",
                Arguments = "pwsh",
                RedirectStandardOutput = true,
                UseShellExecute = false,
                CreateNoWindow = true
            };
            using var p = Process.Start(psi);
            p?.WaitForExit(1200);
            if (p?.ExitCode == 0) return "pwsh";
        }
        catch { }
        return "powershell.exe";
    }
}
