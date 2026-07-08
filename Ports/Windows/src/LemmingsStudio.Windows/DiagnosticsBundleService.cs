using System.IO.Compression;
using System.Text;

namespace LemmingsStudio.Windows;

public static class DiagnosticsBundleService
{
    public static string Create(StudioProject project, string? projectPath, IEnumerable<string> recentLogLines)
    {
        AppPaths.EnsureFirstRunFolders();
        var stamp = DateTime.UtcNow.ToString("yyyyMMdd_HHmmss");
        var temp = Path.Combine(Path.GetTempPath(), "LemmingsStudioDiag_" + stamp);
        Directory.CreateDirectory(temp);
        File.WriteAllText(Path.Combine(temp, "system.txt"), BuildSystemText(project, projectPath));
        File.WriteAllLines(Path.Combine(temp, "recent-log.txt"), recentLogLines.TakeLast(2000));
        var health = ProjectHealthService.Audit(project);
        File.WriteAllText(Path.Combine(temp, "project-health.txt"), health.Summary());
        CopyIfExists(Path.Combine(AppContext.BaseDirectory, "windows-build-manifest.json"), Path.Combine(temp, "windows-build-manifest.json"));
        CopyIfExists(Path.Combine(AppContext.BaseDirectory, "LemmingsVst3Host.exe"), Path.Combine(temp, "native-host-present.txt"), markerOnly: true);
        var zip = Path.Combine(AppPaths.Diagnostics, $"LemmingsStudio-Diagnostics-{stamp}.zip");
        if (File.Exists(zip)) File.Delete(zip);
        ZipFile.CreateFromDirectory(temp, zip, CompressionLevel.Optimal, false);
        try { Directory.Delete(temp, true); } catch { }
        return zip;
    }

    private static string BuildSystemText(StudioProject project, string? projectPath)
    {
        var sb = new StringBuilder();
        sb.AppendLine($"UTC: {DateTime.UtcNow:O}");
        sb.AppendLine($"OS: {Environment.OSVersion}");
        sb.AppendLine($"64-bit process: {Environment.Is64BitProcess}");
        sb.AppendLine($"Architecture: {System.Runtime.InteropServices.RuntimeInformation.ProcessArchitecture}");
        sb.AppendLine($"Runtime: {System.Runtime.InteropServices.RuntimeInformation.FrameworkDescription}");
        sb.AppendLine($"App base: {AppContext.BaseDirectory}");
        sb.AppendLine($"Project path: {projectPath ?? "(unsaved)"}");
        sb.AppendLine($"Project: {project.Name}, {project.Tracks.Count} tracks, {project.Tempo:0.##} BPM");
        sb.AppendLine($"Refresh: {DisplayRefreshRateDetector.DetectPrimaryRefreshRate(60)} Hz");
        sb.AppendLine($"VST3 host: {Vst3NativeHostBridge.Shared.StatusText}");
        sb.AppendLine($"VST3 crash count: {Vst3NativeHostBridge.Shared.CrashCount}");
        return sb.ToString();
    }

    private static void CopyIfExists(string source, string dest, bool markerOnly = false)
    {
        try
        {
            if (!File.Exists(source)) return;
            if (markerOnly) File.WriteAllText(dest, $"Present: {source}{Environment.NewLine}Size: {new FileInfo(source).Length:n0} bytes");
            else File.Copy(source, dest, true);
        }
        catch { }
    }
}
