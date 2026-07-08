namespace LemmingsStudio.Windows;

/// <summary>
/// Native Windows parity implementation of the macOS Step Sequencer workspace.
/// This is intentionally stateful and real: grid edits mutate Track.StepPattern,
/// playback renders active sequencer tracks, and Print creates editable MIDI clips.
/// </summary>
public sealed class StepSequencerPanel : UserControl
{
    private readonly ComboBox trackBox = new() { DropDownStyle = ComboBoxStyle.DropDownList, Width = 220 };
    private readonly CheckBox driveCheck = new() { Text = "Drive track from sequencer", AutoSize = true, Checked = true };
    private readonly NumericUpDown stepsBox = new() { Minimum = 4, Maximum = 64, Increment = 4, Value = 16, Width = 64 };
    private readonly NumericUpDown spbBox = new() { Minimum = 1, Maximum = 8, Value = 4, Width = 52 };
    private readonly Panel gridHost = new() { Dock = DockStyle.Fill, AutoScroll = true, BackColor = Color.FromArgb(24, 24, 28) };
    private readonly ToolStrip toolbar = new() { Dock = DockStyle.Top, GripStyle = ToolStripGripStyle.Hidden };

    public StudioProject? Project { get; set; }
    public Action? Changed { get; set; }
    public Action<string>? Log { get; set; }

    private Track? SelectedTrack => trackBox.SelectedItem as Track;

    public StepSequencerPanel()
    {
        Dock = DockStyle.Fill;
        var header = new Panel { Dock = DockStyle.Top, Height = 42, Padding = new Padding(8), BackColor = Color.FromArgb(32, 32, 38) };
        trackBox.DisplayMember = nameof(Track.Name);
        trackBox.SelectedIndexChanged += (_, _) => LoadSelectedTrack();
        driveCheck.CheckedChanged += (_, _) => { if (SelectedTrack is { } t) { t.UseStepSequencer = driveCheck.Checked; Changed?.Invoke(); } };
        header.Controls.Add(new Label { Text = "Step Sequencer", AutoSize = true, ForeColor = Color.White, Font = new Font(SystemFonts.MessageBoxFont, FontStyle.Bold), Left = 8, Top = 12 });
        trackBox.Left = 132; trackBox.Top = 8; header.Controls.Add(trackBox);
        driveCheck.Left = 370; driveCheck.Top = 11; driveCheck.ForeColor = Color.Gainsboro; header.Controls.Add(driveCheck);

        AddButton("New Sequencer", (_, _) => NewSequencerTrack());
        AddButton("Tech House Kit", (_, _) => ApplyKit("Tech House"));
        AddButton("Guaracha", (_, _) => ApplyKit("Guaracha"));
        AddButton("EDM", (_, _) => ApplyKit("EDM"));
        AddButton("Lo-Fi", (_, _) => ApplyKit("Lo-Fi"));
        AddSeparator();
        AddButton("Clear", (_, _) => { if (SelectedTrack is { } t) { t.StepPattern.Clear(); RebuildGrid(); Changed?.Invoke(); } });
        AddButton("Print to Arrangement", (_, _) => PrintToArrangement());
        AddSeparator();
        toolbar.Items.Add(new ToolStripLabel("Steps"));
        toolbar.Items.Add(new ToolStripControlHost(stepsBox));
        toolbar.Items.Add(new ToolStripLabel("Steps/beat"));
        toolbar.Items.Add(new ToolStripControlHost(spbBox));
        stepsBox.ValueChanged += (_, _) => ResizePattern();
        spbBox.ValueChanged += (_, _) => ResizePattern();

        gridHost.AllowDrop = true;
        gridHost.DragEnter += OnGridDragEnter;
        gridHost.DragDrop += OnGridDragDrop;

        Controls.Add(gridHost);
        Controls.Add(toolbar);
        Controls.Add(header);
    }


    private void OnGridDragEnter(object? sender, DragEventArgs e)
    {
        if (e.Data?.GetDataPresent(DataFormats.FileDrop) == true || e.Data?.GetDataPresent(SpliceDropBroker.DataFormat) == true)
            e.Effect = DragDropEffects.Copy;
    }

