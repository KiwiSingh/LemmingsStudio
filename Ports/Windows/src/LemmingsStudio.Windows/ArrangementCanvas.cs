namespace LemmingsStudio.Windows;

public sealed class ArrangementCanvas : Control
{
    public StudioProject Project { get; set; } = StudioProject.New();
    public HashSet<Guid> SelectedClipIds { get; } = new();
    public event Action? ProjectChanged;
    public event Action<ProjectClip?>? ClipSelectionChanged;
    public event Action<string>? Log;

    private readonly Dictionary<RectangleF, (Track Track, ProjectClip Clip)> clipHitMap = new();
    private Rectangle? marquee;
    private Point marqueeStart;
    private bool draggingMarquee;
    private const int TrackHeight = 82;
    private const int HeaderWidth = 150;
    private const float PixelsPerBeat = 56f;

    public ArrangementCanvas()
    {
        DoubleBuffered = true;
        AllowDrop = true;
        BackColor = Color.FromArgb(26, 28, 34);
        DragEnter += OnDragEnter;
        DragDrop += OnDragDrop;
        MouseDown += OnMouseDown;
        MouseMove += OnMouseMove;
        MouseUp += OnMouseUp;
    }

    public ProjectClip? PrimarySelection => Project.Tracks.SelectMany(t => t.Clips).FirstOrDefault(c => SelectedClipIds.Contains(c.Id));

    protected override void OnPaint(PaintEventArgs e)
    {
        base.OnPaint(e);
        var g = e.Graphics;
        g.Clear(BackColor);
        clipHitMap.Clear();
        using var gridPen = new Pen(Color.FromArgb(55, 255, 255, 255));
        using var barPen = new Pen(Color.FromArgb(85, 255, 255, 255));
        using var textBrush = new SolidBrush(Color.Gainsboro);
        using var headerBrush = new SolidBrush(Color.FromArgb(34, 37, 46));
        using var audioBrush = new SolidBrush(Color.FromArgb(66, 147, 245));
        using var midiBrush = new SolidBrush(Color.FromArgb(172, 112, 255));
        using var selectedPen = new Pen(Color.White, 2);

        int totalHeight = Math.Max(Height, Project.Tracks.Count * TrackHeight + 40);
        for (int beat = 0; beat < 160; beat++)
        {
            float x = HeaderWidth + beat * PixelsPerBeat;
            g.DrawLine(beat % 4 == 0 ? barPen : gridPen, x, 0, x, totalHeight);
            if (beat % 4 == 0) g.DrawString($"{beat / 4 + 1}", Font, textBrush, x + 3, 4);
        }

        for (int i = 0; i < Project.Tracks.Count; i++)
        {
            var track = Project.Tracks[i];
            int y = 28 + i * TrackHeight;
            g.FillRectangle(headerBrush, 0, y, HeaderWidth, TrackHeight - 1);
            g.DrawString(track.Name, Font, textBrush, 10, y + 10);
            g.DrawString(track.Type.ToString(), Font, Brushes.Gray, 10, y + 30);
            using var lanePen = new Pen(Color.FromArgb(45, 255, 255, 255));
            g.DrawLine(lanePen, 0, y + TrackHeight - 1, Width, y + TrackHeight - 1);

            foreach (var clip in track.Clips)
            {
                float x = HeaderWidth + (float)clip.StartBeat * PixelsPerBeat;
                float w = Math.Max(34, (float)clip.LengthBeats * PixelsPerBeat);
                var rect = new RectangleF(x, y + 10, w, TrackHeight - 20);
                clipHitMap[rect] = (track, clip);
                g.FillRoundedRectangle(clip.Type == ClipType.Audio ? audioBrush : midiBrush, rect, 7);
                if (SelectedClipIds.Contains(clip.Id)) g.DrawRoundedRectangle(selectedPen, rect, 7);
                g.DrawString(clip.Name, Font, Brushes.White, rect.X + 8, rect.Y + 8);
                if (clip.Type == ClipType.Audio) DrawFakeWaveform(g, rect);
                else DrawMidiNotes(g, rect, clip);
            }
        }

        if (marquee.HasValue)
        {
            using var fill = new SolidBrush(Color.FromArgb(45, 255, 255, 255));
            using var pen = new Pen(Color.White, 1) { DashStyle = System.Drawing.Drawing2D.DashStyle.Dash };
            g.FillRectangle(fill, marquee.Value);
            g.DrawRectangle(pen, marquee.Value);
        }
    }

    private static void DrawFakeWaveform(Graphics g, RectangleF rect)
    {
        using var pen = new Pen(Color.FromArgb(170, 255, 255, 255));
        float mid = rect.Top + rect.Height * 0.62f;
        var rand = new Random(rect.GetHashCode());
        for (float x = rect.Left + 6; x < rect.Right - 6; x += 4)
        {
            float amp = 6 + (float)rand.NextDouble() * (rect.Height * 0.28f);
            g.DrawLine(pen, x, mid - amp, x, mid + amp);
        }
    }

