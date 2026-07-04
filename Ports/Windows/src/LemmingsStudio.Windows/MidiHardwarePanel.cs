using System.Diagnostics;

namespace LemmingsStudio.Windows;

public sealed class MidiHardwarePanel : UserControl
{
    private readonly ComboBox inputBox = new() { DropDownStyle = ComboBoxStyle.DropDownList, Width = 230 };
    private readonly ComboBox outputBox = new() { DropDownStyle = ComboBoxStyle.DropDownList, Width = 220 };
    private readonly ComboBox trackBox = new() { DropDownStyle = ComboBoxStyle.DropDownList, Width = 220 };
    private readonly ComboBox modeBox = new() { DropDownStyle = ComboBoxStyle.DropDownList, Width = 92 };
    private readonly ComboBox quantizeBox = new() { DropDownStyle = ComboBoxStyle.DropDownList, Width = 82 };
    private readonly NumericUpDown startBeat = new() { Minimum = 0, Maximum = 10000, DecimalPlaces = 2, Increment = 0.25M, Width = 74 };
    private readonly NumericUpDown lengthBeats = new() { Minimum = 1, Maximum = 512, DecimalPlaces = 2, Increment = 1M, Value = 4, Width = 74 };
    private readonly NumericUpDown countBars = new() { Minimum = 0, Maximum = 8, Value = 1, Width = 54 };
    private readonly NumericUpDown pitchRange = new() { Minimum = 0, Maximum = 48, Value = 2, Width = 54 };
    private readonly NumericUpDown modDepth = new() { Minimum = 0, Maximum = 12, DecimalPlaces = 2, Increment = 0.05M, Value = 0.35M, Width = 62 };
    private readonly CheckBox live = new() { Text = "Live audition", Checked = true, AutoSize = true };
    private readonly CheckBox routeVst3 = new() { Text = "Route to VST3", Checked = true, AutoSize = true };
    private readonly CheckBox record = new() { Text = "Record MIDI", AutoSize = true };
    private readonly CheckBox countIn = new() { Text = "Count-in", AutoSize = true, Checked = true };
    private readonly CheckBox recordControllers = new() { Text = "CC / pitch / sustain", AutoSize = true, Checked = true };
    private readonly TextBox log = new() { Dock = DockStyle.Fill, Multiline = true, ReadOnly = true, ScrollBars = ScrollBars.Vertical, Font = new Font("Consolas", 9) };
    private readonly LiveMidiSynth synth = new();
    private readonly Stopwatch clock = new();
    private readonly Dictionary<int, (double Beat, int Velocity)> active = new();
    private readonly HashSet<int> sustainedPendingOff = new();
    private ProjectClip? recordClip;
    private bool sustainDown;
    private bool recordingActive;
    private bool countInPending;

    public StudioProject? Project { get; set; }
    public Action? Changed;
    public Action<string>? ExternalLog;

