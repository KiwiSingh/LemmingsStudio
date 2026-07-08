using System.Diagnostics;
using System.Media;

namespace LemmingsStudio.Windows;

public sealed class MainForm : Form
{
    private readonly StudioProject project = StudioProject.New();
    private readonly ArrangementCanvas arrangement = new() { Dock = DockStyle.Fill };
    private readonly TextBox logBox = new() { Multiline = true, ReadOnly = true, ScrollBars = ScrollBars.Vertical, Dock = DockStyle.Fill, Font = new Font("Consolas", 9) };
    private readonly TreeView browserTree = new() { Dock = DockStyle.Fill };
    private readonly Features.MixerPanel mixerPanel = new();
    private readonly ListView automationList = new() { Dock = DockStyle.Fill, View = View.Details, FullRowSelect = true };
    private readonly ClipInspectorPanel inspector = new() { Dock = DockStyle.Fill };
    private readonly SessionLauncherPanel sessionLauncher = new();
    private readonly Features.DeviceRackPanel deviceRack = new();
    private readonly MidiHardwarePanel midiPanel = new();
    private readonly AudioRecordingPanel audioRecordingPanel = new();
    private readonly StepSequencerPanel stepSequencer = new();
    private readonly PianoRollPanel pianoRoll = new();
    private readonly Features.AIPanel aiPanel = new();
    private readonly Features.SplicePanel splicePanel = new();
    private readonly StatusStrip status = new();
    private readonly ToolStripStatusLabel statusLabel = new("Ready");
    private readonly ToolStripProgressBar progress = new() { Visible = false, Minimum = 0, Maximum = 100 };
    private readonly BackendRunner runner = new();
    private readonly UserLibraryScanner scanner = new();
    private readonly AudioEngine engine = new();
    private readonly HardwareDetector detector = new();
    private string selectedBackend = "directml";
    private readonly string buildRuntime = DetectBuildRuntime();
    private ToolStripButton? playButton;
    private ToolStripButton? metronomeButton;
    private ToolStripLabel? tempoLabel;
    private string? projectPath;
    private CancellationTokenSource? scanCts;
    private readonly ProjectRecoveryService recovery = new();
    private readonly System.Windows.Forms.Timer autosaveTimer = new() { Interval = 60_000 };
    private readonly List<string> recentLogs = new();

    public MainForm()
    {
        Text = "Untitled — LemmingsStudio Windows";
        Width = 1320;
        Height = 860;
        MinimumSize = new Size(1024, 680);
        arrangement.Project = project;
        arrangement.ProjectChanged += () => { recovery.MarkDirty(); RefreshAll(); };
        arrangement.ClipSelectionChanged += clip => inspector.Reload(clip);
        arrangement.Log += AppendLog;
        runner.Log += AppendLog;
        scanner.BatchReady += OnScannerBatch;
        scanner.Status += s => BeginInvoke((Action)(() => SetStatus(s)));
        engine.Log += AppendLog;
        aiPanel.Log = AppendLog;
        aiPanel.SelectedClipProvider = () => arrangement.PrimarySelection;
        engine.PlaybackStopped += () => BeginInvoke((Action)(() => { if (playButton != null) playButton.Text = "▶ Play"; SetStatus("Playback finished"); }));
        MidiService.Shared.ControlChange += OnMidiControlChange;
        Vst3NativeHostBridge.Shared.Log += AppendLog;
        Vst3NativeHostBridge.Shared.HostCrashed += () => BeginInvoke((Action)(() =>
        {
            SetStatus("Native VST3 host crashed — restart available in Tools");
            AppendLog("Native VST3 helper crash detected. Stale plug-in hydration state was cleared for safe restart.");
        }));
        AppPaths.EnsureFirstRunFolders();
        autosaveTimer.Tick += (_, _) => RunAutosave();
        autosaveTimer.Start();

        BackColor = Color.FromArgb(18, 20, 26);
        Controls.Add(BuildShell());
        Controls.Add(BuildTransport());
        Controls.Add(BuildMenu());
        status.Items.Add(statusLabel);
        status.Items.Add(progress);
        Controls.Add(status);

        RefreshAll();
        AppendLog("Windows feature-parity port loaded. Startup sound, Arrangement, Session Launcher, Step Sequencer, Piano Roll, Devices, Mixer, Automation, Splice and agent panels are active parity targets.");
        AppendLog(Vst3NativeHostBridge.Shared.StatusText);
        AppendLog(StartupSanityService.Run());
        _ = DetectHardwareAsync(initial: true);
        Shown += (_, _) => OfferRecoveryIfAvailable();
    }



    private void OnMidiControlChange(int channel, int controller, int value)
    {
        bool changed = false;
        double norm = Math.Clamp(value / 127.0, 0.0, 1.0);
        foreach (var track in project.Tracks)
        {
            foreach (var device in track.Devices)
            {
                foreach (var map in device.MidiMappings.ToList())
                {
                    var m = map.Value;
                    if (m.Controller == controller && (m.Channel == 0 || m.Channel == channel))
                    {
                        device.Parameters[map.Key] = m.Minimum + norm * (m.Maximum - m.Minimum);
                        changed = true;
                    }
                }
            }
        }
        if (changed) BeginInvoke((Action)(() => { deviceRack.Reload(); SetStatus($"MIDI CC {controller} updated mapped parameter(s)"); }));
    }

