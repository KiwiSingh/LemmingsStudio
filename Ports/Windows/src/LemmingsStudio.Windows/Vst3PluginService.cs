using System.Diagnostics;
using System.Text.Json;

namespace LemmingsStudio.Windows;

/// <summary>
/// Windows VST3 discovery/editor bridge.
///
/// Important scope boundary: this is a real Windows scanner + project integration +
/// editor-launch bridge. Actual in-process VST3 audio processing requires a native
/// Steinberg VST3 host layer and is intentionally not faked here. Until that native
/// layer lands, VST3 slots are preserved in projects and can be opened in an external
/// VST3 host/editor (Carla/Element) for sound design, while offline render safely
/// bypasses them instead of pretending to process audio.
/// </summary>
public static class Vst3PluginService
{
    public static IReadOnlyList<Vst3PluginInfo> Scan(Action<string>? log = null)
    {
        var roots = CandidateRoots().Where(Directory.Exists).Distinct(StringComparer.OrdinalIgnoreCase).ToList();
        var found = new List<Vst3PluginInfo>();
        foreach (var root in roots)
        {
            try
            {
                foreach (var path in Directory.EnumerateFileSystemEntries(root, "*.vst3", SearchOption.AllDirectories))
                {
                    try
                    {
                        var name = Path.GetFileNameWithoutExtension(path);
                        var manufacturer = GuessManufacturer(path, root);
                        found.Add(new Vst3PluginInfo
                        {
                            Name = string.IsNullOrWhiteSpace(name) ? Path.GetFileName(path) : name,
                            Manufacturer = manufacturer,
                            Path = path,
                            IsBundleDirectory = Directory.Exists(path)
                        });
                    }
                    catch { }
                }
            }
            catch (Exception ex)
            {
                log?.Invoke($"VST3 scan skipped '{root}': {ex.Message}");
            }
        }
        return found
            .GroupBy(p => p.Path, StringComparer.OrdinalIgnoreCase)
            .Select(g => g.First())
            .OrderBy(p => p.Manufacturer)
            .ThenBy(p => p.Name)
            .ToList();
    }

    public static DeviceSlot ToDeviceSlot(Vst3PluginInfo plugin)
    {
        var slot = DeviceSlot.Vst3(plugin.Name, plugin.Path);
        slot.PluginManufacturer = plugin.Manufacturer;
        return slot;
    }

    public static bool TryOpenEditor(DeviceSlot slot, IWin32Window? owner, Action<string>? log = null)
    {
        if (!slot.IsVst3 || string.IsNullOrWhiteSpace(slot.PluginPath))
        {
            MessageBox.Show(owner, "This device is not a VST3 slot.", "LemmingsStudio", MessageBoxButtons.OK, MessageBoxIcon.Information);
            return false;
        }
        if (!File.Exists(slot.PluginPath) && !Directory.Exists(slot.PluginPath))
        {
            MessageBox.Show(owner, $"The VST3 path no longer exists:\n\n{slot.PluginPath}", "Missing VST3", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return false;
        }

        Vst3NativeHostBridge.Shared.Log += m => log?.Invoke(m);
        if (Vst3NativeHostBridge.Shared.TryOpenEditor(slot, owner))
        {
            log?.Invoke($"Opened native VST3 editor request: {slot.Name}");
            return true;
        }

        var host = FindExternalHost();
        if (host != null)
        {
            try
            {
                var psi = new ProcessStartInfo
                {
                    FileName = host.Path,
                    UseShellExecute = true,
                    WorkingDirectory = Path.GetDirectoryName(host.Path) ?? Environment.CurrentDirectory,
                    Arguments = string.Join(" ", host.Args(slot.PluginPath!).Select(QuoteArg))
                };
                Process.Start(psi);
                slot.EditorBridge = host.Name;
                slot.NativeHostStatus = "External editor bridge only";
                log?.Invoke($"Opened VST3 editor bridge via {host.Name}: {slot.Name}");
                return true;
            }
            catch (Exception ex)
            {
                log?.Invoke($"VST3 editor bridge failed: {ex.Message}");
                MessageBox.Show(owner, ex.Message, "VST3 Editor Bridge Failed", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return false;
            }
        }

        var result = MessageBox.Show(owner,
            "LemmingsStudio found the VST3, but the native VST3 helper is not bundled/running and no external VST3 editor host was found yet.\n\n" +
            "Native helper expected: " + Vst3NativeHostBridge.Shared.HostPath + "\n\n" +
            "Install Carla or Element, set LEMMINGS_VST3_HOST to a host executable, or set LEMMINGS_VST3_NATIVE_HOST to a native Lemmings VST3 helper.\n\n" +
            "Open the plug-in location in Explorer?",
            "VST3 Host Needed",
            MessageBoxButtons.YesNo,
            MessageBoxIcon.Information);
        if (result == DialogResult.Yes)
        {
            try
            {
                var target = Directory.Exists(slot.PluginPath) ? slot.PluginPath : Path.GetDirectoryName(slot.PluginPath!);
                if (!string.IsNullOrWhiteSpace(target)) Process.Start("explorer.exe", $"\"{target}\"");
            }
            catch { }
        }
        return false;
    }

    private static IEnumerable<string> CandidateRoots()
    {
        string pf = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles);
        string pf86 = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86);
        string appData = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
        string local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        yield return Path.Combine(pf, "Common Files", "VST3");
        yield return Path.Combine(pf86, "Common Files", "VST3");
        yield return Path.Combine(appData, "VST3");
        yield return Path.Combine(local, "Programs", "Common", "VST3");
        var extra = Environment.GetEnvironmentVariable("LEMMINGS_VST3_PATHS");
        if (!string.IsNullOrWhiteSpace(extra))
            foreach (var part in extra.Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
                yield return part;
    }

    private static string GuessManufacturer(string path, string root)
    {
        try
        {
            var rel = Path.GetRelativePath(root, path);
            var first = rel.Split(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar).FirstOrDefault();
            if (!string.IsNullOrWhiteSpace(first) && !first.EndsWith(".vst3", StringComparison.OrdinalIgnoreCase)) return first;
        }
        catch { }
        return "VST3";
    }

    private static string QuoteArg(string arg) => "\"" + arg.Replace("\"", "\\\"") + "\"";

    private sealed record ExternalHost(string Name, string Path, Func<string, IEnumerable<string>> Args);

    private static ExternalHost? FindExternalHost()
    {
        var env = Environment.GetEnvironmentVariable("LEMMINGS_VST3_HOST");
        if (!string.IsNullOrWhiteSpace(env) && File.Exists(env))
            return new ExternalHost("Custom host", env, p => new[] { p });

        var candidates = new[]
        {
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "Carla", "Carla.exe"),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "Carla", "carla.exe"),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "Element", "Element.exe"),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), "Carla", "Carla.exe"),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), "Element", "Element.exe"),
        };
        foreach (var c in candidates)
            if (File.Exists(c)) return new ExternalHost(Path.GetFileNameWithoutExtension(c), c, p => new[] { p });
        return null;
    }
}

public sealed class Vst3PluginInfo
{
    public string Name { get; set; } = "Plugin";
    public string Manufacturer { get; set; } = "VST3";
    public string Path { get; set; } = "";
    public bool IsBundleDirectory { get; set; }
    public override string ToString() => string.IsNullOrWhiteSpace(Manufacturer) || Manufacturer == "VST3" ? Name : $"{Manufacturer} — {Name}";
}
