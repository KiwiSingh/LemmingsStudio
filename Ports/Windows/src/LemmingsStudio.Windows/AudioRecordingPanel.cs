namespace LemmingsStudio.Windows;

public sealed class AudioRecordingPanel : UserControl
{
    private readonly RecordingService recorder = new();
    private readonly ComboBox inputBox = new() { DropDownStyle = ComboBoxStyle.DropDownList, Width = 260 };
    private readonly ComboBox driverBox = new() { DropDownStyle = ComboBoxStyle.DropDownList, Width = 134 };
    private readonly ComboBox monitorMode = new() { DropDownStyle = ComboBoxStyle.DropDownList, Width = 138 };
    private readonly ComboBox trackBox = new() { DropDownStyle = ComboBoxStyle.DropDownList, Width = 240 };
        private readonly CheckBox countIn = new() { Text = "Count-in", AutoSize = true, Checked = true };
    private readonly NumericUpDown countBars = new() { Minimum = 0, Maximum = 8, Value = 1, Width = 54 };
    private readonly NumericUpDown startBeat = new() { Minimum = 0, Maximum = 10000, DecimalPlaces = 2, Increment = 0.25M, Width = 74 };
    private readonly NumericUpDown latencyMs = new() { Minimum = 0, Maximum = 1000, Value = 40, Width = 70 };
    private readonly ProgressBar level = new() { Width = 160, Height = 18, Minimum = 0, Maximum = 100 };
    private readonly Button recordButton = new() { Text = "● Record", Width = 92 };
    private readonly Button stopButton = new() { Text = "■ Stop", Width = 80, Enabled = false };
    private readonly TextBox log = new() { Dock = DockStyle.Fill, Multiline = true, ReadOnly = true, ScrollBars = ScrollBars.Vertical, Font = new Font("Consolas", 9) };
    private readonly System.Windows.Forms.Timer elapsedTimer = new() { Interval = 250 };
    private DateTime clipStartUtc;
    private double requestedStartBeat;
    private Track? targetTrack;
    private string? activePath;
    private bool waitingForCountIn;

    public StudioProject? Project { get; set; }
    public Func<string?>? ProjectPathProvider { get; set; }
    public Action? Changed;
    public Action<string>? ExternalLog;

    public AudioRecordingPanel()
    {
        Dock = DockStyle.Fill;
        var top = new FlowLayoutPanel { Dock = DockStyle.Top, Height = 96, Padding = new Padding(8), AutoSize = false };
        var refresh = new Button { Text = "Refresh Inputs" };
        top.Controls.Add(new Label { Text = "Driver", AutoSize = true, Padding = new Padding(0, 8, 4, 0) });
        top.Controls.Add(driverBox);
        top.Controls.Add(new Label { Text = "Input", AutoSize = true, Padding = new Padding(8, 8, 4, 0) });
        top.Controls.Add(inputBox);
        top.Controls.Add(refresh);
        top.Controls.Add(new Label { Text = "Track", AutoSize = true, Padding = new Padding(18, 8, 4, 0) });
        top.Controls.Add(trackBox);
        top.Controls.Add(new Label { Text = "Monitor", AutoSize = true, Padding = new Padding(18, 8, 4, 0) });
        top.Controls.Add(monitorMode);
        top.Controls.Add(countIn);
        top.Controls.Add(new Label { Text = "Bars", AutoSize = true, Padding = new Padding(2, 8, 2, 0) });
        top.Controls.Add(countBars);
        top.Controls.Add(new Label { Text = "Start beat", AutoSize = true, Padding = new Padding(18, 8, 4, 0) });
        top.Controls.Add(startBeat);
        top.Controls.Add(new Label { Text = "Latency ms", AutoSize = true, Padding = new Padding(18, 8, 4, 0) });
        top.Controls.Add(latencyMs);
        top.Controls.Add(recordButton);
        top.Controls.Add(stopButton);
        top.Controls.Add(new Label { Text = "Level", AutoSize = true, Padding = new Padding(12, 8, 4, 0) });
        top.Controls.Add(level);
        Controls.Add(log);
        Controls.Add(top);

        driverBox.Items.AddRange(new object[] { "WinMM", "WASAPI shared", "WASAPI exclusive" });
        driverBox.SelectedIndex = 1;
        monitorMode.Items.AddRange(new object[] { "Off", "Software", "Hardware/direct" });
        monitorMode.SelectedIndex = 0;

        recorder.Log += Append;
        recorder.LevelChanged += p => BeginInvoke((Action)(() => level.Value = Math.Clamp((int)Math.Round(p * 100), 0, 100)));
        refresh.Click += (_, _) => ReloadInputs();
        driverBox.SelectedIndexChanged += (_, _) => ReloadInputs();
        recordButton.Click += async (_, _) => await StartRecordingAsync();
        stopButton.Click += (_, _) => StopRecording();
        elapsedTimer.Tick += (_, _) => { if (recorder.IsRecording) recordButton.Text = $"● {recorder.Elapsed:mm\\:ss}"; };
        ReloadInputs();
    }

    public void Reload()
    {
        var previous = trackBox.SelectedIndex;
        trackBox.Items.Clear();
        if (Project != null)
        {
            foreach (var t in Project.Tracks.Where(t => t.Type == TrackType.Audio || t.Armed))
                trackBox.Items.Add(t);
            if (trackBox.Items.Count == 0)
                foreach (var t in Project.Tracks) trackBox.Items.Add(t);
        }
        if (trackBox.Items.Count > 0) trackBox.SelectedIndex = Math.Clamp(previous < 0 ? 0 : previous, 0, trackBox.Items.Count - 1);
    }