    private static string DetectBuildRuntime()
    {
        try
        {
            var manifest = Path.Combine(AppContext.BaseDirectory, "windows-build-manifest.json");
            if (File.Exists(manifest))
            {
                var text = File.ReadAllText(manifest);
                if (text.Contains("\"win-arm64\"", StringComparison.OrdinalIgnoreCase)) return "win-arm64";
                if (text.Contains("\"win-x64\"", StringComparison.OrdinalIgnoreCase)) return "win-x64";
            }
        }
        catch { }
        return System.Runtime.InteropServices.RuntimeInformation.ProcessArchitecture == System.Runtime.InteropServices.Architecture.Arm64 ? "win-arm64" : "win-x64";
    }

    private async Task DetectHardwareAsync(bool initial)
    {
        var info = await detector.DetectAsync();
        selectedBackend = info.Recommended;
        AppendLog("Hardware: " + info.Summary);
        SetStatus($"Backend auto-selected: {selectedBackend}");
        if (!initial)
            MessageBox.Show(this, info.Summary, "Detected Hardware", MessageBoxButtons.OK, MessageBoxIcon.Information);
    }

    private Control BuildMenu()
    {
        var menu = new MenuStrip();
        var file = new ToolStripMenuItem("File");
        file.DropDownItems.Add("New", null, (_, _) => NewProject());
        file.DropDownItems.Add("Open…", null, (_, _) => OpenProject());
        file.DropDownItems.Add("Save", null, (_, _) => SaveProject(false));
        file.DropDownItems.Add("Save As…", null, (_, _) => SaveProject(true));
        file.DropDownItems.Add("Relink Missing Media…", null, (_, _) => RelinkMissingMedia());
        file.DropDownItems.Add("Export Audio…", null, (_, _) => ExportAudio());
        file.DropDownItems.Add(new ToolStripSeparator());
        file.DropDownItems.Add("Exit", null, (_, _) => Close());

        var projectMenu = new ToolStripMenuItem("Project");
        projectMenu.DropDownItems.Add("Set Tempo…", null, (_, _) => SetTempo());
        projectMenu.DropDownItems.Add("Set Key…", null, (_, _) => SetKey());
        projectMenu.DropDownItems.Add("Add Audio Track", null, (_, _) => { project.Tracks.Add(Track.Audio("Audio " + (project.Tracks.Count + 1))); recovery.MarkDirty(); RefreshAll(); });
        projectMenu.DropDownItems.Add("Add Instrument Track", null, (_, _) => { project.Tracks.Add(Track.Instrument("Instrument " + (project.Tracks.Count + 1))); recovery.MarkDirty(); RefreshAll(); });
        projectMenu.DropDownItems.Add("Add MIDI Track", null, (_, _) => { var t = Track.Instrument("MIDI " + (project.Tracks.Count + 1)); t.Type = TrackType.Midi; project.Tracks.Add(t); recovery.MarkDirty(); RefreshAll(); });
        projectMenu.DropDownItems.Add("Add Sequencer Track", null, (_, _) => { var t = Track.Instrument("Sequencer " + (project.Tracks.Count + 1)); t.UseStepSequencer = true; t.Devices.Clear(); t.Devices.Add(DeviceSlot.Stock("Drum Machine")); project.Tracks.Add(t); recovery.MarkDirty(); RefreshAll(); });
        projectMenu.DropDownItems.Add(new ToolStripSeparator());
        projectMenu.DropDownItems.Add("Bounce Selected Clip", null, (_, _) => RunBounceSelected());
        projectMenu.DropDownItems.Add("Consolidate Selected Clips", null, (_, _) => RunConsolidateSelected());
        projectMenu.DropDownItems.Add("Freeze Selected Track", null, (_, _) => RunFreezeSelectedTrack());
        projectMenu.DropDownItems.Add("Unfreeze Selected Track", null, (_, _) => RunUnfreezeSelectedTrack());
        projectMenu.DropDownItems.Add("Flatten Selected Track", null, (_, _) => RunFlattenSelectedTrack());

        var tools = new ToolStripMenuItem("Tools");
        tools.DropDownItems.Add("Detect Hardware…", null, async (_, _) => await DetectHardwareAsync(initial: false));
        tools.DropDownItems.Add(new ToolStripSeparator());
        tools.DropDownItems.Add("Install / Repair DirectML Backend (AMD/Intel/any GPU)", null, async (_, _) => await RunBackendSetup("directml"));
        tools.DropDownItems.Add("Install / Repair CUDA Backend (NVIDIA)", null, async (_, _) => await RunBackendSetup("cuda"));
        tools.DropDownItems.Add("Install / Repair OpenVINO Backend (Intel)", null, async (_, _) => await RunBackendSetup("openvino"));
        tools.DropDownItems.Add("Install / Repair QNN Backend (ARM NPU)", null, async (_, _) => await RunBackendSetup("qnn"));
        tools.DropDownItems.Add("Install / Repair CPU Backend (always works)", null, async (_, _) => await RunBackendSetup("cpu"));
        tools.DropDownItems.Add(new ToolStripSeparator());
        tools.DropDownItems.Add("Stem Split Selected Clip…", null, async (_, _) => await StemSplitSelectedClip());
        tools.DropDownItems.Add("Scan User Library…", null, (_, _) => ChooseAndScanLibrary());
        tools.DropDownItems.Add("Scan VST3 Plug-ins", null, (_, _) => { var count = Vst3PluginService.Scan(AppendLog).Count; AppendLog($"VST3 scan complete: {count} plug-in(s) found. Add them from the Devices tab."); });
        tools.DropDownItems.Add("Start Native VST3 Host", null, (_, _) =>
        {
            if (Vst3NativeHostBridge.Shared.EnsureStarted(this))
                AppendLog(Vst3NativeHostBridge.Shared.StatusText);
            else
                MessageBox.Show(this, Vst3NativeHostBridge.Shared.LastError.Length == 0 ? Vst3NativeHostBridge.Shared.StatusText : Vst3NativeHostBridge.Shared.LastError, "Native VST3 Host", MessageBoxButtons.OK, MessageBoxIcon.Information);
        });
        tools.DropDownItems.Add("Restart Native VST3 Host", null, (_, _) =>
        {
            var ok = Vst3NativeHostBridge.Shared.Restart(this);
            AppendLog(ok ? "Native VST3 host restarted." : "Native VST3 host restart failed: " + Vst3NativeHostBridge.Shared.LastError);
            SetStatus(ok ? "Native VST3 host restarted" : "VST3 host restart failed");
        });
        tools.DropDownItems.Add("Windows Parity Diagnostics…", null, (_, _) => new WindowsParityDiagnosticsForm(project, engine, AppendLog).Show(this));
        tools.DropDownItems.Add("Export Diagnostics Bundle…", null, (_, _) => ExportDiagnosticsBundle());

        menu.Items.Add(file);
        menu.Items.Add(projectMenu);
        menu.Items.Add(tools);
        MainMenuStrip = menu;
        return menu;
    }

