using LemmingsStudio.Windows;

namespace LemmingsStudio.Windows.Features;

/// <summary>
/// Windows port of the macOS instrument/device rack: an Ableton-style per-track insert
/// chain. Pick a track, add stock devices, tweak their parameters, enable/bypass, remove.
///
/// Honest scope: the offline render engine now processes all stock effects — Auto Filter,
/// Saturator, Bit Crusher, EQ Three, Compressor, Reverb, Delay and Utility — in chain order,
/// plus the Oscillatron / LemmingBass instruments. VST3 slots now use the native
/// out-of-process helper for editor windows, live MIDI, parameter discovery, state
/// persistence, and first-pass offline PCM render/processing.
/// </summary>
public sealed class DeviceRackPanel : UserControl
{
    private readonly ComboBox trackBox = new() { DropDownStyle = ComboBoxStyle.DropDownList, Width = 240, Left = 10, Top = 10 };
    private readonly Button addButton = new() { Text = "Add Device ▾", Left = 260, Top = 9, Width = 130 };
    private readonly FlowLayoutPanel cards = new() { Dock = DockStyle.Fill, AutoScroll = true, FlowDirection = FlowDirection.TopDown, WrapContents = false, Padding = new Padding(10, 46, 10, 10) };
    private readonly ContextMenuStrip addMenu = new();
    private readonly ContextMenuStrip vstMenu = new();

    public StudioProject? Project { get; set; }
    public Action? Changed;
    public Action<string>? Log;

    /// <summary>Stock device catalog (name → ordered default parameters in 0..1).</summary>
    private static readonly (string Name, (string Key, double Value)[] Params)[] Catalog =
    {
        ("Oscillatron",  new[] { ("Cutoff", 0.62), ("Detune", 0.35), ("Sub", 0.20) }),
        ("LemmingBass",  new[] { ("Cutoff", 0.30), ("Drive", 0.36), ("Sub", 0.55), ("Punch", 0.48), ("Wave", 0.35) }),
        ("Auto Filter", new[] { ("Cutoff", 0.65), ("Resonance", 0.25), ("Drive", 0.10) }),
        ("Saturator",   new[] { ("Drive", 0.35), ("Wet", 0.80) }),
        ("Bit Crusher", new[] { ("Bits", 0.40), ("Downsample", 0.30), ("Wet", 1.00) }),
        ("EQ Three",    new[] { ("Low", 0.50), ("Mid", 0.50), ("High", 0.50), ("Gain", 0.50) }),
        ("Compressor",  new[] { ("Threshold", 0.50), ("Ratio", 0.40), ("Attack", 0.20), ("Release", 0.40), ("Makeup", 0.30) }),
        ("Reverb",      new[] { ("Size", 0.50), ("Decay", 0.50), ("Wet", 0.30) }),
        ("Delay",       new[] { ("Time", 0.35), ("Feedback", 0.30), ("Wet", 0.30) }),
        ("Utility",     new[] { ("Gain", 0.50), ("Width", 0.50), ("Pan", 0.50) }),
    };

    public DeviceRackPanel()
    {
        Dock = DockStyle.Fill;
        var header = new Panel { Dock = DockStyle.Top, Height = 46 };
        header.Controls.Add(trackBox);
        header.Controls.Add(addButton);
        Controls.Add(cards);
        Controls.Add(header);

        foreach (var d in Catalog)
        {
            var entry = d;
            addMenu.Items.Add(d.Name, null, (_, _) => AddDevice(entry));
        }
        addMenu.Items.Add(new ToolStripSeparator());
        addMenu.Items.Add("Scan/Add VST3 Plug-in…", null, (_, _) => ShowVstMenu());
        addMenu.Items.Add("Add VST3 From File…", null, (_, _) => AddVstFromPicker());
        addButton.Click += (_, _) => addMenu.Show(addButton, new Point(0, addButton.Height));
        trackBox.SelectedIndexChanged += (_, _) => BuildCards();
    }

    /// <summary>Refresh from the project (call after track add/remove or project load).</summary>
    public void Reload()
    {
        int previous = trackBox.SelectedIndex;
        trackBox.Items.Clear();
        if (Project != null)
            foreach (var t in Project.Tracks) trackBox.Items.Add(t.Name);
        if (trackBox.Items.Count > 0)
            trackBox.SelectedIndex = Math.Clamp(previous < 0 ? 0 : previous, 0, trackBox.Items.Count - 1);
        else
            BuildCards();
    }

