namespace LemmingsStudio.Windows;

/// <summary>
/// Ableton-style Session/Clip Launcher parity layer. It launches existing MIDI/audio clips
/// by scene and can create new MIDI sketch clips per track, giving Windows the same broad
/// workspace shape as the macOS shell instead of only Arrangement tabs.
/// </summary>
public sealed class SessionLauncherPanel : UserControl
{
    private readonly TableLayoutPanel grid = new() { Dock = DockStyle.Fill, AutoScroll = true, CellBorderStyle = TableLayoutPanelCellBorderStyle.Single };
    public StudioProject? Project { get; set; }
    public Action? Changed { get; set; }
    public Action<ProjectClip?>? ClipSelected { get; set; }
    public Action<string>? Log { get; set; }

    public SessionLauncherPanel()
    {
        Dock = DockStyle.Fill;
        BackColor = Color.FromArgb(24, 26, 32);
        Controls.Add(grid);
    }

    public void Reload()
    {
        grid.SuspendLayout();
        grid.Controls.Clear();
        grid.RowStyles.Clear();
        grid.ColumnStyles.Clear();
        grid.ColumnCount = (Project?.Tracks.Count ?? 0) + 1;
        grid.RowCount = 10;
        grid.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 88));
        if (Project != null)
            foreach (var _ in Project.Tracks) grid.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 145));
        for (int r = 0; r < grid.RowCount; r++) grid.RowStyles.Add(new RowStyle(SizeType.Absolute, r == 0 ? 34 : 64));

        grid.Controls.Add(Cell("Scene", bold: true), 0, 0);
        if (Project != null)
        {
            for (int t = 0; t < Project.Tracks.Count; t++)
                grid.Controls.Add(Cell(Project.Tracks[t].Name, bold: true), t + 1, 0);
            for (int scene = 0; scene < 9; scene++)
            {
                grid.Controls.Add(Cell((scene + 1).ToString(), bold: true), 0, scene + 1);
                double beat = scene * 4.0;
                for (int t = 0; t < Project.Tracks.Count; t++)
                    grid.Controls.Add(Slot(Project.Tracks[t], scene, beat), t + 1, scene + 1);
            }
        }
        grid.ResumeLayout();
    }

    private Control Slot(Track track, int scene, double beat)
    {
        var clip = track.Clips.FirstOrDefault(c => Math.Abs(c.StartBeat - beat) < 0.001);
        var button = new Button
        {
            Dock = DockStyle.Fill,
            Text = clip != null ? $"▶ {clip.Name}" : "+ Clip",
            BackColor = clip?.Type == ClipType.Audio ? Color.FromArgb(52, 108, 180) : Color.FromArgb(96, 62, 154),
            ForeColor = Color.White,
            FlatStyle = FlatStyle.Flat,
            Tag = clip
        };
        button.Click += (_, _) =>
        {
            if (clip != null)
            {
                ClipSelected?.Invoke(clip);
                Log?.Invoke($"Selected scene {scene + 1}: {clip.Name}");
            }
            else
            {
                var created = new ProjectClip
                {
                    Type = ClipType.Midi,
                    Name = $"Scene {scene + 1}",
                    StartBeat = beat,
                    LengthBeats = 4,
                    Notes = new List<MidiNote> { new(0, 1, 60, 100), new(1, 1, 63, 96), new(2, 1, 67, 104), new(3, 1, 70, 90) }
                };
                track.Clips.Add(created);
                ClipSelected?.Invoke(created);
                Changed?.Invoke();
            }
        };
        return button;
    }

    private static Control Cell(string text, bool bold = false) => new Label
    {
        Text = text,
        Dock = DockStyle.Fill,
        TextAlign = ContentAlignment.MiddleCenter,
        BackColor = Color.FromArgb(34, 37, 46),
        ForeColor = Color.Gainsboro,
        Font = new Font("Segoe UI", 9, bold ? FontStyle.Bold : FontStyle.Regular)
    };
}
