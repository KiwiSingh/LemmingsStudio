using System.Text;

namespace LemmingsStudio.Windows;

public sealed class WindowsParityDiagnosticsForm : Form
{
    private readonly StudioProject project;
    private readonly AudioEngine engine;
    private readonly Action<string> log;
    private readonly TextBox output = new() { Multiline = true, ReadOnly = true, ScrollBars = ScrollBars.Vertical, Dock = DockStyle.Fill, Font = new Font("Consolas", 9f) };
    private readonly Button run = new() { Text = "Run render/export smoke tests", Dock = DockStyle.Top, Height = 36 };
    private readonly Button copy = new() { Text = "Copy diagnostics", Dock = DockStyle.Bottom, Height = 34 };

    public WindowsParityDiagnosticsForm(StudioProject project, AudioEngine engine, Action<string> log)
    {
        this.project = project;
        this.engine = engine;
        this.log = log;
        Text = "Windows Parity Diagnostics";
        StartPosition = FormStartPosition.CenterParent;
        Width = 860;
        Height = 620;
        Controls.Add(output);
        Controls.Add(run);
        Controls.Add(copy);
        run.Click += async (_, _) => await RunAsync();
        copy.Click += (_, _) => Clipboard.SetText(output.Text);
        WriteStaticSummary();
    }

    private void WriteStaticSummary()
    {
        var sb = new StringBuilder();
        sb.AppendLine("LemmingsStudio Windows parity diagnostics");
        sb.AppendLine($"Built runtime: {DetectBuildRuntimeText()}");
        sb.AppendLine($"Process architecture: {System.Runtime.InteropServices.RuntimeInformation.ProcessArchitecture}");
        sb.AppendLine($"OS: {Environment.OSVersion}");
        sb.AppendLine($"Refresh rate detected: {DisplayRefreshRateDetector.DetectPrimaryRefreshRate(60)} Hz");
        sb.AppendLine($"Native VST3 host: {Vst3NativeHostBridge.Shared.StatusText}");
        sb.AppendLine($"Native VST3 host crash count: {Vst3NativeHostBridge.Shared.CrashCount}");
        sb.AppendLine($"ffmpeg: {FindTool(\"ffmpeg.exe\") ?? FindTool(\"ffmpeg\") ?? \"not found\"}");
        sb.AppendLine();
        sb.AppendLine("Project summary:");
        sb.AppendLine($"  Tempo: {project.Tempo:0.##} BPM");
        sb.AppendLine($"  Tracks: {project.Tracks.Count}");
        sb.AppendLine($"  Audio clips: {project.Tracks.Sum(t => t.Clips.Count(c => c.Type == ClipType.Audio))}");
        sb.AppendLine($"  MIDI clips: {project.Tracks.Sum(t => t.Clips.Count(c => c.Type == ClipType.Midi))}");
        sb.AppendLine($"  Step sequencer tracks: {project.Tracks.Count(t => t.UseStepSequencer)}");
        sb.AppendLine($"  VST3 devices: {project.Tracks.SelectMany(t => t.Devices).Count(d => d.IsVst3)}");
        var health = ProjectHealthService.Audit(project);
        sb.AppendLine();
        sb.AppendLine("Project health:");
        sb.AppendLine(health.Summary());
        sb.AppendLine();
        sb.AppendLine(StartupSanityService.Run());
        output.Text = sb.ToString();
    }

    private static string DetectBuildRuntimeText()
    {
        try
        {
            var path = Path.Combine(AppContext.BaseDirectory, "windows-build-manifest.json");
            return File.Exists(path) ? File.ReadAllText(path) : "manifest not found";
        }
        catch (Exception ex) { return "manifest read failed: " + ex.Message; }
    }

    private static string? FindTool(string name)
    {
        var local = Path.Combine(AppContext.BaseDirectory, name);
        if (File.Exists(local)) return local;
        var paths = (Environment.GetEnvironmentVariable("PATH") ?? "").Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries);
        foreach (var p in paths)
        {
            try { var candidate = Path.Combine(p.Trim(), name); if (File.Exists(candidate)) return candidate; } catch { }
        }
        return null;
    }

    private async Task RunAsync()
    {
        run.Enabled = false;
        try
        {
            await Task.Run(() =>
            {
                var dir = Path.Combine(Path.GetTempPath(), "LemmingsStudioDiagnostics", DateTime.UtcNow.ToString("yyyyMMdd_HHmmss"));
                Directory.CreateDirectory(dir);
                Append($"Smoke-test output folder: {dir}");
                var mix = engine.Render(project);
                var seconds = mix.Length / (double)(AudioEngine.SampleRate * AudioEngine.Channels);
                var peak = mix.Length == 0 ? 0 : mix.Max(v => Math.Abs(v));
                Append($"Render: {seconds:0.00}s, peak {20.0 * Math.Log10(Math.Max(peak, 0.000001)):0.0} dBFS, samples {mix.Length}");

                TestExport(dir, "smoke.wav", new ExportSettings { Format = ExportFormat.Wav, BitDepth = 24 });
                TestExport(dir, "smoke.aiff", new ExportSettings { Format = ExportFormat.Aiff, BitDepth = 24 });
                TestExport(dir, "smoke.mp3", new ExportSettings { Format = ExportFormat.Mp3, Mp3Bitrate = 320 });
                TestExport(dir, "smoke.flac", new ExportSettings { Format = ExportFormat.Flac, FlacCompression = 5 });
            });
        }
        finally { run.Enabled = true; }
    }

    private void TestExport(string dir, string name, ExportSettings settings)
    {
        try
        {
            var path = Path.Combine(dir, name);
            engine.Export(project, path, settings);
            var info = new FileInfo(path);
            Append($"PASS export {settings.Describe()} → {info.Length:n0} bytes");
        }
        catch (Exception ex)
        {
            Append($"FAIL export {settings.Describe()}: {ex.GetType().Name}: {ex.Message}");
        }
    }

    private void Append(string line)
    {
        if (InvokeRequired) { BeginInvoke((Action)(() => Append(line))); return; }
        output.AppendText(line + Environment.NewLine);
        log(line);
    }
}