    public MidiHardwarePanel()
    {
        Dock = DockStyle.Fill;
        modeBox.Items.AddRange(new object[] { "Overdub", "Replace" });
        modeBox.SelectedIndex = 0;
        quantizeBox.Items.AddRange(new object[] { "Off", "1/4", "1/8", "1/16", "1/32" });
        quantizeBox.SelectedIndex = 0;

        var top = new FlowLayoutPanel { Dock = DockStyle.Top, Height = 128, Padding = new Padding(8), AutoSize = false };
        var refresh = new Button { Text = "Refresh MIDI" };
        var open = new Button { Text = "Open Input" };
        var panic = new Button { Text = "Panic" };
        top.Controls.Add(new Label { Text = "Input", AutoSize = true, Padding = new Padding(0, 8, 4, 0) });
        top.Controls.Add(inputBox);
        top.Controls.Add(open);
        top.Controls.Add(new Label { Text = "Output", AutoSize = true, Padding = new Padding(18, 8, 4, 0) });
        top.Controls.Add(outputBox);
        top.Controls.Add(refresh);
        top.Controls.Add(new Label { Text = "Track", AutoSize = true, Padding = new Padding(0, 8, 4, 0) });
        top.Controls.Add(trackBox);
        top.Controls.Add(live);
        top.Controls.Add(routeVst3);
        top.Controls.Add(panic);
        top.Controls.Add(new Label { Text = "Mode", AutoSize = true, Padding = new Padding(0, 8, 4, 0) });
        top.Controls.Add(modeBox);
        top.Controls.Add(new Label { Text = "Quantize", AutoSize = true, Padding = new Padding(12, 8, 4, 0) });
        top.Controls.Add(quantizeBox);
        top.Controls.Add(new Label { Text = "Start", AutoSize = true, Padding = new Padding(12, 8, 4, 0) });
        top.Controls.Add(startBeat);
        top.Controls.Add(new Label { Text = "Length", AutoSize = true, Padding = new Padding(12, 8, 4, 0) });
        top.Controls.Add(lengthBeats);
        top.Controls.Add(countIn);
        top.Controls.Add(new Label { Text = "Bars", AutoSize = true, Padding = new Padding(2, 8, 2, 0) });
        top.Controls.Add(countBars);
        top.Controls.Add(recordControllers);
        top.Controls.Add(new Label { Text = "PB range", AutoSize = true, Padding = new Padding(12, 8, 4, 0) });
        top.Controls.Add(pitchRange);
        top.Controls.Add(new Label { Text = "Mod depth", AutoSize = true, Padding = new Padding(8, 8, 4, 0) });
        top.Controls.Add(modDepth);
        top.Controls.Add(record);
        Controls.Add(log); Controls.Add(top);

        MidiService.Shared.Log += Append;
        MidiService.Shared.NoteOn += OnNoteOn;
        MidiService.Shared.NoteOff += OnNoteOff;
        MidiService.Shared.ControlChange += OnControlChange;
        MidiService.Shared.PitchBend += OnPitchBend;
        MidiService.Shared.ChannelEvent += OnChannelEvent;
        refresh.Click += (_, _) => ReloadDevices();
        open.Click += (_, _) => OpenSelectedInput();
        panic.Click += (_, _) => SendPanic();
        record.CheckedChanged += async (_, _) => await ToggleRecordingAsync(record.Checked);
        live.CheckedChanged += (_, _) => synth.Enabled = live.Checked;
        trackBox.SelectedIndexChanged += (_, _) => { synth.TargetTrack = SelectedTrack; if (SelectedTrack != null) { pitchRange.Value = Math.Clamp(SelectedTrack.PitchBendRangeSemitones, (int)pitchRange.Minimum, (int)pitchRange.Maximum); modDepth.Value = Math.Clamp((decimal)SelectedTrack.ModWheelDepthSemitones, modDepth.Minimum, modDepth.Maximum); } };
        pitchRange.ValueChanged += (_, _) => { if (SelectedTrack != null) { SelectedTrack.PitchBendRangeSemitones = (int)pitchRange.Value; Changed?.Invoke(); } };
        modDepth.ValueChanged += (_, _) => { if (SelectedTrack != null) { SelectedTrack.ModWheelDepthSemitones = (double)modDepth.Value; Changed?.Invoke(); } };
        ReloadDevices();
    }

    public void Reload()
    {
        var previous = trackBox.SelectedIndex;
        trackBox.Items.Clear();
        if (Project != null)
            foreach (var t in Project.Tracks.Where(t => t.Type is TrackType.Instrument or TrackType.Midi || t.Armed)) trackBox.Items.Add(t);
        if (trackBox.Items.Count > 0) trackBox.SelectedIndex = Math.Clamp(previous < 0 ? 0 : previous, 0, trackBox.Items.Count - 1);
        synth.TargetTrack = SelectedTrack;
        if (SelectedTrack != null)
        {
            pitchRange.Value = Math.Clamp(SelectedTrack.PitchBendRangeSemitones, (int)pitchRange.Minimum, (int)pitchRange.Maximum);
            modDepth.Value = Math.Clamp((decimal)SelectedTrack.ModWheelDepthSemitones, modDepth.Minimum, modDepth.Maximum);
        }
        if (Project != null)
        {
            countIn.Checked = Project.CountInEnabled;
            countBars.Value = Math.Clamp(Project.RecordCountInBars, (int)countBars.Minimum, (int)countBars.Maximum);
            modeBox.SelectedItem = Project.MidiRecordMode == MidiRecordMode.Replace ? "Replace" : "Overdub";
            quantizeBox.SelectedIndex = Project.QuantizeOnRecord ? GridToIndex(Project.QuantizeGridBeats) : 0;
        }
    }

    private Track? SelectedTrack => trackBox.SelectedItem as Track;
    private DeviceSlot? SelectedVst3Slot => SelectedTrack?.Devices.FirstOrDefault(d => d.Enabled && d.IsVst3);

