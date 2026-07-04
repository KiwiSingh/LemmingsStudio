namespace LemmingsStudio.Windows;

/// <summary>Minimal but real Piano Roll workspace for Windows parity: select a MIDI clip,
/// click the grid to add notes, right-click notes to delete, and edits render/export.</summary>
public sealed class PianoRollPanel : UserControl
{
    private readonly ComboBox trackBox = new() { DropDownStyle = ComboBoxStyle.DropDownList, Width = 210 };
    private readonly ComboBox clipBox = new() { DropDownStyle = ComboBoxStyle.DropDownList, Width = 210 };
    private readonly NumericUpDown lengthBox = new() { Minimum = 1, Maximum = 16, Value = 1, Width = 52 };
    private readonly NumericUpDown velocityBox = new() { Minimum = 1, Maximum = 127, Value = 100, Width = 60 };
    private readonly RollCanvas canvas = new() { Dock = DockStyle.Fill };
    public StudioProject? Project { get; set; }
    public Action? Changed { get; set; }

    public PianoRollPanel()
    {
        Dock = DockStyle.Fill;
        var top = new FlowLayoutPanel { Dock = DockStyle.Top, Height = 42, Padding = new Padding(6), BackColor = Color.FromArgb(32, 32, 38) };
        top.Controls.Add(new Label { Text = "Piano Roll", AutoSize = true, ForeColor = Color.White, Padding = new Padding(0, 8, 10, 0), Font = new Font(SystemFonts.MessageBoxFont, FontStyle.Bold) });
        top.Controls.Add(trackBox); top.Controls.Add(clipBox);
        top.Controls.Add(new Label { Text = "Length steps", AutoSize = true, ForeColor = Color.Gainsboro, Padding = new Padding(10, 8, 0, 0) }); top.Controls.Add(lengthBox);
        top.Controls.Add(new Label { Text = "Velocity", AutoSize = true, ForeColor = Color.Gainsboro, Padding = new Padding(10, 8, 0, 0) }); top.Controls.Add(velocityBox);
        var newClip = new Button { Text = "New MIDI Clip" }; newClip.Click += (_, _) => CreateClip(); top.Controls.Add(newClip);
        var quantize = new Button { Text = "Quantize 1/16" }; quantize.Click += (_, _) => Quantize(); top.Controls.Add(quantize);
        trackBox.DisplayMember = nameof(Track.Name);
        clipBox.DisplayMember = nameof(ProjectClip.Name);
        trackBox.SelectedIndexChanged += (_, _) => ReloadClips();
        clipBox.SelectedIndexChanged += (_, _) => BindCanvas();
        canvas.NoteEdited += () => { Changed?.Invoke(); canvas.Invalidate(); };
        canvas.LengthSteps = () => (int)lengthBox.Value;
        canvas.Velocity = () => (int)velocityBox.Value;
        Controls.Add(canvas);
        Controls.Add(top);
    }

    public void Reload()
    {
        var oldTrack = (trackBox.SelectedItem as Track)?.Id;
        trackBox.Items.Clear();
        if (Project != null) foreach (var t in Project.Tracks.Where(t => t.Type is TrackType.Instrument or TrackType.Midi)) trackBox.Items.Add(t);
        if (trackBox.Items.Count > 0)
        {
            var idx = Enumerable.Range(0, trackBox.Items.Count).FirstOrDefault(i => ((Track)trackBox.Items[i]!).Id == oldTrack);
            trackBox.SelectedIndex = idx >= 0 && idx < trackBox.Items.Count ? idx : 0;
        }
        else ReloadClips();
    }

    private Track? SelectedTrack => trackBox.SelectedItem as Track;
    private ProjectClip? SelectedClip => clipBox.SelectedItem as ProjectClip;

    private void ReloadClips()
    {
        var old = SelectedClip?.Id;
        clipBox.Items.Clear();
        if (SelectedTrack != null) foreach (var c in SelectedTrack.Clips.Where(c => c.Type == ClipType.Midi)) clipBox.Items.Add(c);
        if (clipBox.Items.Count > 0)
        {
            var idx = Enumerable.Range(0, clipBox.Items.Count).FirstOrDefault(i => ((ProjectClip)clipBox.Items[i]!).Id == old);
            clipBox.SelectedIndex = idx >= 0 && idx < clipBox.Items.Count ? idx : 0;
        }
        BindCanvas();
    }