    private Control BuildTransport()
    {
        var bar = new ToolStrip { Dock = DockStyle.Top, GripStyle = ToolStripGripStyle.Hidden, RenderMode = ToolStripRenderMode.System };
        playButton = new ToolStripButton("▶ Play") { DisplayStyle = ToolStripItemDisplayStyle.Text };
        playButton.Click += (_, _) => TogglePlay();
        var stop = new ToolStripButton("■ Stop") { DisplayStyle = ToolStripItemDisplayStyle.Text };
        stop.Click += (_, _) => StopPlayback();
        var export = new ToolStripButton("Export WAV") { DisplayStyle = ToolStripItemDisplayStyle.Text };
        export.Click += (_, _) => ExportAudio();
        metronomeButton = new ToolStripButton("○ Metro") { DisplayStyle = ToolStripItemDisplayStyle.Text, CheckOnClick = true };
        metronomeButton.CheckedChanged += (_, _) => { project.MetronomeEnabled = metronomeButton.Checked; metronomeButton.Text = project.MetronomeEnabled ? "● Metro" : "○ Metro"; SetStatus(project.MetronomeEnabled ? "Metronome on" : "Metronome off"); };
        tempoLabel = new ToolStripLabel();
        var tempoEdit = new ToolStripButton("Tempo") { DisplayStyle = ToolStripItemDisplayStyle.Text };
        tempoEdit.Click += (_, _) => SetTempo();
        var keyEdit = new ToolStripButton("Key") { DisplayStyle = ToolStripItemDisplayStyle.Text };
        keyEdit.Click += (_, _) => SetKey();

        bar.Items.Add(playButton);
        bar.Items.Add(stop);
        bar.Items.Add(metronomeButton);
        bar.Items.Add(new ToolStripSeparator());
        bar.Items.Add(export);
        bar.Items.Add(new ToolStripSeparator());
        bar.Items.Add(tempoLabel);
        bar.Items.Add(tempoEdit);
        bar.Items.Add(keyEdit);
        bar.Items.Add(new ToolStripSeparator());

        bar.Items.Add(new ToolStripLabel("Latency:"));
        var latency = new ToolStripComboBox { DropDownStyle = ComboBoxStyle.DropDownList, AutoSize = false, Width = 90 };
        latency.Items.AddRange(new object[] { "50 ms", "100 ms", "150 ms", "200 ms", "300 ms" });
        latency.SelectedIndex = 3; // 200 ms default
        latency.SelectedIndexChanged += (_, _) =>
        {
            engine.OutputLatencyMs = new[] { 50, 100, 150, 200, 300 }[latency.SelectedIndex];
            SetStatus($"Output latency: {engine.OutputLatencyMs} ms (applies on next Play)");
        };
        bar.Items.Add(latency);
        return bar;
    }