    private Track? SelectedTrack =>
        (Project != null && trackBox.SelectedIndex >= 0 && trackBox.SelectedIndex < Project.Tracks.Count)
            ? Project.Tracks[trackBox.SelectedIndex] : null;

    private void AddDevice((string Name, (string Key, double Value)[] Params) spec)
    {
        var track = SelectedTrack;
        if (track == null) return;
        var slot = new DeviceSlot { Name = spec.Name, Enabled = true, Parameters = new() };
        foreach (var (k, v) in spec.Params) slot.Parameters[k] = v;
        track.Devices.Add(slot);
        BuildCards();
        Changed?.Invoke();
    }

    private void BuildCards()
    {
        cards.Controls.Clear();
        var track = SelectedTrack;
        if (track == null)
        {
            cards.Controls.Add(new Label { Text = "Select a track to edit its device chain.", AutoSize = true, ForeColor = Color.DimGray, Margin = new Padding(4, 8, 4, 4) });
            return;
        }
        if (track.Devices.Count == 0)
        {
            cards.Controls.Add(new Label { Text = "No devices on this track yet. Use “Add Device ▾”.", AutoSize = true, ForeColor = Color.DimGray, Margin = new Padding(4, 8, 4, 4) });
            return;
        }
        foreach (var device in track.Devices)
            cards.Controls.Add(BuildCard(track, device));
    }