    private static void DrawMidiNotes(Graphics g, RectangleF rect, ProjectClip clip)
    {
        using var b = new SolidBrush(Color.FromArgb(190, 255, 255, 255));
        var notes = clip.Notes.Count > 0 ? clip.Notes : new List<MidiNote> { new(0, .5, 60, 100), new(1, .5, 64, 100), new(2, .5, 67, 100) };
        foreach (var n in notes)
        {
            float x = rect.Left + (float)(n.Beat / Math.Max(.1, clip.LengthBeats)) * rect.Width;
            float w = Math.Max(6, (float)(n.Length / Math.Max(.1, clip.LengthBeats)) * rect.Width);
            float y = rect.Bottom - 12 - ((n.Note - 36) % 36) * (rect.Height - 24) / 36f;
            g.FillRectangle(b, x, y, w, 5);
        }
    }

    private void OnMouseDown(object? sender, MouseEventArgs e)
    {
        if (e.Button != MouseButtons.Left) return;
        var hit = HitTest(e.Location);
        if (hit.Clip != null)
        {
            if ((ModifierKeys & (Keys.Control | Keys.Shift)) != 0)
            {
                if (!SelectedClipIds.Add(hit.Clip.Id)) SelectedClipIds.Remove(hit.Clip.Id);
            }
            else
            {
                SelectedClipIds.Clear();
                SelectedClipIds.Add(hit.Clip.Id);
            }
            ClipSelectionChanged?.Invoke(PrimarySelection);
            Invalidate();
            return;
        }
        SelectedClipIds.Clear();
        draggingMarquee = true;
        marqueeStart = e.Location;
        marquee = new Rectangle(e.Location, Size.Empty);
        Invalidate();
    }

    private void OnMouseMove(object? sender, MouseEventArgs e)
    {
        if (!draggingMarquee) return;
        marquee = NormalizeRect(marqueeStart, e.Location);
        SelectIntersecting(marquee.Value);
        Invalidate();
    }

    private void OnMouseUp(object? sender, MouseEventArgs e)
    {
        draggingMarquee = false;
        marquee = null;
        ClipSelectionChanged?.Invoke(PrimarySelection);
        Invalidate();
    }

    private void SelectIntersecting(Rectangle rect)
    {
        SelectedClipIds.Clear();
        foreach (var pair in clipHitMap)
            if (Rectangle.Round(pair.Key).IntersectsWith(rect)) SelectedClipIds.Add(pair.Value.Clip.Id);
    }

    private (Track? Track, ProjectClip? Clip) HitTest(Point p)
    {
        foreach (var pair in clipHitMap)
            if (pair.Key.Contains(p)) return pair.Value;
        return (null, null);
    }

    private static Rectangle NormalizeRect(Point a, Point b) => Rectangle.FromLTRB(Math.Min(a.X, b.X), Math.Min(a.Y, b.Y), Math.Max(a.X, b.X), Math.Max(a.Y, b.Y));

    private void OnDragEnter(object? sender, DragEventArgs e)
    {
        if (e.Data?.GetDataPresent(DataFormats.FileDrop) == true) e.Effect = DragDropEffects.Copy;
    }

    private void OnDragDrop(object? sender, DragEventArgs e)
    {
        if (e.Data?.GetData(DataFormats.FileDrop) is not string[] files || files.Length == 0) return;
        var client = PointToClient(new Point(e.X, e.Y));
        int trackIndex = (client.Y - 28) / TrackHeight;
        Track target;
        if (trackIndex >= 0 && trackIndex < Project.Tracks.Count) target = Project.Tracks[trackIndex];
        else
        {
            target = Track.Audio("Audio " + (Project.Tracks.Count(t => t.Type == TrackType.Audio) + 1));
            Project.Tracks.Add(target);
        }
        double beat = Math.Max(0, (client.X - HeaderWidth) / PixelsPerBeat);
        foreach (var file in files)
        {
            var ext = Path.GetExtension(file).ToLowerInvariant();
            var clip = new ProjectClip
            {
                Name = Path.GetFileNameWithoutExtension(file),
                SourcePath = file,
                Type = ext is ".mid" or ".midi" ? ClipType.Midi : ClipType.Audio,
                StartBeat = beat,
                LengthBeats = 4
            };
            target.Clips.Add(clip);
            beat += clip.LengthBeats;
            Log?.Invoke($"Imported {clip.Name} to {target.Name}");
        }
        ProjectChanged?.Invoke();
        Invalidate();
    }
}

internal static class GraphicsExtensions
{
    public static void FillRoundedRectangle(this Graphics g, Brush brush, RectangleF rect, float radius)
    {
        using var path = Rounded(rect, radius);
        g.FillPath(brush, path);
    }
    public static void DrawRoundedRectangle(this Graphics g, Pen pen, RectangleF rect, float radius)
    {
        using var path = Rounded(rect, radius);
        g.DrawPath(pen, path);
    }
    private static System.Drawing.Drawing2D.GraphicsPath Rounded(RectangleF r, float radius)
    {
        var path = new System.Drawing.Drawing2D.GraphicsPath();
        float d = radius * 2;
        path.AddArc(r.X, r.Y, d, d, 180, 90);
        path.AddArc(r.Right - d, r.Y, d, d, 270, 90);
        path.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
        path.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
        path.CloseFigure();
        return path;
    }
}
