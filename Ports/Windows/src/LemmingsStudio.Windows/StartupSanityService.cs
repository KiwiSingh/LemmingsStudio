using System.Text;

namespace LemmingsStudio.Windows;

public static class StartupSanityService
{
    public static string Run()
    {
        var sb = new StringBuilder();
        sb.AppendLine("Startup sanity report:");
        AppPaths.EnsureFirstRunFolders();
        foreach (var path in new[] { AppPaths.Root, AppPaths.Autosaves, AppPaths.Logs, AppPaths.Diagnostics, AppPaths.UserProjects, AppPaths.Recordings, AppPaths.Renders, AppPaths.SpliceCache })
            sb.AppendLine(TestWritable(path));
        sb.AppendLine(TestUnicodeAndLongPath());
        sb.AppendLine(File.Exists(Path.Combine(AppContext.BaseDirectory, "LemmingsVst3Host.exe")) ? "PASS native VST3 helper present" : "WARN native VST3 helper not bundled");
        sb.AppendLine(File.Exists(Path.Combine(AppContext.BaseDirectory, "ffmpeg.exe")) ? "PASS bundled ffmpeg present" : "WARN bundled ffmpeg not found beside app");
        return sb.ToString().TrimEnd();
    }

    private static string TestWritable(string dir)
    {
        try
        {
            var p = Path.Combine(dir, ".write-test-" + Guid.NewGuid().ToString("N"));
            File.WriteAllText(p, "ok"); File.Delete(p);
            return "PASS writable: " + dir;
        }
        catch (Exception ex) { return "FAIL writable: " + dir + " — " + ex.Message; }
    }

    private static string TestUnicodeAndLongPath()
    {
        try
        {
            var nested = Path.Combine(AppPaths.Root, "PathTests", "नमस्ते_音楽_тест", new string('L', 80), new string('P', 80));
            Directory.CreateDirectory(nested);
            var file = Path.Combine(nested, "संगीत_テスト_é.wav.txt");
            File.WriteAllText(file, "LemmingsStudio path test");
            var ok = File.ReadAllText(file) == "LemmingsStudio path test";
            Directory.Delete(Path.Combine(AppPaths.Root, "PathTests"), true);
            return ok ? "PASS Unicode/long path I/O" : "FAIL Unicode/long path content mismatch";
        }
        catch (Exception ex) { return "WARN Unicode/long path I/O: " + ex.Message; }
    }
}
