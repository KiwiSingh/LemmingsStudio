using LemmingsStudio.Windows;

namespace LemmingsStudio.Windows.Features;

/// <summary>
/// buildfix239: Windows Device Rack parity pass.
/// Adds chain rules, drag/reorder controls, duplicate/delete/bypass, device classification,
/// visible MIDI mappings, automation target creation and VST3 preset/state access.
/// </summary>
public sealed class DeviceRackPanel : UserControl
{
    private readonly ComboBox trackBox = new() { DropDownStyle = ComboBoxStyle.DropDownList, Width = 240, Left = 10, Top = 10 };
    private readonly Button addButton = new() { Text = "Add Device ▾", Left = 260, Top = 9, Width = 130 };
    private readonly Label chainStatus = new() { Left = 402, Top = 13, AutoSize = true, ForeColor = Color.DimGray };
    private readonly FlowLayoutPanel cards = new() { Dock = DockStyle.Fill, AutoScroll = true, FlowDirection = FlowDirection.TopDown, WrapContents = false, Padding = new Padding(10, 46, 10, 10), AllowDrop = true };
    private readonly ContextMenuStrip addMenu = new();
    private readonly ContextMenuStrip vstMenu = new();

    private DeviceSlot? draggedDevice;

    public StudioProject? Project { get; set; }
    public Action? Changed;
    public Action<string>? Log;