    private async void OnGridDragDrop(object? sender, DragEventArgs e)
    {
        if (SelectedTrack is not { } track)
        {
            Log?.Invoke("Select a sequencer track before dropping a sample.");
            return;
        }

        string? path = null;
        string name = "Sample";
        if (e.Data?.GetDataPresent(SpliceDropBroker.DataFormat) == true
            && e.Data.GetData(SpliceDropBroker.DataFormat) is Features.SpliceSample sample)
        {
            var asset = await SpliceDropBroker.ResolveAsync(sample);
            if (asset == null) { Log?.Invoke("Splice Fetch on Drop failed; sequencer lane unchanged."); return; }
            path = asset.FilePath; name = asset.Name;
        }
        else if (e.Data?.GetData(DataFormats.FileDrop) is string[] files && files.Length > 0)
        {
            path = files[0]; name = Path.GetFileNameWithoutExtension(path);
        }

        if (string.IsNullOrEmpty(path)) return;
        var client = gridHost.PointToClient(new Point(e.X, e.Y));
        int row = Math.Max(0, (client.Y - 44) / 32);
        if (track.SequencerLayers.Count == 0) track.SequencerLayers = SequencerLayer.DefaultKit();
        SequencerLayer layer;
        if (row < track.SequencerLayers.Count) layer = track.SequencerLayers[row];
        else
        {
            layer = new SequencerLayer { Name = name, Note = Math.Min(127, 60 + track.SequencerLayers.Count) };
            track.SequencerLayers.Add(layer);
        }
        layer.Name = name; layer.SourcePath = path; track.UseStepSequencer = true;
        RebuildGrid(); Changed?.Invoke(); Log?.Invoke($"Loaded sample {name} into sequencer lane {layer.Name}.");
    }

    private void AddButton(string text, EventHandler click)
    {
        var b = new ToolStripButton(text) { DisplayStyle = ToolStripItemDisplayStyle.Text };
        b.Click += click;
        toolbar.Items.Add(b);
    }
    private void AddSeparator() => toolbar.Items.Add(new ToolStripSeparator());

    public void Reload()
    {
        var old = SelectedTrack?.Id;
        trackBox.Items.Clear();
        if (Project != null)
        {
            foreach (var track in Project.Tracks.Where(t => t.Type is TrackType.Instrument or TrackType.Midi)) trackBox.Items.Add(track);
        }
        if (trackBox.Items.Count > 0)
        {
            var idx = Enumerable.Range(0, trackBox.Items.Count).FirstOrDefault(i => ((Track)trackBox.Items[i]!).Id == old);
            trackBox.SelectedIndex = idx >= 0 && idx < trackBox.Items.Count ? idx : 0;
        }
        else RebuildGrid();
    }

    private void LoadSelectedTrack()
    {
        if (SelectedTrack is { } t)
        {
            t.StepPattern ??= StepPattern.DefaultDrumPattern();
            if (t.SequencerLayers == null || t.SequencerLayers.Count == 0) t.SequencerLayers = SequencerLayer.DefaultKit();
            driveCheck.Checked = t.UseStepSequencer;
            stepsBox.Value = Math.Clamp(t.StepPattern.StepCount, (int)stepsBox.Minimum, (int)stepsBox.Maximum);
            spbBox.Value = Math.Clamp(t.StepPattern.StepsPerBeat, (int)spbBox.Minimum, (int)spbBox.Maximum);
        }
        RebuildGrid();
    }

    private void ResizePattern()
    {
        if (SelectedTrack is not { } t) return;
        t.StepPattern.StepCount = (int)stepsBox.Value;
        t.StepPattern.StepsPerBeat = (int)spbBox.Value;
        t.StepPattern.Hits.RemoveAll(h => h.Step >= t.StepPattern.StepCount);
        RebuildGrid();
        Changed?.Invoke();
    }

    private void NewSequencerTrack()
    {
        if (Project == null) return;
        var track = Track.Instrument("Sequencer " + (Project.Tracks.Count + 1));
        track.UseStepSequencer = true;
        track.Devices.Clear();
        track.Devices.Add(DeviceSlot.Stock("Drum Machine"));
        track.SequencerLayers = SequencerLayer.DefaultKit();
        track.StepPattern = StepPattern.DefaultDrumPattern();
        Project.Tracks.Add(track);
        Changed?.Invoke();
        Reload();
        trackBox.SelectedItem = track;
        Log?.Invoke("Created Windows Step Sequencer track.");
    }

    private void ApplyKit(string kit)
    {
        if (SelectedTrack is not { } t) return;
        t.UseStepSequencer = true;
        t.SequencerLayers = SequencerLayer.DefaultKit();
        t.StepPattern = StepPattern.Empty((int)stepsBox.Value, (int)spbBox.Value);
        int[] kick, snare, hat, oh;
        switch (kit)
        {
            case "Guaracha": kick = new[] { 0, 3, 7, 11 }; snare = new[] { 4, 12 }; hat = new[] { 2, 6, 10, 14 }; oh = new[] { 15 }; break;
            case "EDM": kick = new[] { 0, 4, 8, 12 }; snare = new[] { 4, 12 }; hat = new[] { 2, 6, 10, 14 }; oh = new[] { 6, 14 }; break;
            case "Lo-Fi": kick = new[] { 0, 7, 10 }; snare = new[] { 4, 12 }; hat = new[] { 2, 5, 8, 11, 14 }; oh = Array.Empty<int>(); break;
            default: kick = new[] { 0, 4, 8, 12 }; snare = new[] { 4, 12 }; hat = new[] { 2, 6, 10, 14 }; oh = new[] { 15 }; break;
        }
        foreach (var s in kick) t.StepPattern.Set(s, 36, true, 124);
        foreach (var s in snare) t.StepPattern.Set(s, 38, true, 112);
        foreach (var s in hat) t.StepPattern.Set(s, 42, true, 84);
        foreach (var s in oh) t.StepPattern.Set(s, 46, true, 70);
        RebuildGrid();
        Changed?.Invoke();
        Log?.Invoke($"Applied {kit} kit/groove.");
    }