    private void BindCanvas()
    {
        canvas.Clip = SelectedClip;
        canvas.Invalidate();
    }

    private void CreateClip()
    {
        if (SelectedTrack is not { } t) return;
        var clip = new ProjectClip { Type = ClipType.Midi, Name = "MIDI Clip " + (t.Clips.Count + 1), StartBeat = 0, LengthBeats = 4 };
        t.Clips.Add(clip);
        Changed?.Invoke();
        ReloadClips();
        clipBox.SelectedItem = clip;
    }

    private void Quantize()
    {
        if (SelectedClip is not { } c) return;
        c.Notes = c.Notes.Select(n => n with { Beat = Math.Round(n.Beat * 4.0) / 4.0, Length = Math.Max(0.0625, Math.Round(n.Length * 4.0) / 4.0) }).OrderBy(n => n.Beat).ToList();
        Changed?.Invoke(); canvas.Invalidate();
    }

    private sealed class RollCanvas : Control
    {
        public ProjectClip? Clip { get; set; }
        public Action? NoteEdited { get; set; }
        public Func<int>? LengthSteps { get; set; }
        public Func<int>? Velocity { get; set; }
        private const int NoteMin = 36, NoteMax = 84;
        private const int KeyW = 72, StepW = 28, RowH = 12;
        public RollCanvas() { DoubleBuffered = true; BackColor = Color.FromArgb(22,22,26); }
        protected override void OnPaint(PaintEventArgs e)
        {
            var g = e.Graphics; g.Clear(BackColor);
            if (Clip == null) { using var br = new SolidBrush(Color.Gainsboro); g.DrawString("Select or create a MIDI clip.", Font, br, 24, 24); return; }
            int rows = NoteMax - NoteMin + 1; int steps = Math.Max(16, (int)Math.Ceiling(Clip.LengthBeats * 4));
            using var grid = new Pen(Color.FromArgb(42,42,48)); using var beat = new Pen(Color.FromArgb(68,68,78));
            using var text = new SolidBrush(Color.Gainsboro); using var noteBrush = new SolidBrush(Color.FromArgb(0, 190, 135));
            for (int r=0;r<rows;r++)
            {
                int y = r * RowH; int note = NoteMax-r;
                if (note % 12 == 0) g.FillRectangle(new SolidBrush(Color.FromArgb(30,30,36)), 0, y, Width, RowH);
                g.DrawString(NoteName(note), Font, text, 4, y-2); g.DrawLine(grid, KeyW, y, Width, y);
            }
            for (int s=0;s<=steps;s++) g.DrawLine(s%4==0?beat:grid, KeyW + s*StepW, 0, KeyW + s*StepW, rows*RowH);
            foreach (var n in Clip.Notes)
            {
                int x = KeyW + (int)Math.Round(n.Beat*4)*StepW;
                int y = (NoteMax - n.Note) * RowH;
                int w = Math.Max(8, (int)Math.Round(n.Length*4)*StepW - 2);
                g.FillRectangle(noteBrush, x+1, y+1, w, RowH-2);
            }
        }
        protected override void OnMouseDown(MouseEventArgs e)
        {
            if (Clip == null || e.X < KeyW) return;
            int step = Math.Max(0, (e.X - KeyW) / StepW);
            int note = NoteMax - Math.Clamp(e.Y / RowH, 0, NoteMax-NoteMin);
            double beat = step / 4.0;
            var hit = Clip.Notes.FirstOrDefault(n => Math.Abs(n.Beat-beat)<0.001 && n.Note==note);
            if (e.Button == MouseButtons.Right)
            {
                Clip.Notes.RemoveAll(n => Math.Abs(n.Beat-beat)<0.001 && n.Note==note);
            }
            else if (hit == null)
            {
                var len = Math.Max(1, LengthSteps?.Invoke() ?? 1) / 4.0;
                Clip.Notes.Add(new MidiNote(beat, len, note, Velocity?.Invoke() ?? 100));
                Clip.Notes = Clip.Notes.OrderBy(n => n.Beat).ThenBy(n => n.Note).ToList();
                Clip.LengthBeats = Math.Max(Clip.LengthBeats, beat + len);
            }
            NoteEdited?.Invoke();
        }
        private static string NoteName(int n) { string[] names = {"C","C#","D","D#","E","F","F#","G","G#","A","A#","B"}; return names[n%12] + (n/12-1); }
    }
}