    private void ReloadDevices()
    {
        inputBox.Items.Clear(); outputBox.Items.Clear();
        foreach (var n in MidiService.Shared.InputNames()) inputBox.Items.Add(n);
        foreach (var n in MidiService.Shared.OutputNames()) outputBox.Items.Add(n);
        if (inputBox.Items.Count > 0 && inputBox.SelectedIndex < 0) inputBox.SelectedIndex = 0;
        if (outputBox.Items.Count > 0 && outputBox.SelectedIndex < 0) outputBox.SelectedIndex = 0;
        Append($"MIDI devices refreshed: {inputBox.Items.Count} input(s), {outputBox.Items.Count} output(s).");
    }

    private void OpenSelectedInput()
    {
        try
        {
            if (inputBox.SelectedIndex < 0) { Append("No MIDI input selected."); return; }
            MidiService.Shared.OpenInput(inputBox.SelectedIndex);
            if (SelectedTrack != null) SelectedTrack.MidiInputName = inputBox.Text;
            Changed?.Invoke();
        }
        catch (Exception ex) { Append("Open MIDI input failed: " + ex.Message); }
    }

    private void OnNoteOn(int ch, int note, int velocity)
    {
        BeginInvoke((Action)(() =>
        {
            Append($"Note On ch{ch} {note} vel{velocity}");
            bool routed = false;
            if (routeVst3.Checked && SelectedVst3Slot is { } slot)
                routed = Vst3NativeHostBridge.Shared.SendNoteOn(slot, ch, note, velocity);
            if (live.Checked && !routed) synth.NoteOn(note, velocity, SelectedTrack);
            if (recordingActive) StartRecordedNote(note, velocity);
        }));
    }

    private void OnNoteOff(int ch, int note)
    {
        BeginInvoke((Action)(() =>
        {
            Append($"Note Off ch{ch} {note}");
            bool routed = false;
            if (routeVst3.Checked && SelectedVst3Slot is { } slot)
                routed = Vst3NativeHostBridge.Shared.SendNoteOff(slot, ch, note);
            if (!routed) synth.NoteOff(note);
            if (recordingActive)
            {
                if (sustainDown) sustainedPendingOff.Add(note);
                else FinishRecordedNote(note);
            }
        }));
    }

    private void OnControlChange(int ch, int cc, int val)
    {
        Append($"CC ch{ch} #{cc} = {val}");
        if (cc == 1) synth.ModWheel(val);
        if (routeVst3.Checked && SelectedVst3Slot is { } slot)
            Vst3NativeHostBridge.Shared.SendControlChange(slot, ch, cc, val);
    }

    private void OnPitchBend(int ch, int bend)
    {
        BeginInvoke((Action)(() =>
        {
            Append($"Pitch bend ch{ch} = {bend}");
            var range = SelectedTrack?.PitchBendRangeSemitones ?? (int)pitchRange.Value;
            synth.PitchBend(bend, range);
            if (routeVst3.Checked && SelectedVst3Slot is { } slot)
                Vst3NativeHostBridge.Shared.SendPitchBend(slot, ch, bend);
        }));
    }

    private void OnChannelEvent(int channel, MidiClipEventKind kind, int data1, int data2)
    {
        BeginInvoke((Action)(() =>
        {
            if (kind == MidiClipEventKind.SustainPedal)
            {
                var wasDown = sustainDown;
                sustainDown = data2 >= 64;
                if (wasDown && !sustainDown)
                {
                    foreach (var note in sustainedPendingOff.ToList()) FinishRecordedNote(note);
                    sustainedPendingOff.Clear();
                }
            }
            if (!recordingActive || !recordControllers.Checked || recordClip == null) return;
            recordClip.MidiEvents.Add(new MidiClipEvent
            {
                Beat = Quantize(CurrentBeat()),
                Kind = kind,
                Channel = channel,
                Data1 = data1,
                Data2 = data2
            });
            Changed?.Invoke();
        }));
    }

    private void SendPanic()
    {
        foreach (var n in Enumerable.Range(0, 128)) synth.NoteOff(n);
        if (routeVst3.Checked) Vst3NativeHostBridge.Shared.Panic(SelectedVst3Slot);
        sustainDown = false;
        sustainedPendingOff.Clear();
        Append("MIDI panic sent.");
    }