    private void RebuildGrid()
    {
        gridHost.Controls.Clear();
        if (SelectedTrack is not { } t)
        {
            gridHost.Controls.Add(new Label { Text = "Create or select an instrument/sequencer track.", AutoSize = true, ForeColor = Color.Gainsboro, Left = 24, Top = 24 });
            return;
        }
        var pattern = t.StepPattern;
        var layers = t.SequencerLayers.Count > 0 ? t.SequencerLayers : SequencerLayer.DefaultKit();
        int cell = 32, rowH = 32, labelW = 160;
        var table = new Panel { Left = 12, Top = 12, Width = labelW + pattern.StepCount * cell + 60, Height = 34 + layers.Count * rowH + 40, BackColor = Color.FromArgb(24, 24, 28) };
        for (int s = 0; s < pattern.StepCount; s++)
        {
            var lab = new Label { Text = (s + 1).ToString(), ForeColor = s % pattern.StepsPerBeat == 0 ? Color.White : Color.Gray, TextAlign = ContentAlignment.MiddleCenter, Left = labelW + s * cell, Top = 4, Width = cell, Height = 22 };
            table.Controls.Add(lab);
        }
        for (int r = 0; r < layers.Count; r++)
        {
            var layer = layers[r];
            int y = 32 + r * rowH;
            var name = new Label { Text = layer.Name, ForeColor = Color.Gainsboro, TextAlign = ContentAlignment.MiddleRight, Left = 0, Top = y + 2, Width = labelW - 8, Height = 26 };
            table.Controls.Add(name);
            for (int s = 0; s < pattern.StepCount; s++)
            {
                var step = s;
                var b = new Button { Left = labelW + s * cell + 3, Top = y + 3, Width = 25, Height = 24, FlatStyle = FlatStyle.Flat, Text = "" };
                b.FlatAppearance.BorderColor = Color.FromArgb(54, 54, 62);
                PaintStepButton(b, pattern.IsOn(step, layer.Note), step, pattern.StepsPerBeat);
                b.Click += (_, _) => { pattern.Toggle(step, layer.Note); PaintStepButton(b, pattern.IsOn(step, layer.Note), step, pattern.StepsPerBeat); Changed?.Invoke(); };
                b.MouseUp += (_, e) => { if (e.Button == MouseButtons.Right) { pattern.ClearLane(layer.Note); RebuildGrid(); Changed?.Invoke(); } };
                table.Controls.Add(b);
            }
        }
        gridHost.Controls.Add(table);
    }

    private static void PaintStepButton(Button b, bool on, int step, int spb)
    {
        b.BackColor = on ? Color.FromArgb(0, 190, 135) : (step % Math.Max(1, spb) == 0 ? Color.FromArgb(50, 50, 58) : Color.FromArgb(38, 38, 44));
        b.FlatAppearance.BorderSize = on ? 2 : 1;
        b.FlatAppearance.BorderColor = on ? Color.WhiteSmoke : Color.FromArgb(60, 60, 68);
    }

    private void PrintToArrangement()
    {
        if (Project == null || SelectedTrack is not { } t) return;
        var clip = BuildMidiClipFromPattern(t, t.Name + " Pattern", 0);
        var outTrack = Track.Instrument(t.Name + " Print");
        outTrack.Devices = t.Devices.Select(d => new DeviceSlot { Name = d.Name, Enabled = d.Enabled, Parameters = new Dictionary<string, double>(d.Parameters) }).ToList();
        outTrack.Clips.Add(clip);
        Project.Tracks.Add(outTrack);
        Changed?.Invoke();
        Log?.Invoke($"Printed {t.Name} step pattern to editable MIDI arrangement clip.");
    }

    public static ProjectClip BuildMidiClipFromPattern(Track track, string name, double startBeat)
    {
        var p = track.StepPattern;
        double stepLen = 1.0 / Math.Max(1, p.StepsPerBeat);
        var clip = new ProjectClip { Type = ClipType.Midi, Name = name, StartBeat = startBeat, LengthBeats = p.StepCount * stepLen };
        foreach (var hit in p.Hits.OrderBy(h => h.Step).ThenBy(h => h.Note))
        {
            var layer = track.SequencerLayers.FirstOrDefault(l => l.Note == hit.Note);
            int note = hit.Note + (layer?.OctaveOffset ?? 0) * 12;
            clip.Notes.Add(new MidiNote(hit.Step * stepLen, Math.Min(stepLen * 0.9, 0.24), note, hit.Velocity));
        }
        return clip;
    }
}