    private static readonly HashSet<string> StockInstruments = new(StringComparer.OrdinalIgnoreCase)
    {
        "Oscillatron", "LemmingBass", "Drum Machine"
    };

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
        header.Controls.Add(chainStatus);
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
        cards.DragEnter += (_, e) => { if (e.Data?.GetDataPresent(typeof(DeviceSlot)) == true) e.Effect = DragDropEffects.Move; };
        cards.DragOver += (_, e) => { if (draggedDevice != null) e.Effect = DragDropEffects.Move; };
        cards.DragDrop += Cards_DragDrop;
    }

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
        Project != null && trackBox.SelectedIndex >= 0 && trackBox.SelectedIndex < Project.Tracks.Count
            ? Project.Tracks[trackBox.SelectedIndex] : null;

    private static bool IsInstrument(DeviceSlot d)
    {
        if (!d.IsVst3) return StockInstruments.Contains(d.Name);
        // VST3 metadata: synths usually expose no audio input and at least one output.
        return d.PluginOutputChannels > 0 && d.PluginInputChannels == 0;
    }

    private static string DeviceTypeLabel(DeviceSlot d)
    {
        if (d.IsVst3) return IsInstrument(d) ? "VST3 Instrument" : "VST3 Effect";
        return IsInstrument(d) ? "Stock Instrument" : "Stock Effect";
    }

    private bool CanInsert(Track track, DeviceSlot candidate, int insertIndex, out string reason)
    {
        reason = "";
        if (!IsInstrument(candidate)) return true;
        if (track.Type != TrackType.Instrument)
        {
            reason = "Instrument devices can only be inserted on Instrument tracks.";
            return false;
        }
        var existing = track.Devices.Where(IsInstrument).ToList();
        if (existing.Any(d => d.Id != candidate.Id))
        {
            reason = "Only one instrument device is allowed per Instrument track. Remove or replace the existing instrument first.";
            return false;
        }
        if (insertIndex > 0)
        {
            reason = "The instrument must be the first device in the chain.";
            return false;
        }
        return true;
    }

    private void AddDevice((string Name, (string Key, double Value)[] Params) spec)
    {
        var track = SelectedTrack;
        if (track == null) return;
        var slot = new DeviceSlot { Name = spec.Name, Enabled = true, Parameters = new() };
        foreach (var (k, v) in spec.Params) slot.Parameters[k] = v;
        int index = IsInstrument(slot) ? 0 : track.Devices.Count;
        if (!CanInsert(track, slot, index, out var reason))
        {
            MessageBox.Show(FindForm(), reason, "Device Chain", MessageBoxButtons.OK, MessageBoxIcon.Information);
            return;
        }
        track.Devices.Insert(index, slot);
        CommitChainChange(track, $"Added {slot.Name}");
    }

    private void CommitChainChange(Track track, string log)
    {
        NormalizeChain(track);
        Log?.Invoke($"{log} on {track.Name}");
        BuildCards();
        Changed?.Invoke();
    }

    private static void NormalizeChain(Track track)
    {
        // Keep any single instrument first. Existing malformed projects remain audible rather than destructive:
        // extra instruments are bypassed and left visible for the user to resolve.
        var instruments = track.Devices.Where(IsInstrument).ToList();
        if (instruments.Count > 0)
        {
            var primary = instruments[0];
            track.Devices.Remove(primary);
            track.Devices.Insert(0, primary);
            foreach (var extra in instruments.Skip(1)) extra.Enabled = false;
        }
    }

    private void BuildCards()
    {
        cards.Controls.Clear();
        var track = SelectedTrack;
        if (track == null)
        {
            chainStatus.Text = "";
            cards.Controls.Add(new Label { Text = "Select a track to edit its device chain.", AutoSize = true, ForeColor = Color.DimGray, Margin = new Padding(4, 8, 4, 4) });
            return;
        }

        NormalizeChain(track);
        var invalid = track.Devices.Count(IsInstrument) > 1;
        chainStatus.Text = invalid ? "⚠ Multiple instruments: extras bypassed" : $"{track.Devices.Count} device{(track.Devices.Count == 1 ? "" : "s")}";
        chainStatus.ForeColor = invalid ? Color.DarkOrange : Color.DimGray;

        if (track.Devices.Count == 0)
        {
            cards.Controls.Add(new Label { Text = "No devices on this track yet. Use “Add Device ▾”.", AutoSize = true, ForeColor = Color.DimGray, Margin = new Padding(4, 8, 4, 4) });
            return;
        }

        for (int i = 0; i < track.Devices.Count; i++)
            cards.Controls.Add(BuildCard(track, track.Devices[i], i));
    }

    private Control BuildCard(Track track, DeviceSlot device, int index)
    {
        int paramCount = device.Parameters.Count;
        if (device.IsVst3) paramCount += 3;
        int cardWidth = Math.Max(620, cards.ClientSize.Width - 40);
        var card = new Panel
        {
            Width = cardWidth,
            Height = 82 + paramCount * 30,
            Margin = new Padding(2, 2, 2, 10),
            BorderStyle = BorderStyle.FixedSingle,
            BackColor = IsInstrument(device) ? Color.FromArgb(240, 246, 255) : device.IsVst3 ? Color.FromArgb(246, 241, 255) : Color.FromArgb(248, 248, 250),
            Tag = device,
            AllowDrop = true
        };

        var dragHandle = new Label { Text = "☰", Left = 8, Top = 8, Width = 22, Font = new Font("Segoe UI", 12f), Cursor = Cursors.SizeAll };
        dragHandle.MouseDown += (_, e) =>
        {
            if (e.Button != MouseButtons.Left) return;
            draggedDevice = device;
            dragHandle.DoDragDrop(device, DragDropEffects.Move);
            draggedDevice = null;
        };
        card.DragEnter += (_, e) => { if (e.Data?.GetDataPresent(typeof(DeviceSlot)) == true) e.Effect = DragDropEffects.Move; };
        card.DragDrop += (_, e) => ReorderDraggedDevice(track, device);

        var title = new Label { Text = device.Name, Font = new Font("Segoe UI", 9.5f, FontStyle.Bold), Left = 34, Top = 8, AutoSize = true };
        var type = new Label { Text = DeviceTypeLabel(device), Left = 34, Top = 29, AutoSize = true, ForeColor = Color.DimGray };

        var up = new Button { Text = "↑", Left = cardWidth - 420, Top = 5, Width = 36, Height = 25, Enabled = index > 0 };
        var down = new Button { Text = "↓", Left = cardWidth - 381, Top = 5, Width = 36, Height = 25, Enabled = index < track.Devices.Count - 1 };
        var duplicate = new Button { Text = "Duplicate", Left = cardWidth - 340, Top = 5, Width = 76, Height = 25 };
        var enabled = new CheckBox { Text = device.Enabled ? "On" : "Bypassed", Checked = device.Enabled, Left = cardWidth - 258, Top = 8, Width = 82 };
        var remove = new Button { Text = "Delete", Left = cardWidth - 86, Top = 5, Width = 74, Height = 25 };

        up.Click += (_, _) => MoveDevice(track, device, -1);
        down.Click += (_, _) => MoveDevice(track, device, +1);
        duplicate.Click += (_, _) => DuplicateDevice(track, device);
        enabled.CheckedChanged += (_, _) => { device.Enabled = enabled.Checked; enabled.Text = device.Enabled ? "On" : "Bypassed"; Changed?.Invoke(); };
        remove.Click += (_, _) =>
        {
            track.Devices.Remove(device);
            track.Automation.RemoveAll(l => l.DeviceId == device.Id.ToString());
            CommitChainChange(track, $"Deleted {device.Name}");
        };

        card.Controls.AddRange(new Control[] { dragHandle, title, type, up, down, duplicate, enabled, remove });

        int y = 55;
        if (device.IsVst3)
        {
            var editor = new Button { Text = "Editor", Left = 10, Top = y, Width = 70 };
            var host = new Button { Text = "Host", Left = 84, Top = y, Width = 70 };
            var parameters = new Button { Text = "Refresh Params", Left = 158, Top = y, Width = 105 };
            var state = new Button { Text = "Save State", Left = 267, Top = y, Width = 90 };
            var programs = new Button { Text = "Programs ▾", Left = 361, Top = y, Width = 92 };
            editor.Click += (_, _) => Vst3PluginService.TryOpenEditor(device, FindForm(), Log);
            host.Click += (_, _) => LoadVst3Host(device);
            parameters.Click += (_, _) => RefreshVst3(device);
            state.Click += (_, _) => SaveVst3State(device);
            programs.Click += (_, _) => ShowPrograms(device, programs);
            card.Controls.AddRange(new Control[] { editor, host, parameters, state, programs });
            y += 30;

            AddInfoRow(card, "Path", device.PluginPath ?? "", ref y, cardWidth);
            AddInfoRow(card, "Host", device.NativeHostEnabled ? (device.NativeHostStatus ?? "Native host loaded") : Vst3NativeHostBridge.Shared.StatusText, ref y, cardWidth);
            AddInfoRow(card, "I/O", $"{device.PluginInputChannels} → {device.PluginOutputChannels} • latency {device.PluginLatencySamples} samples • {device.PluginBusLayout ?? "layout unknown"}", ref y, cardWidth);
        }

        foreach (var key in new List<string>(device.Parameters.Keys))
        {
            string paramKey = key;
            var lbl = new Label { Text = DisplayParameterName(device, paramKey), Left = 10, Top = y + 3, Width = 145, AutoEllipsis = true };
            var bar = new TrackBar { Minimum = 0, Maximum = 100, TickStyle = TickStyle.None, Left = 160, Top = y, Width = Math.Max(120, cardWidth - 480), Value = (int)Math.Clamp(device.Parameters[paramKey] * 100.0, 0, 100) };
            var val = new Label { Text = device.Parameters[paramKey].ToString("0.00"), Left = cardWidth - 310, Top = y + 3, Width = 46 };
            string mappingText = device.MidiMappings.TryGetValue(paramKey, out var existingMap) ? $"Ch {(existingMap.Channel == 0 ? "Any" : existingMap.Channel)} CC {existingMap.Controller}" : "Unmapped";
            var mapping = new Label { Text = mappingText, Left = cardWidth - 260, Top = y + 3, Width = 92, ForeColor = existingMap != null ? Color.DarkGreen : Color.DimGray };
            var learn = new Button { Text = "Learn", Left = cardWidth - 164, Top = y - 1, Width = 62, Height = 24 };
            var automate = new Button { Text = "Auto", Left = cardWidth - 98, Top = y - 1, Width = 60, Height = 24 };

            learn.Click += (_, _) => ArmMidiLearn(device, paramKey, bar, val, mapping);
            automate.Click += (_, _) => AddAutomationTarget(track, device, paramKey);
            bar.Scroll += (_, _) => SetParameter(device, paramKey, bar.Value / 100.0, val);

            card.Controls.AddRange(new Control[] { lbl, bar, val, mapping, learn, automate });
            y += 30;
        }

        return card;
    }

    private static string DisplayParameterName(DeviceSlot device, string key)
    {
        if (!device.IsVst3 || !key.StartsWith("VST3:", StringComparison.OrdinalIgnoreCase)) return key;
        var info = device.Vst3Parameters.FirstOrDefault(p => string.Equals(p.Id, key, StringComparison.OrdinalIgnoreCase));
        return info?.Name ?? key[5..];
    }

    private static void AddInfoRow(Control card, string name, string value, ref int y, int width)
    {
        card.Controls.Add(new Label { Text = name, Left = 10, Top = y + 3, Width = 90 });
        card.Controls.Add(new Label { Text = value, Left = 100, Top = y + 3, Width = width - 125, AutoEllipsis = true });
        y += 30;
    }

    private void MoveDevice(Track track, DeviceSlot device, int delta)
    {
        int from = track.Devices.IndexOf(device);
        int to = Math.Clamp(from + delta, 0, track.Devices.Count - 1);
        if (from == to) return;
        if (IsInstrument(device) && to != 0)
        {
            MessageBox.Show(FindForm(), "Instrument devices must remain first in the chain.", "Device Chain", MessageBoxButtons.OK, MessageBoxIcon.Information);
            return;
        }
        if (!IsInstrument(device) && to == 0 && track.Devices.Any(IsInstrument)) to = 1;
        track.Devices.RemoveAt(from);
        track.Devices.Insert(Math.Clamp(to, 0, track.Devices.Count), device);
        CommitChainChange(track, $"Moved {device.Name}");
    }

    private void ReorderDraggedDevice(Track track, DeviceSlot target)
    {
        if (draggedDevice == null || draggedDevice == target) return;
        int from = track.Devices.IndexOf(draggedDevice);
        int to = track.Devices.IndexOf(target);
        if (from < 0 || to < 0) return;
        if (IsInstrument(draggedDevice) && to != 0)
        {
            MessageBox.Show(FindForm(), "Instrument devices must remain first in the chain.", "Device Chain", MessageBoxButtons.OK, MessageBoxIcon.Information);
            return;
        }
        if (!IsInstrument(draggedDevice) && to == 0 && track.Devices.Any(IsInstrument)) to = 1;
        track.Devices.RemoveAt(from);
        if (from < to) to--;
        track.Devices.Insert(Math.Clamp(to, 0, track.Devices.Count), draggedDevice);
        CommitChainChange(track, $"Reordered {draggedDevice.Name}");
    }

    private void Cards_DragDrop(object? sender, DragEventArgs e)
    {
        var track = SelectedTrack;
        if (track == null || draggedDevice == null) return;
        if (IsInstrument(draggedDevice)) return;
        track.Devices.Remove(draggedDevice);
        track.Devices.Add(draggedDevice);
        CommitChainChange(track, $"Moved {draggedDevice.Name} to end of chain");
    }

    private void DuplicateDevice(Track track, DeviceSlot source)
    {
        if (IsInstrument(source) && track.Devices.Any(d => IsInstrument(d) && d.Id != source.Id)) return;
        if (IsInstrument(source))
        {
            MessageBox.Show(FindForm(), "Only one instrument is allowed per track. Duplicate the track instead if you need a second instrument instance.", "Duplicate Device", MessageBoxButtons.OK, MessageBoxIcon.Information);
            return;
        }
        var copy = CloneDevice(source);
        int index = track.Devices.IndexOf(source);
        track.Devices.Insert(index + 1, copy);
        CommitChainChange(track, $"Duplicated {source.Name}");
    }

    private static DeviceSlot CloneDevice(DeviceSlot d) => new()
    {
        Id = Guid.NewGuid(),
        Name = d.Name + " Copy",
        Enabled = d.Enabled,
        Kind = d.Kind,
        PluginPath = d.PluginPath,
        PluginManufacturer = d.PluginManufacturer,
        PluginFormat = d.PluginFormat,
        EditorBridge = d.EditorBridge,
        NativeHostEnabled = false,
        NativeHostStatus = null,
        PluginStateBase64 = d.PluginStateBase64,
        PluginLatencySamples = d.PluginLatencySamples,
        PluginInputChannels = d.PluginInputChannels,
        PluginOutputChannels = d.PluginOutputChannels,
        PluginBusLayout = d.PluginBusLayout,
        PluginSupportsEditor = d.PluginSupportsEditor,
        PluginHasCustomEditor = d.PluginHasCustomEditor,
        PluginProgramIndex = d.PluginProgramIndex,
        Vst3Parameters = d.Vst3Parameters.Select(p => new Vst3ParameterInfo { Id = p.Id, Name = p.Name, Index = p.Index, NormalizedValue = p.NormalizedValue, DisplayValue = p.DisplayValue, Automatable = p.Automatable }).ToList(),
        Parameters = new Dictionary<string, double>(d.Parameters),
        MidiMappings = d.MidiMappings.ToDictionary(kv => kv.Key, kv => new MidiMapping { Channel = kv.Value.Channel, Controller = kv.Value.Controller, Minimum = kv.Value.Minimum, Maximum = kv.Value.Maximum })
    };

    private void ArmMidiLearn(DeviceSlot device, string paramKey, TrackBar bar, Label val, Label mapping)
    {
        MidiService.Shared.LearnNextControl($"{device.Name} / {DisplayParameterName(device, paramKey)}", (ch, cc, current) =>
        {
            device.MidiMappings[paramKey] = new MidiMapping { Channel = ch, Controller = cc };
            double v = current / 127.0;
            device.Parameters[paramKey] = v;
            bar.Value = (int)Math.Clamp(v * 100.0, 0, 100);
            val.Text = v.ToString("0.00");
            mapping.Text = $"Ch {(ch == 0 ? "Any" : ch)} CC {cc}";
            mapping.ForeColor = Color.DarkGreen;
            if (device.IsVst3 && paramKey.StartsWith("VST3:", StringComparison.OrdinalIgnoreCase))
                Vst3NativeHostBridge.Shared.SetParameter(device, paramKey, v);
            Changed?.Invoke();
        });
    }

    private void SetParameter(DeviceSlot device, string paramKey, double value, Label label)
    {
        device.Parameters[paramKey] = value;
        label.Text = value.ToString("0.00");
        if (device.IsVst3 && paramKey.StartsWith("VST3:", StringComparison.OrdinalIgnoreCase))
            Vst3NativeHostBridge.Shared.SetParameter(device, paramKey, value);
        Changed?.Invoke();
    }

    private void AddAutomationTarget(Track track, DeviceSlot device, string paramKey)
    {
        string deviceId = device.Id.ToString();
        var existing = track.Automation.FirstOrDefault(l => l.Kind == AutomationTargetKind.DeviceParameter && l.DeviceId == deviceId && l.ParameterId == paramKey);
        if (existing != null)
        {
            Log?.Invoke($"Automation target already exists: {existing.Name}");
            return;
        }
        track.Automation.Add(new AutomationLane
        {
            Name = $"{device.Name} • {DisplayParameterName(device, paramKey)}",
            Kind = AutomationTargetKind.DeviceParameter,
            DeviceId = deviceId,
            ParameterId = paramKey,
            Minimum = 0,
            Maximum = 1,
            Points = new List<AutomationPoint> { new(0, device.Parameters.TryGetValue(paramKey, out var v) ? v : 0.5) }
        });
        Log?.Invoke($"Created automation lane for {device.Name} / {DisplayParameterName(device, paramKey)}");
        Changed?.Invoke();
    }

    private void LoadVst3Host(DeviceSlot device)
    {
        Vst3NativeHostBridge.Shared.Log += m => Log?.Invoke(m);
        if (!Vst3NativeHostBridge.Shared.TryLoad(device, FindForm()))
        {
            MessageBox.Show(FindForm(), Vst3NativeHostBridge.Shared.LastError.Length == 0 ? Vst3NativeHostBridge.Shared.StatusText : Vst3NativeHostBridge.Shared.LastError, "Native VST3 Host", MessageBoxButtons.OK, MessageBoxIcon.Information);
            return;
        }
        device.NativeHostEnabled = true;
        device.NativeHostStatus = "Native host loaded";
        Vst3NativeHostBridge.Shared.RefreshParameters(device);
        Vst3NativeHostBridge.Shared.RefreshInfo(device);
        Changed?.Invoke();
        BuildCards();
    }

    private void RefreshVst3(DeviceSlot device)
    {
        Vst3NativeHostBridge.Shared.Log += m => Log?.Invoke(m);
        if (Vst3NativeHostBridge.Shared.RefreshParameters(device))
        {
            Vst3NativeHostBridge.Shared.RefreshInfo(device);
            device.NativeHostStatus = $"{device.PluginInputChannels}→{device.PluginOutputChannels}, latency {device.PluginLatencySamples} samples";
            Changed?.Invoke();
            BuildCards();
        }
    }

    private void SaveVst3State(DeviceSlot device)
    {
        if (Vst3NativeHostBridge.Shared.SaveState(device) == null) return;
        Log?.Invoke($"Saved VST3 state for {device.Name}");
        Changed?.Invoke();
    }

    private void ShowPrograms(DeviceSlot device, Control anchor)
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
                if (!Vst3NativeHostBridge.Shared.SetProgram(device, local.Index)) return;
                device.PluginProgramIndex = local.Index;
                Vst3NativeHostBridge.Shared.SaveState(device);
                Log?.Invoke($"Set {device.Name} program to {local.Name}");
                Changed?.Invoke();
            });
        }
        menu.Show(anchor, 0, anchor.Height);
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
        var track = SelectedTrack;
        if (track == null) return;
        using var dlg = new OpenFileDialog
        {
            Title = "Choose a VST3 plug-in",
            Filter = "VST3 plug-ins (*.vst3)|*.vst3|All files (*.*)|*.*",
            CheckFileExists = false,
            ValidateNames = false
        };
        if (dlg.ShowDialog(FindForm()) != DialogResult.OK) return;
        var path = dlg.FileName;
        AddVst3(new Vst3PluginInfo { Name = Path.GetFileNameWithoutExtension(path), Path = path, Manufacturer = "VST3", IsBundleDirectory = Directory.Exists(path) });
    }

    private void AddVst3(Vst3PluginInfo plugin)
    {
        var track = SelectedTrack;
        if (track == null) return;
        var slot = Vst3PluginService.ToDeviceSlot(plugin);
        // Until metadata is queried we conservatively append unknown VST3s. Once Host/Refresh
        // identifies a no-input synth, NormalizeChain moves it to the instrument position.
        track.Devices.Add(slot);
        CommitChainChange(track, $"Added VST3 {plugin.Name}");
    }
}