    private async Task ToggleRecordingAsync(bool enabled)
    {
        if (!enabled)
        {
            StopMidiRecording();
            return;
        }

        var t = SelectedTrack;
        if (t == null) { record.Checked = false; Append("Pick an instrument/MIDI track before recording."); return; }
        if (Project == null) { record.Checked = false; record.Enabled = true; Append("No project loaded."); return; }
        Project.CountInEnabled = countIn.Checked;
        Project.RecordCountInBars = (int)countBars.Value;
        Project.MidiRecordMode = modeBox.SelectedItem?.ToString() == "Replace" ? MidiRecordMode.Replace : MidiRecordMode.Overdub;
        Project.QuantizeOnRecord = quantizeBox.SelectedIndex > 0;
        Project.QuantizeGridBeats = IndexToGrid(quantizeBox.SelectedIndex);

        record.Enabled = false;
        var bars = countIn.Checked ? (int)countBars.Value : 0;
        if (bars > 0)
        {
            countInPending = true;
            Append($"MIDI count-in: {bars} bar(s).");
            await Task.Delay(TimeSpan.FromSeconds((bars * Math.Max(1, Project.BeatsPerBar)) * 60.0 / Math.Max(1.0, Project.Tempo)));
            countInPending = false;
            if (!record.Checked || IsDisposed) { record.Enabled = true; return; }
        }
        record.Enabled = true;
        StartMidiRecording(t);
    }

    private void StartMidiRecording(Track t)
    {
        var start = (double)startBeat.Value;
        var length = (double)lengthBeats.Value;
        recordClip = new ProjectClip { Type = ClipType.Midi, Name = "MIDI Take " + (t.Clips.Count + 1), StartBeat = start, LengthBeats = length };
        if (modeBox.SelectedItem?.ToString() == "Replace")
        {
            t.Clips.RemoveAll(c => c.Type == ClipType.Midi && RangesOverlap(start, start + length, c.StartBeat, c.StartBeat + c.LengthBeats));
            Append("Replace mode: removed overlapping MIDI clips on target track.");
        }
        t.Clips.Add(recordClip);
        t.Armed = true;
        active.Clear();
        sustainedPendingOff.Clear();
        sustainDown = false;
        recordingActive = true;
        clock.Restart();
        Append($"Recording MIDI to {t.Name} / {recordClip.Name} at beat {start:0.##} ({modeBox.SelectedItem}, quantize {quantizeBox.SelectedItem}).");
        Changed?.Invoke();
    }

    private void StopMidiRecording()
    {
        if (countInPending) Append("MIDI count-in cancelled.");
        foreach (var note in active.Keys.ToList()) FinishRecordedNote(note);
        active.Clear();
        sustainedPendingOff.Clear();
        clock.Reset();
        recordingActive = false;
        recordClip = null;
        Append("MIDI recording stopped.");
        Changed?.Invoke();
    }

    private double CurrentBeat()
    {
        var bpm = Project?.Tempo > 0 ? Project!.Tempo : 120;
        return (double)startBeat.Value + clock.Elapsed.TotalSeconds * bpm / 60.0;
    }

    private void StartRecordedNote(int note, int velocity)
    {
        active[note] = (Quantize(CurrentBeat()), velocity);
    }

    private void FinishRecordedNote(int note)
    {
        if (recordClip == null || !active.TryGetValue(note, out var start)) return;
        active.Remove(note);
        double end = Quantize(CurrentBeat());
        double len = Math.Max(0.0625, end - start.Beat);
        // Store note positions clip-relative, matching the renderer/piano roll.
        var relStart = Math.Max(0, start.Beat - recordClip.StartBeat);
        recordClip.Notes.Add(new MidiNote(relStart, len, note, start.Velocity));
        recordClip.LengthBeats = Math.Max(recordClip.LengthBeats, relStart + len);
        Changed?.Invoke();
    }

    private double Quantize(double beat)
    {
        if (quantizeBox.SelectedIndex <= 0) return beat;
        var grid = IndexToGrid(quantizeBox.SelectedIndex);
        return Math.Round(beat / grid) * grid;
    }

    private static double IndexToGrid(int index) => index switch
    {
        1 => 1.0,
        2 => 0.5,
        3 => 0.25,
        4 => 0.125,
        _ => 0.25
    };

    private static int GridToIndex(double grid)
    {
        if (Math.Abs(grid - 1.0) < 0.001) return 1;
        if (Math.Abs(grid - 0.5) < 0.001) return 2;
        if (Math.Abs(grid - 0.25) < 0.001) return 3;
        if (Math.Abs(grid - 0.125) < 0.001) return 4;
        return 0;
    }

    private static bool RangesOverlap(double a0, double a1, double b0, double b1) => a0 < b1 && b0 < a1;

    private void Append(string msg)
    {
        if (IsDisposed) return;
        var line = $"[{DateTime.Now:HH:mm:ss}] {msg}\r\n";
        if (InvokeRequired) BeginInvoke((Action)(() => Append(msg)));
        else { log.AppendText(line); ExternalLog?.Invoke(msg); }
    }
}