    private Control BuildCard(Track track, DeviceSlot device)
    {
        int paramCount = device.Parameters.Count;
        if (device.IsVst3) paramCount += 4;
        int cardWidth = Math.Max(380, cards.ClientSize.Width - 40);
        var card = new Panel
        {
            Width = cardWidth,
            Height = 60 + paramCount * 30,
            Margin = new Padding(2, 2, 2, 10),
            BorderStyle = BorderStyle.FixedSingle,
            BackColor = Color.FromArgb(248, 248, 250)
        };

        var titleText = device.IsVst3 ? $"VST3 • {device.Name}" : device.Name;
        var title = new Label { Text = titleText, Font = new Font("Segoe UI", 9.5f, FontStyle.Bold), Left = 10, Top = 9, AutoSize = true };
        var openEditor = new Button { Text = device.IsVst3 ? "Editor" : "", Left = cardWidth - 310, Top = 5, Width = 72, Visible = device.IsVst3 };
        openEditor.Click += (_, _) => Vst3PluginService.TryOpenEditor(device, FindForm(), Log);
        var loadHost = new Button { Text = device.IsVst3 ? "Host" : "", Left = cardWidth - 235, Top = 5, Width = 72, Visible = device.IsVst3 };
        loadHost.Click += (_, _) =>
        {
            Vst3NativeHostBridge.Shared.Log += m => Log?.Invoke(m);
            if (Vst3NativeHostBridge.Shared.TryLoad(device, FindForm()))
            {
                device.NativeHostEnabled = true;
                device.NativeHostStatus = "Native host loaded";
                Vst3NativeHostBridge.Shared.RefreshParameters(device);
                Vst3NativeHostBridge.Shared.RefreshInfo(device);
                Log?.Invoke($"Native VST3 host loaded for {device.Name}");
                Changed?.Invoke();
                BuildCards();
            }
            else
            {
                MessageBox.Show(FindForm(), Vst3NativeHostBridge.Shared.LastError.Length == 0 ? Vst3NativeHostBridge.Shared.StatusText : Vst3NativeHostBridge.Shared.LastError, "Native VST3 Host", MessageBoxButtons.OK, MessageBoxIcon.Information);
            }
        };
        var refreshVst = new Button { Text = device.IsVst3 ? "Params" : "", Left = cardWidth - 235, Top = 31, Width = 72, Height = 23, Visible = device.IsVst3 };
        refreshVst.Click += (_, _) =>
        {
            Vst3NativeHostBridge.Shared.Log += m => Log?.Invoke(m);
            if (Vst3NativeHostBridge.Shared.RefreshParameters(device))
            {
                Vst3NativeHostBridge.Shared.RefreshInfo(device);
                device.NativeHostStatus = $"{device.PluginInputChannels}→{device.PluginOutputChannels}, latency {device.PluginLatencySamples} samples";
                Changed?.Invoke();
                BuildCards();
            }
        };
        var saveState = new Button { Text = device.IsVst3 ? "State" : "", Left = cardWidth - 310, Top = 31, Width = 72, Height = 23, Visible = device.IsVst3 };
        saveState.Click += (_, _) =>
        {
            if (Vst3NativeHostBridge.Shared.SaveState(device) != null)
            {
                Log?.Invoke($"Saved VST3 state for {device.Name}");
                Changed?.Invoke();
            }
        };
        var programs = new Button { Text = device.IsVst3 ? "Programs" : "", Left = cardWidth - 160, Top = 31, Width = 78, Height = 23, Visible = device.IsVst3 };
        programs.Click += (_, _) =>
        {
            var items = Vst3NativeHostBridge.Shared.GetPrograms(device);
            if (items.Count == 0)
            {
                MessageBox.Show(FindForm(), "This plug-in did not expose a program/preset list through the host API. Use the plug-in editor or save the current state instead.", "VST3 Programs", MessageBoxButtons.OK, MessageBoxIcon.Information);
                return;
            }
            var menu = new ContextMenuStrip();
            foreach (var item in items)
            {
                var local = item;
                menu.Items.Add($"{local.Index + 1}. {local.Name}", null, (_, _) =>
                {
                    if (Vst3NativeHostBridge.Shared.SetProgram(device, local.Index))
                    {
                        Log?.Invoke($"Set {device.Name} program to {local.Name}");
                        Vst3NativeHostBridge.Shared.SaveState(device);
                        Changed?.Invoke();
                    }
                });
            }
            menu.Show(programs, 0, programs.Height);
        };
        var enabled = new CheckBox { Text = "On", Checked = device.Enabled, Left = cardWidth - 150, Top = 7, Width = 50 };
        enabled.CheckedChanged += (_, _) => { device.Enabled = enabled.Checked; Changed?.Invoke(); };
        var remove = new Button { Text = "Remove", Left = cardWidth - 90, Top = 5, Width = 78 };
        remove.Click += (_, _) => { track.Devices.Remove(device); BuildCards(); Changed?.Invoke(); };
        remove.Anchor = AnchorStyles.Top | AnchorStyles.Right;
        enabled.Anchor = AnchorStyles.Top | AnchorStyles.Right;
        card.Controls.Add(title);
        card.Controls.Add(openEditor);
        card.Controls.Add(loadHost);
        card.Controls.Add(refreshVst);
        card.Controls.Add(saveState);
        card.Controls.Add(programs);
        card.Controls.Add(enabled);
        card.Controls.Add(remove);

        int y = 36;
        if (device.IsVst3)
        {
            var pathLbl = new Label { Text = "Path", Left = 10, Top = y + 3, Width = 90, AutoSize = false };
            var pathVal = new Label { Text = device.PluginPath ?? "", Left = 100, Top = y + 3, Width = cardWidth - 125, AutoEllipsis = true };
            card.Controls.Add(pathLbl); card.Controls.Add(pathVal); y += 30;
            var hostLbl = new Label { Text = "Host", Left = 10, Top = y + 3, Width = 90, AutoSize = false };
            var hostText = device.NativeHostEnabled
                ? (device.NativeHostStatus ?? $"{device.PluginInputChannels}→{device.PluginOutputChannels}, latency {device.PluginLatencySamples} samples")
                : Vst3NativeHostBridge.Shared.StatusText;
            var hostVal = new Label { Text = hostText, Left = 100, Top = y + 3, Width = cardWidth - 125, AutoEllipsis = true };
            card.Controls.Add(hostLbl); card.Controls.Add(hostVal); y += 30;
        }
        foreach (var key in new List<string>(device.Parameters.Keys))
        {
            string paramKey = key;
            var lbl = new Label { Text = paramKey, Left = 10, Top = y + 3, Width = 90, AutoSize = false };
            var bar = new TrackBar { Minimum = 0, Maximum = 100, TickStyle = TickStyle.None, Left = 100, Top = y, Width = card.Width - 230, Value = (int)Math.Clamp(device.Parameters[paramKey] * 100.0, 0, 100) };
            var val = new Label { Text = device.Parameters[paramKey].ToString("0.00"), Left = cardWidth - 142, Top = y + 3, Width = 50, AutoSize = false };
            var learn = new Button { Text = "Learn", Left = cardWidth - 86, Top = y - 1, Width = 66, Height = 24 };
            bar.Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right;
            val.Anchor = AnchorStyles.Top | AnchorStyles.Right;
            learn.Anchor = AnchorStyles.Top | AnchorStyles.Right;
            learn.Click += (_, _) => MidiService.Shared.LearnNextControl($"{device.Name} / {paramKey}", (ch, cc, current) =>
            {
                device.MidiMappings[paramKey] = new MidiMapping { Channel = ch, Controller = cc };
                double v = current / 127.0;
                device.Parameters[paramKey] = v;
                bar.Value = (int)Math.Clamp(v * 100.0, 0, 100);
                val.Text = v.ToString("0.00");
                if (device.IsVst3 && paramKey.StartsWith("VST3:", StringComparison.OrdinalIgnoreCase))
                    Vst3NativeHostBridge.Shared.SetParameter(device, paramKey, v);
                Changed?.Invoke();
            });
            bar.Scroll += (_, _) =>
            {
                double v = bar.Value / 100.0;
                device.Parameters[paramKey] = v;
                val.Text = v.ToString("0.00");
                if (device.IsVst3 && paramKey.StartsWith("VST3:", StringComparison.OrdinalIgnoreCase))
                    Vst3NativeHostBridge.Shared.SetParameter(device, paramKey, v);
                Changed?.Invoke();
            };
            card.Controls.Add(lbl);
            card.Controls.Add(bar);
            card.Controls.Add(val);
            card.Controls.Add(learn);
            y += 30;
        }
        return card;
    }
    private void ShowVstMenu()
    {
        var track = SelectedTrack;
        if (track == null) return;
        vstMenu.Items.Clear();
        vstMenu.Items.Add("Scanning VST3 folders…").Enabled = false;
        vstMenu.Show(addButton, new Point(0, addButton.Height));
        Task.Run(() => Vst3PluginService.Scan(Log)).ContinueWith(task =>
        {
            if (IsDisposed) return;
            BeginInvoke((Action)(() =>
            {
                vstMenu.Items.Clear();
                var plugins = task.Status == TaskStatus.RanToCompletion ? task.Result : Array.Empty<Vst3PluginInfo>();
                if (plugins.Count == 0)
                {
                    vstMenu.Items.Add("No VST3 plug-ins found").Enabled = false;
                    vstMenu.Items.Add("Add VST3 From File…", null, (_, _) => AddVstFromPicker());
                }
                else
                {
                    foreach (var plugin in plugins.Take(80))
                    {
                        var p = plugin;
                        vstMenu.Items.Add(p.ToString(), null, (_, _) => AddVst3(p));
                    }
                    if (plugins.Count > 80) vstMenu.Items.Add($"…and {plugins.Count - 80} more. Use Add From File for exact selection.").Enabled = false;
                }
                vstMenu.Show(addButton, new Point(0, addButton.Height));
            }));
        });
    }

    private void AddVstFromPicker()
    {
        var track = SelectedTrack; if (track == null) return;
        using var dlg = new OpenFileDialog
        {
            Title = "Choose a VST3 plug-in",
            Filter = "VST3 plug-ins (*.vst3)|*.vst3|All files (*.*)|*.*",
            CheckFileExists = false,
            ValidateNames = false
        };
        if (dlg.ShowDialog(FindForm()) == DialogResult.OK)
        {
            var path = dlg.FileName;
            AddVst3(new Vst3PluginInfo { Name = Path.GetFileNameWithoutExtension(path), Path = path, Manufacturer = "VST3", IsBundleDirectory = Directory.Exists(path) });
        }
    }

    private void AddVst3(Vst3PluginInfo plugin)
    {
        var track = SelectedTrack; if (track == null) return;
        track.Devices.Add(Vst3PluginService.ToDeviceSlot(plugin));
        Log?.Invoke($"Added VST3 slot to {track.Name}: {plugin.Name}");
        BuildCards();
        Changed?.Invoke();
    }

}