    private void ReloadInputs()
    {
        inputBox.Items.Clear();
        foreach (var n in recorder.Inputs(SelectedBackend())) inputBox.Items.Add(n);
        if (inputBox.Items.Count > 0 && inputBox.SelectedIndex < 0) inputBox.SelectedIndex = 0;
        Append($"Audio inputs refreshed: {inputBox.Items.Count} input(s) via {SelectedBackend()}.");
    }

    private async Task StartRecordingAsync()
    {
        if (Project == null) { Append("No project loaded."); return; }
        if (inputBox.SelectedIndex < 0) { Append("No audio input selected."); return; }
        targetTrack = trackBox.SelectedItem as Track;
        if (targetTrack == null)
        {
            targetTrack = Track.Audio("Audio " + (Project.Tracks.Count + 1));
            Project.Tracks.Add(targetTrack);
        }
        if (targetTrack.Type != TrackType.Audio)
            Append($"Recording audio onto '{targetTrack.Name}' even though it is a {targetTrack.Type} track.");

        requestedStartBeat = (double)startBeat.Value;
        var bars = countIn.Checked ? (int)countBars.Value : 0;
        if (bars > 0)
        {
            waitingForCountIn = true;
            recordButton.Enabled = false;
            Append($"Count-in: {bars} bar(s). Recording starts after {bars * Math.Max(1, Project.BeatsPerBar)} beat(s).");
            await Task.Delay(TimeSpan.FromSeconds((bars * Math.Max(1, Project.BeatsPerBar)) * 60.0 / Math.Max(1.0, Project.Tempo)));
            waitingForCountIn = false;
            if (!recordButton.IsHandleCreated || IsDisposed) return;
        }

        try
        {
            var path = MakeRecordingPath(Project);
            activePath = recorder.Start(SelectedBackend(), inputBox.SelectedIndex, path, SelectedMonitoringMode(), monitorLatencyMs: Math.Max(10, (int)latencyMs.Value));
            clipStartUtc = DateTime.UtcNow;
            recordButton.Text = "● 00:00";
            recordButton.Enabled = false;
            stopButton.Enabled = true;
            elapsedTimer.Start();
        }
        catch (Exception ex)
        {
            recordButton.Enabled = true;
            waitingForCountIn = false;
            Append("Audio recording failed: " + ex.Message);
        }
    }

    private void StopRecording()
    {
        if (waitingForCountIn)
        {
            waitingForCountIn = false;
            recordButton.Enabled = true;
            Append("Count-in cancelled.");
            return;
        }
        var path = recorder.Stop() ?? activePath;
        elapsedTimer.Stop();
        recordButton.Text = "● Record";
        recordButton.Enabled = true;
        stopButton.Enabled = false;
        level.Value = 0;
        if (Project == null || targetTrack == null || string.IsNullOrWhiteSpace(path) || !File.Exists(path)) return;

        var seconds = Math.Max(0.05, (DateTime.UtcNow - clipStartUtc).TotalSeconds);
        var lengthBeats = seconds * Math.Max(1.0, Project.Tempo) / 60.0;
        var latencyBeats = ((double)latencyMs.Value / 1000.0) * Math.Max(1.0, Project.Tempo) / 60.0;
        var clip = new ProjectClip
        {
            Type = ClipType.Audio,
            Name = "Audio Take " + (targetTrack.Clips.Count + 1),
            SourcePath = path,
            StartBeat = Math.Max(0.0, requestedStartBeat - latencyBeats),
            LengthBeats = Math.Max(0.25, lengthBeats),
            SourceTempo = Project.Tempo,
            WarpEnabled = false
        };
        targetTrack.Clips.Add(clip);
        targetTrack.Armed = false;
        Append($"Added recorded clip '{clip.Name}' to {targetTrack.Name} at beat {clip.StartBeat:0.##}, length {clip.LengthBeats:0.##} beat(s).");
        Changed?.Invoke();
    }

    private string MakeRecordingPath(StudioProject project)
    {
        string root;
        var projectPath = ProjectPathProvider?.Invoke();
        if (!string.IsNullOrWhiteSpace(projectPath))
            root = Path.Combine(Path.GetDirectoryName(projectPath)!, "Media", "Recordings");
        else
            root = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments), "LemmingsStudio", "Recordings", Sanitize(project.Name));
        Directory.CreateDirectory(root);
        return Path.Combine(root, $"{DateTime.Now:yyyyMMdd-HHmmss}-audio-take.wav");
    }

    private static string Sanitize(string name)
    {
        foreach (var ch in Path.GetInvalidFileNameChars()) name = name.Replace(ch, '_');
        return string.IsNullOrWhiteSpace(name) ? "Untitled" : name;
    }

    private AudioInputBackend SelectedBackend() => driverBox.SelectedIndex switch
    {
        0 => AudioInputBackend.WinMM,
        2 => AudioInputBackend.WasapiExclusive,
        _ => AudioInputBackend.WasapiShared
    };

    private InputMonitoringMode SelectedMonitoringMode() => monitorMode.SelectedIndex switch
    {
        1 => InputMonitoringMode.Software,
        2 => InputMonitoringMode.HardwareDirect,
        _ => InputMonitoringMode.Off
    };

    private void Append(string msg)
    {
        if (IsDisposed) return;
        var line = $"[{DateTime.Now:HH:mm:ss}] {msg}\r\n";
        if (InvokeRequired) BeginInvoke((Action)(() => Append(msg)));
        else { log.AppendText(line); ExternalLog?.Invoke(msg); }
    }
}