    private void TogglePlay()
    {
        if (engine.IsPlaying) { StopPlayback(); return; }
        try
        {
            SetStatus("Rendering & playing…");
            engine.Play(project);
            if (playButton != null) playButton.Text = "❚❚ Pause";
            SetStatus("Playing");
        }
        catch (Exception ex)
        {
            AppendLog("Playback failed: " + ex.Message);
            MessageBox.Show(this, ex.Message, "Playback", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }

    private void StopPlayback()
    {
        engine.Stop();
        if (playButton != null) playButton.Text = "▶ Play";
        SetStatus("Stopped");
    }

    private Control BuildShell()
    {
        var root = new SplitContainer { Dock = DockStyle.Fill, Orientation = Orientation.Vertical, SplitterDistance = 250 };
        var tabs = new TabControl { Dock = DockStyle.Fill };
        tabs.TabPages.Add(new TabPage("Arrangement") { Controls = { arrangement } });
        tabs.TabPages.Add(new TabPage("Session") { Controls = { sessionLauncher } });
        tabs.TabPages.Add(new TabPage("Step Sequencer") { Controls = { stepSequencer } });
        tabs.TabPages.Add(new TabPage("Piano Roll") { Controls = { pianoRoll } });
        tabs.TabPages.Add(new TabPage("Devices") { Controls = { deviceRack } });
        tabs.TabPages.Add(new TabPage("Mixer") { Controls = { mixerPanel } });
        tabs.TabPages.Add(new TabPage("Automation") { Controls = { BuildAutomationPanel() } });
        tabs.TabPages.Add(new TabPage("Audio Recording") { Controls = { audioRecordingPanel } });
        tabs.TabPages.Add(new TabPage("MIDI / Hardware") { Controls = { midiPanel } });
        tabs.TabPages.Add(new TabPage("AI") { Controls = { aiPanel } });
        tabs.TabPages.Add(new TabPage("Splice") { Controls = { splicePanel } });
        tabs.TabPages.Add(new TabPage("Log") { Controls = { logBox } });
        root.Panel1.Controls.Add(BuildBrowserPanel());
        root.Panel2.Controls.Add(tabs);

        var outer = new SplitContainer { Dock = DockStyle.Fill, Orientation = Orientation.Horizontal, SplitterDistance = 590 };
        outer.Panel1.Controls.Add(root);
        outer.Panel2.Controls.Add(inspector);
        return outer;
    }

    private Control BuildBrowserPanel()
    {
        var panel = new Panel { Dock = DockStyle.Fill };
        var header = new FlowLayoutPanel { Dock = DockStyle.Top, Height = 42, Padding = new Padding(6) };
        var scan = new Button { Text = "Scan Library…" };
        scan.Click += (_, _) => ChooseAndScanLibrary();
        header.Controls.Add(new Label { Text = "Browser", AutoSize = true, Padding = new Padding(0, 7, 8, 0) });
        var addSeq = new Button { Text = "Add Sequencer" };
        addSeq.Click += (_, _) => { var t = Track.Instrument("Sequencer " + (project.Tracks.Count + 1)); t.UseStepSequencer = true; t.Devices.Clear(); t.Devices.Add(DeviceSlot.Stock("Drum Machine")); project.Tracks.Add(t); recovery.MarkDirty(); RefreshAll(); };
        header.Controls.Add(scan);
        header.Controls.Add(addSeq);
        SeedBrowserCatalog();
        browserTree.ItemDrag += (_, e) => { if (e.Item is TreeNode n && n.Tag is string p) DoDragDrop(new DataObject(DataFormats.FileDrop, new[] { p }), DragDropEffects.Copy); };
        panel.Controls.Add(browserTree);
        panel.Controls.Add(header);
        return panel;
    }

    private Control BuildAutomationPanel()
    {
        automationList.Columns.Add("Scope", 140);
        automationList.Columns.Add("Lane", 220);
        automationList.Columns.Add("Points", 80);
        automationList.DoubleClick += (_, _) => EditAutomationPoint();
        var panel = new Panel { Dock = DockStyle.Fill };
        var buttons = new FlowLayoutPanel { Dock = DockStyle.Top, Height = 42, Padding = new Padding(6) };
        var add = new Button { Text = "Add Point" };
        var del = new Button { Text = "Delete Last Point" };
        add.Click += (_, _) => EditAutomationPoint();
        del.Click += (_, _) => DeleteLastAutomationPoint();
        buttons.Controls.Add(add);
        buttons.Controls.Add(del);
        panel.Controls.Add(automationList);
        panel.Controls.Add(buttons);
        return panel;
    }

    private void SeedBrowserCatalog()
    {
        if (browserTree.Nodes.Count > 0) return;
        var instruments = browserTree.Nodes.Add("Stock Instruments");
        instruments.Nodes.Add("Oscillatron");
        instruments.Nodes.Add("LemmingBass");
        instruments.Nodes.Add("Drum Machine");
        var effects = browserTree.Nodes.Add("Stock Audio Effects");
        foreach (var name in new[] { "Auto Filter", "Saturator", "Bit Crusher", "EQ Three", "Compressor", "Reverb", "Delay", "Utility" }) effects.Nodes.Add(name);
        var plugins = browserTree.Nodes.Add("External Plug-ins");
        plugins.Nodes.Add("Scan/Add VST3 in Devices tab");
        var agents = browserTree.Nodes.Add("Agentic Tools");
        foreach (var name in new[] { "Bhangra Architect", "2C Guaracha", "Stem Splitter", "Sonic Signature Research", "Splice Finder" }) agents.Nodes.Add(name);
        instruments.Expand(); effects.Expand(); plugins.Expand(); agents.Expand();
    }

    private void RefreshAll()
    {
        arrangement.Project = project;
        arrangement.Invalidate();
        sessionLauncher.Project = project;
        sessionLauncher.Changed = () => { recovery.MarkDirty(); RefreshAll(); };
        sessionLauncher.ClipSelected = clip => { inspector.Reload(clip); arrangement.SelectedClipIds.Clear(); if (clip != null) arrangement.SelectedClipIds.Add(clip.Id); arrangement.Invalidate(); };
        sessionLauncher.Log = AppendLog;
        sessionLauncher.Reload();
        RefreshMixer();
        RefreshAutomation();
        stepSequencer.Project = project;
        stepSequencer.Changed = () => { recovery.MarkDirty(); RefreshAll(); SetStatus("Step Sequencer updated"); };
        stepSequencer.Log = AppendLog;
        stepSequencer.Reload();
        pianoRoll.Project = project;
        pianoRoll.Changed = () => { recovery.MarkDirty(); arrangement.Invalidate(); SetStatus("Piano Roll updated"); };
        pianoRoll.Reload();
        deviceRack.Project = project;
        deviceRack.Changed = () => { recovery.MarkDirty(); SetStatus("Device chain updated"); arrangement.Invalidate(); };
        deviceRack.Log = AppendLog;
        deviceRack.Reload();
        midiPanel.Project = project;
        midiPanel.Changed = () => { recovery.MarkDirty(); arrangement.Invalidate(); RefreshMixer(); SetStatus("MIDI updated"); };
        midiPanel.ExternalLog = AppendLog;
        midiPanel.Reload();
        audioRecordingPanel.Project = project;
        audioRecordingPanel.ProjectPathProvider = () => projectPath;
        audioRecordingPanel.Changed = () => { recovery.MarkDirty(); arrangement.Invalidate(); RefreshMixer(); SetStatus("Audio recording updated"); RefreshAll(); };
        audioRecordingPanel.ExternalLog = AppendLog;
        audioRecordingPanel.Reload();
        aiPanel.Project = project;
        aiPanel.OnProjectChanged = () => { recovery.MarkDirty(); RefreshAll(); SetStatus("AI agent updated the project"); };
        splicePanel.Project = project;
        splicePanel.OnProjectChanged = () => { recovery.MarkDirty(); RefreshAll(); SetStatus("Added a Splice sample"); };
        splicePanel.Log = AppendLog;
        inspector.Project = project;
        inspector.Changed = () => { recovery.MarkDirty(); arrangement.Invalidate(); RefreshMixer(); SetStatus("Inspector updated"); };
        inspector.Reload(arrangement.PrimarySelection);
        if (metronomeButton != null) { metronomeButton.Checked = project.MetronomeEnabled; metronomeButton.Text = project.MetronomeEnabled ? "● Metro" : "○ Metro"; }
        if (tempoLabel != null) tempoLabel.Text = $"{project.Tempo:0.#} BPM • {project.Key}";
        Text = $"{project.Name} — LemmingsStudio Windows";
        SetStatus($"{project.Name} • {project.Tempo:0.#} BPM • {project.Key}");
    }

    private void RefreshMixer()
    {
        mixerPanel.Project = project;
        mixerPanel.Engine = engine;
        mixerPanel.Log = AppendLog;
        mixerPanel.Changed = () => { recovery.MarkDirty(); arrangement.Invalidate(); SetStatus("Mixer updated"); };
        mixerPanel.Reload();
    }

    private void RefreshAutomation()
    {
        automationList.Items.Clear();
        foreach (var lane in project.GlobalAutomation)
        {
            var item = new ListViewItem("Global");
            item.SubItems.Add(lane.Name);
            item.SubItems.Add(lane.Points.Count.ToString());
            item.Tag = lane;
            automationList.Items.Add(item);
        }
        foreach (var t in project.Tracks)
        {
            EnsureDeviceOnLanes(t);
            foreach (var lane in t.Automation)
            {
                var item = new ListViewItem(t.Name);
                item.SubItems.Add(lane.Name);
                item.SubItems.Add(lane.Points.Count.ToString());
                item.Tag = lane;
                automationList.Items.Add(item);
            }
        }
    }

    private static void EnsureDeviceOnLanes(Track track)
    {
        foreach (var device in track.Devices)
        {
            if (!track.Automation.Any(a => a.Kind == AutomationTargetKind.DeviceOn && a.DeviceId == device.Id.ToString()))
            {
                track.Automation.Add(new AutomationLane
                {
                    Name = device.Name + " Device On",
                    Kind = AutomationTargetKind.DeviceOn,
                    DeviceId = device.Id.ToString(),
                    Minimum = 0,
                    Maximum = 1,
                    Points = new List<AutomationPoint> { new(0, device.Enabled ? 1 : 0) }
                });
            }

            foreach (var param in device.Parameters.Keys.Where(k => device.IsVst3 ? k.StartsWith("VST3:", StringComparison.OrdinalIgnoreCase) : true).Take(24).ToList())
            {
                if (track.Automation.Any(a => a.Kind == AutomationTargetKind.DeviceParameter && a.DeviceId == device.Id.ToString() && a.ParameterId == param)) continue;
                track.Automation.Add(new AutomationLane
                {
                    Name = device.Name + " / " + (param.StartsWith("VST3:", StringComparison.OrdinalIgnoreCase) ? param.Split(':').LastOrDefault() ?? param : param),
                    Kind = AutomationTargetKind.DeviceParameter,
                    DeviceId = device.Id.ToString(),
                    ParameterId = param,
                    Minimum = 0,
                    Maximum = 1,
                    Points = new List<AutomationPoint> { new(0, device.Parameters.TryGetValue(param, out var v) ? v : 0.5) }
                });
            }
        }
    }

    private void OnScannerBatch(IReadOnlyList<UserLibraryItem> items, string message)
    {
        BeginInvoke((Action)(() =>
        {
            foreach (var group in items.GroupBy(i => i.Kind))
            {
                var root = browserTree.Nodes.Cast<TreeNode>().FirstOrDefault(n => n.Text == group.Key) ?? browserTree.Nodes.Add(group.Key);
                foreach (var item in group)
                    root.Nodes.Add(new TreeNode(item.Name) { Tag = item.Path });
            }
            SetStatus(message);
        }));
    }

    private void ChooseAndScanLibrary()
    {
        using var dialog = new FolderBrowserDialog { Description = "Choose your User Library folder" };
        if (dialog.ShowDialog(this) != DialogResult.OK) return;
        browserTree.Nodes.Clear();
        SeedBrowserCatalog();
        scanCts?.Cancel();
        scanCts = new CancellationTokenSource();
        _ = scanner.ScanAsync(dialog.SelectedPath, scanCts.Token);
    }

    private async Task RunBackendSetup(string backend)
    {
        var script = Path.Combine(AppContext.BaseDirectory, "scripts", "setup-backend.ps1");
        if (!File.Exists(script)) script = Path.GetFullPath(Path.Combine("Ports", "Windows", "scripts", "setup-backend.ps1"));
        await runner.RunPowerShellAsync(script, $"-Backend {backend} -Runtime {buildRuntime}", AppContext.BaseDirectory);
    }

    private async Task StemSplitSelectedClip()
    {
        var clip = arrangement.PrimarySelection;
        if (clip?.SourcePath == null)
        {
            MessageBox.Show(this, "Select an audio clip with a source file first.", "Stem Split", MessageBoxButtons.OK, MessageBoxIcon.Information);
            return;
        }
        var script = Path.Combine(AppContext.BaseDirectory, "scripts", "test-stems.ps1");
        if (!File.Exists(script)) script = Path.GetFullPath(Path.Combine("Ports", "Windows", "scripts", "test-stems.ps1"));
        AppendLog($"Stem splitting '{Path.GetFileName(clip.SourcePath)}' with backend: {selectedBackend}");
        await runner.RunPowerShellAsync(script, $"-Backend {selectedBackend} -Runtime {buildRuntime} -InputPath \"{clip.SourcePath}\"", AppContext.BaseDirectory);
    }

    private void NewProject()
    {
        if (!ConfirmDiscardUnsaved()) return;
        ApplyLoadedProject(StudioProject.New());
        projectPath = null;
        recovery.MarkClean();
        RefreshAll();
    }

    private void OpenProject()
    {
        if (!ConfirmDiscardUnsaved()) return;
        using var dialog = new OpenFileDialog { Filter = "LemmingsStudio project|*.lemmingsproject|JSON|*.json|All files|*.*" };
        if (dialog.ShowDialog(this) != DialogResult.OK) return;
        try
        {
            var loaded = ProjectIO.Load(dialog.FileName);
            ApplyLoadedProject(loaded);
            projectPath = dialog.FileName;
            recovery.MarkClean();
            RefreshAll();
            AuditOpenedProject();
        }
        catch (Exception ex)
        {
            AppendLog("Project open failed: " + ex.Message);
            MessageBox.Show(this, ex.Message, "Open Project", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }

    private void SaveProject(bool saveAs)
    {
        if (saveAs || string.IsNullOrWhiteSpace(projectPath))
        {
            using var dialog = new SaveFileDialog { Filter = "LemmingsStudio project|*.lemmingsproject", FileName = project.Name + ".lemmingsproject", InitialDirectory = AppPaths.UserProjects };
            if (dialog.ShowDialog(this) != DialogResult.OK) return;
            projectPath = dialog.FileName;
            project.Name = Path.GetFileNameWithoutExtension(projectPath);
        }
        ProjectIO.SaveAtomic(projectPath!, project);
        recovery.MarkClean();
        recovery.DeleteRecovery(projectPath, project.Name);
        AppendLog("Saved " + projectPath);
        RefreshAll();
    }

    private void ApplyLoadedProject(StudioProject loaded)
    {
        project.Name = loaded.Name;
        project.Tempo = loaded.Tempo;
        project.Key = loaded.Key;
        project.Tracks = loaded.Tracks;
        project.GlobalAutomation = loaded.GlobalAutomation;
        project.MetronomeEnabled = loaded.MetronomeEnabled;
        project.BeatsPerBar = loaded.BeatsPerBar <= 0 ? 4 : loaded.BeatsPerBar;
        project.CountInEnabled = loaded.CountInEnabled;
        project.RecordCountInBars = loaded.RecordCountInBars <= 0 ? 1 : loaded.RecordCountInBars;
        project.QuantizeOnRecord = loaded.QuantizeOnRecord;
        project.QuantizeGridBeats = loaded.QuantizeGridBeats <= 0 ? 0.25 : loaded.QuantizeGridBeats;
        project.MidiRecordMode = loaded.MidiRecordMode;
        project.ReturnBuses = loaded.ReturnBuses;
        project.MasterVolume = loaded.MasterVolume;
        project.MasterMuted = loaded.MasterMuted;
    }

    private bool ConfirmDiscardUnsaved()
    {
        if (!recovery.IsDirty) return true;
        var result = MessageBox.Show(this, "This project has unsaved changes. Save before continuing?", "Unsaved Changes", MessageBoxButtons.YesNoCancel, MessageBoxIcon.Warning);
        if (result == DialogResult.Cancel) return false;
        if (result == DialogResult.Yes)
        {
            SaveProject(false);
            return !recovery.IsDirty;
        }
        return true;
    }

    private void RunAutosave()
    {
        if (!recovery.IsDirty) return;
        try
        {
            var path = recovery.Autosave(project, projectPath);
            AppendLog("Recovery autosave written: " + path);
            SetStatus("Recovery autosaved " + DateTime.Now.ToString("HH:mm:ss"));
        }
        catch (Exception ex) { AppendLog("Autosave failed: " + ex.Message); }
    }

    private void OfferRecoveryIfAvailable()
    {
        var candidate = ProjectRecoveryService.FindNewestRecovery();
        if (candidate == null) return;
        var answer = MessageBox.Show(this, $"A recovery autosave was found for '{candidate.ProjectName}' from {candidate.SavedUtc.ToLocalTime():g}. Recover it now?", "Recover Project", MessageBoxButtons.YesNo, MessageBoxIcon.Question);
        if (answer != DialogResult.Yes) return;
        try
        {
            ApplyLoadedProject(ProjectIO.Load(candidate.RecoveryPath));
            projectPath = candidate.OriginalProjectPath;
            recovery.MarkDirty();
            RefreshAll();
            AppendLog("Recovered autosave: " + candidate.RecoveryPath);
        }
        catch (Exception ex) { MessageBox.Show(this, ex.Message, "Recovery Failed", MessageBoxButtons.OK, MessageBoxIcon.Error); }
    }

    private void AuditOpenedProject()
    {
        var report = ProjectHealthService.Audit(project);
        if (!report.HasIssues) { AppendLog("Project health check passed."); return; }
        AppendLog(report.Summary());
        var answer = MessageBox.Show(this, report.Summary() + Environment.NewLine + Environment.NewLine + "Relink missing media from a folder now? Missing VST3 devices are bypassed rather than crashing the project.", "Project Health Check", MessageBoxButtons.YesNo, MessageBoxIcon.Warning);
        if (answer == DialogResult.Yes) RelinkMissingMedia();
        RefreshAll();
    }

    private void RelinkMissingMedia()
    {
        using var dialog = new FolderBrowserDialog { Description = "Choose a folder to search recursively for missing media" };
        if (dialog.ShowDialog(this) != DialogResult.OK) return;
        try
        {
            Cursor = Cursors.WaitCursor;
            var count = ProjectHealthService.RelinkMissingMedia(project, dialog.SelectedPath);
            if (count > 0) recovery.MarkDirty();
            RefreshAll();
            MessageBox.Show(this, $"Relinked {count} missing media file(s).", "Relink Media", MessageBoxButtons.OK, MessageBoxIcon.Information);
        }
        catch (Exception ex) { MessageBox.Show(this, ex.Message, "Relink Media", MessageBoxButtons.OK, MessageBoxIcon.Error); }
        finally { Cursor = Cursors.Default; }
    }

    private void ExportDiagnosticsBundle()
    {
        try
        {
            var zip = DiagnosticsBundleService.Create(project, projectPath, recentLogs);
            Clipboard.SetText(zip);
            AppendLog("Diagnostics bundle created: " + zip);
            MessageBox.Show(this, "Diagnostics bundle created and its path copied to the clipboard:

" + zip, "Diagnostics Bundle", MessageBoxButtons.OK, MessageBoxIcon.Information);
        }
        catch (Exception ex) { MessageBox.Show(this, ex.Message, "Diagnostics Bundle", MessageBoxButtons.OK, MessageBoxIcon.Error); }
    }

    private ExportSettings lastExport = new() { Format = ExportFormat.Wav, BitDepth = 24 };

    private void ExportAudio()
    {
        var settings = ExportDialog.Choose(this, lastExport);
        if (settings == null) return;
        lastExport = settings;

        string filter = settings.Format switch
        {
            ExportFormat.Wav => "WAV audio|*.wav",
            ExportFormat.Aiff => "AIFF audio|*.aiff;*.aif",
            ExportFormat.Mp3 => "MP3 audio|*.mp3",
            ExportFormat.Flac => "FLAC audio|*.flac",
            _ => "WAV audio|*.wav"
        };
        using var dialog = new SaveFileDialog { Filter = filter, FileName = project.Name + settings.Extension };
        if (dialog.ShowDialog(this) != DialogResult.OK) return;

        if (engine.IsPlaying) StopPlayback();
        try
        {
            SetStatus($"Rendering mixdown ({settings.Describe()})…");
            Cursor = Cursors.WaitCursor;
            engine.Export(project, dialog.FileName, settings);
            SetStatus("Exported " + Path.GetFileName(dialog.FileName));
        }
        catch (Exception ex)
        {
            AppendLog("Export failed: " + ex.Message);
            MessageBox.Show(this, ex.Message, "Export", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
        finally
        {
            Cursor = Cursors.Default;
        }
    }


    private Track? SelectedTrackForEdit()
    {
        var primary = arrangement.PrimarySelection;
        if (primary != null)
            return project.Tracks.FirstOrDefault(t => t.Clips.Any(c => c.Id == primary.Id));
        return project.Tracks.FirstOrDefault(t => t.Armed) ?? project.Tracks.FirstOrDefault();
    }

    private void RunBounceSelected()
    {
        var clip = arrangement.PrimarySelection;
        if (clip == null) { MessageBox.Show(this, "Select a clip first.", "Bounce", MessageBoxButtons.OK, MessageBoxIcon.Information); return; }
        var track = project.Tracks.FirstOrDefault(t => t.Clips.Any(c => c.Id == clip.Id));
        if (track == null) return;
        RunRenderEdit("Bounce", () => BounceFreezeService.BounceClip(project, track, clip, engine, projectPath));
    }

    private void RunConsolidateSelected()
    {
        var ids = arrangement.SelectedClipIds.ToHashSet();
        if (ids.Count == 0) { MessageBox.Show(this, "Select one or more clips first.", "Consolidate", MessageBoxButtons.OK, MessageBoxIcon.Information); return; }
        var tracks = project.Tracks.Where(t => t.Clips.Any(c => ids.Contains(c.Id))).ToList();
        if (tracks.Count != 1) { MessageBox.Show(this, "Consolidate currently requires all selected clips to be on one track.", "Consolidate", MessageBoxButtons.OK, MessageBoxIcon.Information); return; }
        RunRenderEdit("Consolidate", () => BounceFreezeService.Consolidate(project, tracks[0], ids, engine, projectPath));
        arrangement.SelectedClipIds.Clear();
    }

    private void RunFreezeSelectedTrack()
    {
        var track = SelectedTrackForEdit();
        if (track == null) return;
        RunRenderEdit("Freeze", () => BounceFreezeService.FreezeTrack(project, track, engine, projectPath));
    }

    private void RunUnfreezeSelectedTrack()
    {
        var track = SelectedTrackForEdit();
        if (track == null) return;
        try
        {
            BounceFreezeService.UnfreezeTrack(project, track);
            AppendLog($"Unfroze track '{track.Name}'.");
            recovery.MarkDirty();
            RefreshAll();
        }
        catch (Exception ex) { MessageBox.Show(this, ex.Message, "Unfreeze", MessageBoxButtons.OK, MessageBoxIcon.Error); }
    }

    private void RunFlattenSelectedTrack()
    {
        var track = SelectedTrackForEdit();
        if (track == null) return;
        if (!track.Frozen) { MessageBox.Show(this, "The selected track is not frozen.", "Flatten", MessageBoxButtons.OK, MessageBoxIcon.Information); return; }
        if (MessageBox.Show(this, "Flatten permanently keeps the frozen audio and discards the editable pre-freeze backup. Continue?", "Flatten Track", MessageBoxButtons.YesNo, MessageBoxIcon.Warning) != DialogResult.Yes) return;
        BounceFreezeService.FlattenTrack(track);
        AppendLog($"Flattened track '{track.Name}'.");
        recovery.MarkDirty();
        RefreshAll();
    }

    private void RunRenderEdit(string operation, Action action)
    {
        if (engine.IsPlaying) StopPlayback();
        try
        {
            Cursor = Cursors.WaitCursor;
            SetStatus(operation + " rendering…");
            action();
            recovery.MarkDirty();
            AppendLog(operation + " complete.");
            SetStatus(operation + " complete");
            RefreshAll();
        }
        catch (Exception ex)
        {
            AppendLog(operation + " failed: " + ex.Message);
            MessageBox.Show(this, ex.Message, operation, MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
        finally { Cursor = Cursors.Default; }
    }

    private void SetTempo()
    {
        var value = Prompt.Show("Tempo BPM", project.Tempo.ToString("0.##"));
        if (double.TryParse(value, out var bpm)) { project.Tempo = Math.Clamp(bpm, 40, 220); recovery.MarkDirty(); RefreshAll(); }
    }

    private void SetKey()
    {
        var value = Prompt.Show("Project key", project.Key);
        if (!string.IsNullOrWhiteSpace(value)) { project.Key = value; recovery.MarkDirty(); RefreshAll(); }
    }

    private void EditAutomationPoint()
    {
        if (automationList.SelectedItems.Count == 0 || automationList.SelectedItems[0].Tag is not AutomationLane lane) return;
        var beatText = Prompt.Show("Automation point beat", "0");
        var valueText = Prompt.Show($"Value ({lane.Minimum:0.##}–{lane.Maximum:0.##})", lane.Kind == AutomationTargetKind.Tempo ? project.Tempo.ToString("0.##") : "1");
        if (!double.TryParse(beatText, out var beat) || !double.TryParse(valueText, out var value)) return;
        value = Math.Clamp(value, lane.Minimum, lane.Maximum);
        if (lane.Kind == AutomationTargetKind.DeviceOn) value = value >= 0.5 ? 1 : 0;
        lane.Points.Add(new AutomationPoint(Math.Max(0, beat), value));
        lane.Points = lane.Points.OrderBy(p => p.Beat).ToList();
        recovery.MarkDirty();
        RefreshAutomation();
    }

    private void DeleteLastAutomationPoint()
    {
        if (automationList.SelectedItems.Count == 0 || automationList.SelectedItems[0].Tag is not AutomationLane lane || lane.Points.Count == 0) return;
        lane.Points.RemoveAt(lane.Points.Count - 1);
        recovery.MarkDirty();
        RefreshAutomation();
    }

    protected override void OnFormClosing(FormClosingEventArgs e)
    {
        if (!ConfirmDiscardUnsaved()) { e.Cancel = true; return; }
        autosaveTimer.Stop();
        engine.Dispose();
        scanCts?.Cancel();
        Vst3NativeHostBridge.Shared.Dispose();
        base.OnFormClosing(e);
    }

    private void SetStatus(string message) => statusLabel.Text = message;
    private void AppendLog(string message)
    {
        lock (recentLogs)
        {
            recentLogs.Add($"[{DateTime.Now:O}] {message}");
            if (recentLogs.Count > 5000) recentLogs.RemoveRange(0, recentLogs.Count - 5000);
        }
        void Append() => logBox.AppendText($"[{DateTime.Now:HH:mm:ss}] {message}{Environment.NewLine}");
        if (IsHandleCreated) BeginInvoke((Action)Append);
        else Append();
    }
}

public static class Prompt
{
    public static string Show(string caption, string value)
    {
        using var form = new Form { Text = caption, Width = 360, Height = 140, StartPosition = FormStartPosition.CenterParent };
        var box = new TextBox { Left = 12, Top = 12, Width = 320, Text = value };
        var ok = new Button { Text = "OK", Left = 176, Top = 52, DialogResult = DialogResult.OK };
        var cancel = new Button { Text = "Cancel", Left = 256, Top = 52, DialogResult = DialogResult.Cancel };
        form.Controls.Add(box); form.Controls.Add(ok); form.Controls.Add(cancel);
        form.AcceptButton = ok; form.CancelButton = cancel;
        return form.ShowDialog() == DialogResult.OK ? box.Text : value;
    }
}
