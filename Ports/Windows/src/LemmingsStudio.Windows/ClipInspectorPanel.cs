namespace LemmingsStudio.Windows;

/// <summary>
/// Mac-style lower inspector deck for selected clips and the selected track.
/// Replaces the old raw PropertyGrid for the common production controls users
/// actually need while recording: clip gain/pitch/warp, start/length, and track
/// mute/solo/arm/volume/pan.
/// </summary>
public sealed class ClipInspectorPanel : UserControl
{
    private readonly FlowLayoutPanel body = new() { Dock = DockStyle.Fill, AutoScroll = true, FlowDirection = FlowDirection.TopDown, WrapContents = false, Padding = new Padding(10) };
    public StudioProject? Project { get; set; }
    public ProjectClip? Clip { get; private set; }
    public Action? Changed { get; set; }

    public ClipInspectorPanel()
    {
        Dock = DockStyle.Fill;
        BackColor = Color.FromArgb(24, 26, 32);
        Controls.Add(body);
        Reload(null);
    }

    public void Reload(ProjectClip? clip)
    {
        Clip = clip;
        Build();
    }

    private Track? ClipTrack => Project?.Tracks.FirstOrDefault(t => Clip != null && t.Clips.Any(c => c.Id == Clip.Id));

    private void Build()
    {
        body.SuspendLayout();
        body.Controls.Clear();
        body.Controls.Add(Header("Inspector"));
        var track = ClipTrack ?? Project?.Tracks.FirstOrDefault();
        if (Clip == null)
        {
            body.Controls.Add(TextBlock("No clip selected. Click an Arrangement clip, a Session slot, or a Piano Roll clip to edit it here."));
            if (track != null) body.Controls.Add(TrackCard(track));
            body.ResumeLayout();
            return;
        }

        body.Controls.Add(ClipCard(Clip));
        if (track != null) body.Controls.Add(TrackCard(track));
        body.ResumeLayout();
    }

    private Control ClipCard(ProjectClip clip)
    {
        var p = Card("Selected Clip");
        p.Controls.Add(LabelValue("Name", clip.Name, 10, 36));
        p.Controls.Add(Numeric("Start beat", clip.StartBeat, 0, 9999, 0.25, 10, 66, v => { clip.StartBeat = v; Fire(); }));
        p.Controls.Add(Numeric("Length beats", clip.LengthBeats, 0.25, 9999, 0.25, 10, 96, v => { clip.LengthBeats = v; Fire(); }));
        p.Controls.Add(Numeric("Clip gain", clip.Gain, 0, 4, 0.05, 10, 126, v => { clip.Gain = v; Fire(); }));
        p.Controls.Add(Numeric("Pitch semitones", clip.PitchSemitones, -24, 24, 1, 10, 156, v => { clip.PitchSemitones = (int)Math.Round(v); Fire(); }));
        p.Controls.Add(Numeric("Pitch cents", clip.PitchCents, -100, 100, 1, 10, 186, v => { clip.PitchCents = (int)Math.Round(v); Fire(); }));
        var warp = new CheckBox { Text = "Warp to project tempo", Checked = clip.WarpEnabled, Left = 10, Top = 216, Width = 180, ForeColor = Color.Gainsboro, BackColor = p.BackColor };
        warp.CheckedChanged += (_, _) => { clip.WarpEnabled = warp.Checked; Fire(); };
        p.Controls.Add(warp);
        p.Controls.Add(Numeric("Clip BPM", clip.SourceTempo, 40, 220, 1, 10, 246, v => { clip.SourceTempo = v; Fire(); }));
        var rename = new Button { Text = "Rename", Left = 10, Top = 284, Width = 90 };
        rename.Click += (_, _) => { var value = Prompt.Show("Clip name", clip.Name); if (!string.IsNullOrWhiteSpace(value)) { clip.Name = value; Fire(); Build(); } };
        p.Controls.Add(rename);
        p.Height = 326;
        return p;
    }

    private Control TrackCard(Track track)
    {
        var p = Card("Track");
        p.Controls.Add(LabelValue("Name", track.Name, 10, 36));
        p.Controls.Add(Numeric("Volume", track.Volume, 0, 1, 0.01, 10, 66, v => { track.Volume = (float)v; Fire(); }));
        p.Controls.Add(Numeric("Pan", track.Pan, -1, 1, 0.01, 10, 96, v => { track.Pan = (float)v; Fire(); }));
        var mute = Toggle("Mute", track.Muted, 10, 130, v => { track.Muted = v; Fire(); });
        var solo = Toggle("Solo", track.Solo, 92, 130, v => { track.Solo = v; Fire(); });
        var arm = Toggle("Arm", track.Armed, 174, 130, v => { track.Armed = v; Fire(); });
        p.Controls.Add(mute); p.Controls.Add(solo); p.Controls.Add(arm);
        p.Height = 176;
        return p;
    }

    private Control Header(string text) => new Label { Text = text, Font = new Font("Segoe UI", 11, FontStyle.Bold), ForeColor = Color.White, AutoSize = true, Margin = new Padding(0, 0, 0, 8) };
    private Control TextBlock(string text) => new Label { Text = text, ForeColor = Color.Silver, Width = Math.Max(320, Width - 40), Height = 42, Margin = new Padding(0, 0, 0, 8) };
    private Panel Card(string title)
    {
        var p = new Panel { Width = Math.Max(420, Width - 40), Height = 220, BackColor = Color.FromArgb(34, 37, 46), Margin = new Padding(0, 0, 0, 10) };
        p.Controls.Add(new Label { Text = title, Font = new Font("Segoe UI", 9.5f, FontStyle.Bold), ForeColor = Color.White, Left = 10, Top = 10, AutoSize = true });
        return p;
    }
    private Control LabelValue(string label, string value, int x, int y) => new Label { Text = $"{label}: {value}", ForeColor = Color.Gainsboro, Left = x, Top = y, Width = 360 };
    private Control Numeric(string label, double value, double min, double max, double step, int x, int y, Action<double> set)
    {
        var panel = new Panel { Left = x, Top = y, Width = 390, Height = 26 };
        panel.Controls.Add(new Label { Text = label, ForeColor = Color.Gainsboro, Left = 0, Top = 4, Width = 120 });
        var box = new NumericUpDown { DecimalPlaces = step < 1 ? 2 : 0, Increment = (decimal)step, Minimum = (decimal)min, Maximum = (decimal)max, Value = (decimal)Math.Clamp(value, min, max), Left = 130, Top = 0, Width = 96 };
        box.ValueChanged += (_, _) => set((double)box.Value);
        panel.Controls.Add(box);
        return panel;
    }
    private Control Toggle(string text, bool value, int x, int y, Action<bool> set)
    {
        var c = new CheckBox { Text = text, Checked = value, Left = x, Top = y, Width = 74, ForeColor = Color.Gainsboro, BackColor = Color.FromArgb(34, 37, 46) };
        c.CheckedChanged += (_, _) => set(c.Checked);
        return c;
    }
    private void Fire() { Changed?.Invoke(); }
}
