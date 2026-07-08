using NAudio.Wave;
using System.Text.Json;

namespace LemmingsStudio.Windows;

public sealed class ArrangementCanvas : Control
{
    public StudioProject Project { get; set; } = StudioProject.New();
    public HashSet<Guid> SelectedClipIds { get; } = new();
    public event Action? ProjectChanged;
    public event Action<ProjectClip?>? ClipSelectionChanged;
    public event Action<string>? Log;

    private readonly Dictionary<RectangleF, (Track Track, ProjectClip Clip)> clipHitMap = new();
    private readonly Dictionary<string, float[]> waveformCache = new(StringComparer.OrdinalIgnoreCase);
    private readonly ContextMenuStrip clipMenu = new();
    private Rectangle? marquee;
    private Point marqueeStart;
    private bool draggingMarquee;
    private DragMode dragMode;
    private Point dragStart;
    private ProjectClip? dragClip;
    private Track? dragTrack;
    private double originalStartBeat;
    private double originalLengthBeats;
    private double originalSourceOffsetBeats;
    private readonly Dictionary<Guid, double> dragOriginalStarts = new();
    private List<ClipboardClip> clipboard = new();
    private double pasteBeat;
    private int verticalScroll;
    private float horizontalScrollBeats;

    private const int BaseTrackHeight = 82;
    private const int HeaderWidth = 150;
    private const float BasePixelsPerBeat = 56f;
    private const float HandleWidth = 8f;

    public float HorizontalZoom { get; private set; } = 1f;
    public float VerticalZoom { get; private set; } = 1f;
    public double SnapGridBeats { get; private set; } = 0.25;
    public bool SnapEnabled { get; private set; } = true;
    private float PixelsPerBeat => BasePixelsPerBeat * HorizontalZoom;
    private int TrackHeight => Math.Max(44, (int)Math.Round(BaseTrackHeight * VerticalZoom));

    public ArrangementCanvas()
    {
        DoubleBuffered = true;
        AllowDrop = true;
        BackColor = Color.FromArgb(26, 28, 34);
        TabStop = true;
        BuildContextMenu();
        DragEnter += OnDragEnter;
        DragDrop += OnDragDrop;
        MouseDown += OnMouseDown;
        MouseMove += OnMouseMove;
        MouseUp += OnMouseUp;
        MouseWheel += OnMouseWheel;
        KeyDown += OnKeyDown;
    }

    public ProjectClip? PrimarySelection => Project.Tracks.SelectMany(t => t.Clips).FirstOrDefault(c => SelectedClipIds.Contains(c.Id));

    public void SetSnapGrid(double beats)
    {
        SnapGridBeats = Math.Max(1.0 / 64.0, beats);
        SnapEnabled = true;
        Log?.Invoke($"Arrangement snap grid: {SnapGridBeats:0.###} beat(s)");
        Invalidate();
    }

    public void ToggleSnap()
    {
        SnapEnabled = !SnapEnabled;
        Log?.Invoke("Arrangement snap " + (SnapEnabled ? "enabled" : "disabled"));
        Invalidate();
    }

    protected override bool IsInputKey(Keys keyData)
    {
        var code = keyData & Keys.KeyCode;
        return code is Keys.Delete or Keys.Back or Keys.Left or Keys.Right || base.IsInputKey(keyData);
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        base.OnPaint(e);
        var g = e.Graphics;
        g.Clear(BackColor);
        clipHitMap.Clear();
        using var gridPen = new Pen(Color.FromArgb(55, 255, 255, 255));
        using var barPen = new Pen(Color.FromArgb(85, 255, 255, 255));
        using var subGridPen = new Pen(Color.FromArgb(28, 255, 255, 255));
        using var textBrush = new SolidBrush(Color.Gainsboro);
        using var headerBrush = new SolidBrush(Color.FromArgb(34, 37, 46));
        using var audioBrush = new SolidBrush(Color.FromArgb(66, 147, 245));
        using var midiBrush = new SolidBrush(Color.FromArgb(172, 112, 255));
        using var selectedPen = new Pen(Color.White, 2);
        using var handleBrush = new SolidBrush(Color.FromArgb(210, 255, 255, 255));

        int totalHeight = Math.Max(Height, Project.Tracks.Count * TrackHeight + 40);
        double visibleBeats = Math.Max(32, (Width - HeaderWidth) / PixelsPerBeat + 8);
        int firstBeat = Math.Max(0, (int)Math.Floor(horizontalScrollBeats));
        int lastBeat = (int)Math.Ceiling(horizontalScrollBeats + visibleBeats);

        if (SnapEnabled && SnapGridBeats < 1)
        {
            for (double beat = Math.Floor(horizontalScrollBeats / SnapGridBeats) * SnapGridBeats; beat <= lastBeat; beat += SnapGridBeats)
            {
                float x = BeatToX(beat);
                if (x >= HeaderWidth) g.DrawLine(subGridPen, x, 0, x, totalHeight);
            }
        }
        for (int beat = firstBeat; beat <= lastBeat; beat++)
        {
            float x = BeatToX(beat);
            g.DrawLine(beat % Math.Max(1, Project.BeatsPerBar) == 0 ? barPen : gridPen, x, 0, x, totalHeight);
            if (beat % Math.Max(1, Project.BeatsPerBar) == 0)
                g.DrawString($"{beat / Math.Max(1, Project.BeatsPerBar) + 1}", Font, textBrush, x + 3, 4);
        }

        for (int i = 0; i < Project.Tracks.Count; i++)
        {
            var track = Project.Tracks[i];
            int y = 28 + i * TrackHeight - verticalScroll;
            if (y + TrackHeight < 28 || y > Height) continue;
            g.FillRectangle(headerBrush, 0, y, HeaderWidth, TrackHeight - 1);
            g.DrawString(track.Name, Font, textBrush, 10, y + 10);
            g.DrawString(track.Type.ToString() + (track.Frozen ? " • Frozen" : ""), Font, Brushes.Gray, 10, y + 30);
            using var lanePen = new Pen(Color.FromArgb(45, 255, 255, 255));
            g.DrawLine(lanePen, 0, y + TrackHeight - 1, Width, y + TrackHeight - 1);

            foreach (var clip in track.Clips)
            {
                float x = BeatToX(clip.StartBeat);
                float w = Math.Max(14, (float)clip.LengthBeats * PixelsPerBeat);
                var rect = new RectangleF(x, y + 10, w, TrackHeight - 20);
                if (rect.Right < HeaderWidth || rect.Left > Width) continue;
                clipHitMap[rect] = (track, clip);
                g.FillRoundedRectangle(clip.Type == ClipType.Audio ? audioBrush : midiBrush, rect, 7);
                if (SelectedClipIds.Contains(clip.Id))
                {
                    g.DrawRoundedRectangle(selectedPen, rect, 7);
                    g.FillRectangle(handleBrush, rect.Left + 1, rect.Top + 3, Math.Min(HandleWidth - 2, rect.Width / 3), rect.Height - 6);
                    g.FillRectangle(handleBrush, rect.Right - Math.Min(HandleWidth - 2, rect.Width / 3) - 1, rect.Top + 3, Math.Min(HandleWidth - 2, rect.Width / 3), rect.Height - 6);
                }
                g.DrawString(clip.Name, Font, Brushes.White, rect.X + 8, rect.Y + 8);
                if (clip.Type == ClipType.Audio) DrawWaveform(g, rect, clip.SourcePath);
                else DrawMidiNotes(g, rect, clip);
            }
        }

        using var headerCover = new SolidBrush(Color.FromArgb(34, 37, 46));
        g.FillRectangle(headerCover, 0, 0, HeaderWidth, 28);
        g.DrawString($"Snap: {(SnapEnabled ? SnapLabel() : "Off")}", Font, Brushes.Gainsboro, 8, 7);

        if (marquee.HasValue)
        {
            using var fill = new SolidBrush(Color.FromArgb(45, 255, 255, 255));
            using var pen = new Pen(Color.White, 1) { DashStyle = System.Drawing.Drawing2D.DashStyle.Dash };
            g.FillRectangle(fill, marquee.Value);
            g.DrawRectangle(pen, marquee.Value);
        }
    }

    private float BeatToX(double beat) => HeaderWidth + (float)(beat - horizontalScrollBeats) * PixelsPerBeat;
    private double XToBeat(float x) => Math.Max(0, horizontalScrollBeats + (x - HeaderWidth) / PixelsPerBeat);
    private double Snap(double beat) => SnapEnabled ? Math.Round(beat / SnapGridBeats) * SnapGridBeats : beat;

    private string SnapLabel() => SnapGridBeats switch
    {
        >= 4 => "1 Bar",
        1 => "1/4",
        .5 => "1/8",
        .25 => "1/16",
        .125 => "1/32",
        _ => $"{SnapGridBeats:0.###} beats"
    };

    private void DrawWaveform(Graphics g, RectangleF rect, string? sourcePath)
    {
        using var pen = new Pen(Color.FromArgb(170, 255, 255, 255));
        float mid = rect.Top + rect.Height * 0.62f;
        var peaks = GetWaveformPeaks(sourcePath, Math.Max(16, (int)rect.Width / 3));
        if (peaks.Length == 0) return;
        float step = rect.Width / peaks.Length;
        for (int i = 0; i < peaks.Length; i++)
        {
            float x = rect.Left + i * step;
            float amp = Math.Max(1, peaks[i] * rect.Height * .32f);
            g.DrawLine(pen, x, mid - amp, x, mid + amp);
        }
    }

    private float[] GetWaveformPeaks(string? path, int desiredCount)
    {
        if (string.IsNullOrWhiteSpace(path) || !File.Exists(path)) return Array.Empty<float>();
        string key = path + "|" + desiredCount;
        if (waveformCache.TryGetValue(key, out var cached)) return cached;
        try
        {
            using var reader = new AudioFileReader(path);
            int channels = Math.Max(1, reader.WaveFormat.Channels);
            long totalFrames = Math.Max(1, reader.Length / Math.Max(1, reader.WaveFormat.BlockAlign));
            int framesPerPeak = (int)Math.Max(1, totalFrames / desiredCount);
            var peaks = new List<float>(desiredCount);
            var buffer = new float[Math.Min(65536, framesPerPeak * channels)];
            float peak = 0;
            int frames = 0;
            int read;
            while ((read = reader.Read(buffer, 0, buffer.Length)) > 0)
            {
                for (int i = 0; i < read; i += channels)
                {
                    float samplePeak = 0;
                    for (int ch = 0; ch < channels && i + ch < read; ch++) samplePeak = Math.Max(samplePeak, Math.Abs(buffer[i + ch]));
                    peak = Math.Max(peak, samplePeak);
                    frames++;
                    if (frames >= framesPerPeak)
                    {
                        peaks.Add(Math.Min(1, peak)); peak = 0; frames = 0;
                        if (peaks.Count >= desiredCount) break;
                    }
                }
                if (peaks.Count >= desiredCount) break;
            }
            if (frames > 0 && peaks.Count < desiredCount) peaks.Add(Math.Min(1, peak));
            cached = peaks.ToArray();
            waveformCache[key] = cached;
            return cached;
        }
        catch { return Array.Empty<float>(); }
    }

    private static void DrawMidiNotes(Graphics g, RectangleF rect, ProjectClip clip)
    {
        using var b = new SolidBrush(Color.FromArgb(190, 255, 255, 255));
        var notes = clip.Notes.Count > 0 ? clip.Notes : new List<MidiNote>();
        foreach (var n in notes)
        {
            float x = rect.Left + (float)(n.Beat / Math.Max(.1, clip.LengthBeats)) * rect.Width;
            float w = Math.Max(3, (float)(n.Length / Math.Max(.1, clip.LengthBeats)) * rect.Width);
            float y = rect.Bottom - 12 - ((n.Note - 36) % 36) * (rect.Height - 24) / 36f;
            g.FillRectangle(b, x, y, w, 5);
        }
    }

    private void OnMouseDown(object? sender, MouseEventArgs e)
    {
        Focus();
        pasteBeat = XToBeat(e.X);
        if (e.Button == MouseButtons.Right)
        {
            var rightHit = HitTest(e.Location);
            if (rightHit.Clip != null && !SelectedClipIds.Contains(rightHit.Clip.Id))
            {
                SelectedClipIds.Clear(); SelectedClipIds.Add(rightHit.Clip.Id);
                ClipSelectionChanged?.Invoke(PrimarySelection); Invalidate();
            }
            clipMenu.Show(this, e.Location);
            return;
        }
        if (e.Button != MouseButtons.Left) return;
        var hit = HitTest(e.Location);
        if (hit.Clip != null && hit.Track != null)
        {
            if ((ModifierKeys & (Keys.Control | Keys.Shift)) != 0)
            {
                if (!SelectedClipIds.Add(hit.Clip.Id)) SelectedClipIds.Remove(hit.Clip.Id);
            }
            else if (!SelectedClipIds.Contains(hit.Clip.Id))
            {
                SelectedClipIds.Clear(); SelectedClipIds.Add(hit.Clip.Id);
            }
            ClipSelectionChanged?.Invoke(PrimarySelection);
            var rect = clipHitMap.First(kv => kv.Value.Clip.Id == hit.Clip.Id).Key;
            dragMode = e.X <= rect.Left + HandleWidth ? DragMode.TrimStart : e.X >= rect.Right - HandleWidth ? DragMode.TrimEnd : DragMode.Move;
            dragStart = e.Location; dragClip = hit.Clip; dragTrack = hit.Track;
            originalStartBeat = hit.Clip.StartBeat; originalLengthBeats = hit.Clip.LengthBeats; originalSourceOffsetBeats = hit.Clip.SourceOffsetBeats;
            dragOriginalStarts.Clear();
            foreach (var c in Project.Tracks.SelectMany(t => t.Clips).Where(c => SelectedClipIds.Contains(c.Id))) dragOriginalStarts[c.Id] = c.StartBeat;
            Capture = true;
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
        if (dragMode != DragMode.None && dragClip != null)
        {
            double delta = (e.X - dragStart.X) / PixelsPerBeat;
            switch (dragMode)
            {
                case DragMode.Move:
                    var newStart = Math.Max(0, Snap(originalStartBeat + delta));
                    double moveDelta = newStart - originalStartBeat;
                    foreach (var clip in Project.Tracks.SelectMany(t => t.Clips).Where(c => SelectedClipIds.Contains(c.Id)))
                    {
                        var cb = dragOriginalStarts.TryGetValue(clip.Id, out var start) ? start : clip.StartBeat;
                        clip.StartBeat = Math.Max(0, Snap(cb + moveDelta));
                    }
                    break;
                case DragMode.TrimStart:
                    double newTrimStart = Math.Clamp(Snap(originalStartBeat + delta), 0, originalStartBeat + originalLengthBeats - SnapGridBeats);
                    dragClip.StartBeat = newTrimStart;
                    double trimmedBeats = newTrimStart - originalStartBeat;
                    dragClip.SourceOffsetBeats = Math.Max(0, originalSourceOffsetBeats + trimmedBeats);
                    dragClip.LengthBeats = Math.Max(SnapGridBeats, originalLengthBeats - trimmedBeats);
                    break;
                case DragMode.TrimEnd:
                    dragClip.LengthBeats = Math.Max(SnapGridBeats, Snap(originalLengthBeats + delta));
                    break;
            }
            Invalidate(); return;
        }
        if (!draggingMarquee) return;
        marquee = NormalizeRect(marqueeStart, e.Location);
        SelectIntersecting(marquee.Value);
        Invalidate();
    }

    private void OnMouseUp(object? sender, MouseEventArgs e)
    {
        if (dragMode != DragMode.None)
        {
            dragMode = DragMode.None; dragClip = null; dragTrack = null; dragOriginalStarts.Clear(); Capture = false;
            ProjectChanged?.Invoke(); ClipSelectionChanged?.Invoke(PrimarySelection); Invalidate(); return;
        }
        draggingMarquee = false;
        marquee = null;
        ClipSelectionChanged?.Invoke(PrimarySelection);
        Invalidate();
    }

    private void OnMouseWheel(object? sender, MouseEventArgs e)
    {
        if ((ModifierKeys & Keys.Control) != 0)
        {
            float oldPpb = PixelsPerBeat;
            double anchorBeat = XToBeat(e.X);
            HorizontalZoom = Math.Clamp(HorizontalZoom * (e.Delta > 0 ? 1.12f : .89f), .35f, 4f);
            horizontalScrollBeats = Math.Max(0, (float)(anchorBeat - (e.X - HeaderWidth) / PixelsPerBeat));
            Log?.Invoke($"Arrangement horizontal zoom: {HorizontalZoom:0.00}×");
        }
        else if ((ModifierKeys & Keys.Shift) != 0)
        {
            horizontalScrollBeats = Math.Max(0, horizontalScrollBeats - Math.Sign(e.Delta) * Math.Max(.5f, 4f / HorizontalZoom));
        }
        else if ((ModifierKeys & Keys.Alt) != 0)
        {
            VerticalZoom = Math.Clamp(VerticalZoom * (e.Delta > 0 ? 1.1f : .9f), .55f, 2.25f);
        }
        else
        {
            verticalScroll = Math.Max(0, verticalScroll - Math.Sign(e.Delta) * Math.Max(24, TrackHeight / 2));
        }
        Invalidate();
    }

    private void OnKeyDown(object? sender, KeyEventArgs e)
    {
        if (e.Control && e.KeyCode == Keys.C) { CopySelected(); e.SuppressKeyPress = true; }
        else if (e.Control && e.KeyCode == Keys.X) { CopySelected(); DeleteSelected(); e.SuppressKeyPress = true; }
        else if (e.Control && e.KeyCode == Keys.V) { PasteClipboard(); e.SuppressKeyPress = true; }
        else if (e.Control && e.KeyCode == Keys.D) { DuplicateSelected(); e.SuppressKeyPress = true; }
        else if (e.KeyCode is Keys.Delete or Keys.Back) { DeleteSelected(); e.SuppressKeyPress = true; }
        else if (e.KeyCode == Keys.S && !e.Control) { SplitAtBeat(pasteBeat); e.SuppressKeyPress = true; }
        else if (e.KeyCode == Keys.Left || e.KeyCode == Keys.Right)
        {
            NudgeSelected((e.KeyCode == Keys.Right ? 1 : -1) * (SnapEnabled ? SnapGridBeats : .05));
            e.SuppressKeyPress = true;
        }
    }

    private void BuildContextMenu()
    {
        clipMenu.Items.Add("Split at Pointer", null, (_, _) => SplitAtBeat(pasteBeat));
        clipMenu.Items.Add(new ToolStripSeparator());
        clipMenu.Items.Add("Copy", null, (_, _) => CopySelected());
        clipMenu.Items.Add("Cut", null, (_, _) => { CopySelected(); DeleteSelected(); });
        clipMenu.Items.Add("Paste", null, (_, _) => PasteClipboard());
        clipMenu.Items.Add("Duplicate", null, (_, _) => DuplicateSelected());
        clipMenu.Items.Add("Delete", null, (_, _) => DeleteSelected());
        clipMenu.Items.Add(new ToolStripSeparator());
        var snap = new ToolStripMenuItem("Snap/Grid");
        snap.DropDownItems.Add("Toggle Snap", null, (_, _) => ToggleSnap());
        snap.DropDownItems.Add("1 Bar", null, (_, _) => SetSnapGrid(Math.Max(1, Project.BeatsPerBar)));
        snap.DropDownItems.Add("1/4", null, (_, _) => SetSnapGrid(1));
        snap.DropDownItems.Add("1/8", null, (_, _) => SetSnapGrid(.5));
        snap.DropDownItems.Add("1/16", null, (_, _) => SetSnapGrid(.25));
        snap.DropDownItems.Add("1/32", null, (_, _) => SetSnapGrid(.125));
        clipMenu.Items.Add(snap);
    }

    private void CopySelected()
    {
        var selected = Project.Tracks.SelectMany((t, ti) => t.Clips.Where(c => SelectedClipIds.Contains(c.Id)).Select(c => new { TrackIndex = ti, Clip = c })).ToList();
        if (selected.Count == 0) return;
        double minBeat = selected.Min(x => x.Clip.StartBeat);
        clipboard = selected.Select(x => new ClipboardClip(x.TrackIndex, x.Clip.StartBeat - minBeat, CloneClip(x.Clip))).ToList();
        Log?.Invoke($"Copied {clipboard.Count} clip(s)");
    }

    private void PasteClipboard()
    {
        if (clipboard.Count == 0) return;
        SelectedClipIds.Clear();
        foreach (var item in clipboard)
        {
            if (item.TrackIndex < 0 || item.TrackIndex >= Project.Tracks.Count) continue;
            var clone = CloneClip(item.Clip);
            clone.Id = Guid.NewGuid(); clone.StartBeat = Snap(pasteBeat + item.RelativeBeat);
            Project.Tracks[item.TrackIndex].Clips.Add(clone); SelectedClipIds.Add(clone.Id);
        }
        ProjectChanged?.Invoke(); ClipSelectionChanged?.Invoke(PrimarySelection); Invalidate();
        Log?.Invoke($"Pasted {SelectedClipIds.Count} clip(s)");
    }

    private void DuplicateSelected()
    {
        var selected = Project.Tracks.SelectMany((t, ti) => t.Clips.Where(c => SelectedClipIds.Contains(c.Id)).Select(c => new { Track = t, Clip = c })).ToList();
        if (selected.Count == 0) return;
        SelectedClipIds.Clear();
        foreach (var item in selected)
        {
            var clone = CloneClip(item.Clip); clone.Id = Guid.NewGuid(); clone.StartBeat = Snap(item.Clip.StartBeat + item.Clip.LengthBeats);
            item.Track.Clips.Add(clone); SelectedClipIds.Add(clone.Id);
        }
        ProjectChanged?.Invoke(); ClipSelectionChanged?.Invoke(PrimarySelection); Invalidate();
    }

    private void DeleteSelected()
    {
        if (SelectedClipIds.Count == 0) return;
        int count = SelectedClipIds.Count;
        foreach (var track in Project.Tracks) track.Clips.RemoveAll(c => SelectedClipIds.Contains(c.Id));
        SelectedClipIds.Clear(); ProjectChanged?.Invoke(); ClipSelectionChanged?.Invoke(null); Invalidate();
        Log?.Invoke($"Deleted {count} clip(s)");
    }

    private void SplitAtBeat(double beat)
    {
        var targets = Project.Tracks.SelectMany(t => t.Clips.Select(c => (Track: t, Clip: c)))
            .Where(x => SelectedClipIds.Contains(x.Clip.Id) && beat > x.Clip.StartBeat && beat < x.Clip.StartBeat + x.Clip.LengthBeats).ToList();
        if (targets.Count == 0) return;
        SelectedClipIds.Clear();
        foreach (var item in targets)
        {
            var original = item.Clip;
            double localSplit = beat - original.StartBeat;
            var right = CloneClip(original); right.Id = Guid.NewGuid(); right.StartBeat = beat; right.LengthBeats = original.LengthBeats - localSplit;
            right.SourceOffsetBeats = original.SourceOffsetBeats + localSplit;
            if (original.Type == ClipType.Midi)
            {
                right.Notes = original.Notes.Where(n => n.Beat >= localSplit).Select(n => n with { Beat = n.Beat - localSplit }).ToList();
                right.MidiEvents = original.MidiEvents.Where(ev => ev.Beat >= localSplit).Select(ev => CloneMidiEventShifted(ev, localSplit)).ToList();
                original.Notes = original.Notes.Where(n => n.Beat < localSplit).Select(n => n with { Length = Math.Min(n.Length, localSplit - n.Beat) }).Where(n => n.Length > 0).ToList();
                original.MidiEvents = original.MidiEvents.Where(ev => ev.Beat < localSplit).ToList();
            }
            original.LengthBeats = localSplit;
            item.Track.Clips.Add(right); SelectedClipIds.Add(original.Id); SelectedClipIds.Add(right.Id);
        }
        ProjectChanged?.Invoke(); ClipSelectionChanged?.Invoke(PrimarySelection); Invalidate();
        Log?.Invoke($"Split {targets.Count} clip(s) at beat {beat:0.###}");
    }

    private static MidiClipEvent CloneMidiEventShifted(MidiClipEvent ev, double shift) => new() { Beat = ev.Beat - shift, Kind = ev.Kind, Channel = ev.Channel, Data1 = ev.Data1, Data2 = ev.Data2 };

    private void NudgeSelected(double delta)
    {
        bool changed = false;
        foreach (var clip in Project.Tracks.SelectMany(t => t.Clips).Where(c => SelectedClipIds.Contains(c.Id)))
        {
            clip.StartBeat = Math.Max(0, Snap(clip.StartBeat + delta)); changed = true;
        }
        if (changed) { ProjectChanged?.Invoke(); Invalidate(); }
    }

    private static ProjectClip CloneClip(ProjectClip clip)
    {
        var json = JsonSerializer.Serialize(clip);
        return JsonSerializer.Deserialize<ProjectClip>(json) ?? throw new InvalidOperationException("Could not clone clip.");
    }

    private void SelectIntersecting(Rectangle rect)
    {
        SelectedClipIds.Clear();
        foreach (var pair in clipHitMap)
            if (Rectangle.Round(pair.Key).IntersectsWith(rect)) SelectedClipIds.Add(pair.Value.Clip.Id);
    }

    private (Track? Track, ProjectClip? Clip) HitTest(Point p)
    {
        foreach (var pair in clipHitMap.Reverse()) if (pair.Key.Contains(p)) return pair.Value;
        return (null, null);
    }

    private static Rectangle NormalizeRect(Point a, Point b) => Rectangle.FromLTRB(Math.Min(a.X, b.X), Math.Min(a.Y, b.Y), Math.Max(a.X, b.X), Math.Max(a.Y, b.Y));

    private void OnDragEnter(object? sender, DragEventArgs e)
    {
        if (e.Data?.GetDataPresent(DataFormats.FileDrop) == true || e.Data?.GetDataPresent(SpliceDropBroker.DataFormat) == true)
            e.Effect = DragDropEffects.Copy;
    }

    private async void OnDragDrop(object? sender, DragEventArgs e)
    {
        var client = PointToClient(new Point(e.X, e.Y));
        if (e.Data?.GetDataPresent(SpliceDropBroker.DataFormat) == true && e.Data.GetData(SpliceDropBroker.DataFormat) is Features.SpliceSample spliceSample)
        {
            var asset = await SpliceDropBroker.ResolveAsync(spliceSample);
            if (asset == null) { Log?.Invoke("Splice Fetch on Drop failed; no clip created."); return; }
            int spliceTrackIndex = (client.Y + verticalScroll - 28) / TrackHeight;
            Track spliceTarget;
            if (spliceTrackIndex >= 0 && spliceTrackIndex < Project.Tracks.Count && Project.Tracks[spliceTrackIndex].Type == TrackType.Audio) spliceTarget = Project.Tracks[spliceTrackIndex];
            else { spliceTarget = Track.Audio(asset.Name); Project.Tracks.Add(spliceTarget); }
            double spliceBeat = Snap(XToBeat(client.X));
            double sourceBpm = asset.Bpm is > 0 ? asset.Bpm.Value : Project.Tempo;
            double length = asset.DurationSeconds is > 0 ? Math.Max(.25, asset.DurationSeconds.Value * sourceBpm / 60.0) : 4;
            spliceTarget.Clips.Add(new ProjectClip { Name = asset.Name, SourcePath = asset.FilePath, Type = ClipType.Audio, StartBeat = spliceBeat, LengthBeats = length, SourceTempo = sourceBpm, WarpEnabled = string.Equals(asset.Type, "loop", StringComparison.OrdinalIgnoreCase) });
            Log?.Invoke($"Splice Fetch on Drop: {asset.Name} → {spliceTarget.Name} @ beat {spliceBeat:0.##}");
            ProjectChanged?.Invoke(); Invalidate(); return;
        }

        if (e.Data?.GetData(DataFormats.FileDrop) is not string[] files || files.Length == 0) return;
        int trackIndex = (client.Y + verticalScroll - 28) / TrackHeight;
        Track target;
        if (trackIndex >= 0 && trackIndex < Project.Tracks.Count) target = Project.Tracks[trackIndex];
        else { target = Track.Audio("Audio " + (Project.Tracks.Count(t => t.Type == TrackType.Audio) + 1)); Project.Tracks.Add(target); }
        double beat = Snap(XToBeat(client.X));
        foreach (var file in files)
        {
            var ext = Path.GetExtension(file).ToLowerInvariant();
            var clip = new ProjectClip { Name = Path.GetFileNameWithoutExtension(file), SourcePath = file, Type = ext is ".mid" or ".midi" ? ClipType.Midi : ClipType.Audio, StartBeat = beat, LengthBeats = 4 };
            target.Clips.Add(clip); beat += clip.LengthBeats; Log?.Invoke($"Imported {clip.Name} to {target.Name}");
        }
        ProjectChanged?.Invoke(); Invalidate();
    }

    private sealed record ClipboardClip(int TrackIndex, double RelativeBeat, ProjectClip Clip);
    private enum DragMode { None, Move, TrimStart, TrimEnd }
}

internal static class GraphicsExtensions
{
    public static void FillRoundedRectangle(this Graphics g, Brush brush, RectangleF rect, float radius) { using var path = Rounded(rect, radius); g.FillPath(brush, path); }
    public static void DrawRoundedRectangle(this Graphics g, Pen pen, RectangleF rect, float radius) { using var path = Rounded(rect, radius); g.DrawPath(pen, path); }
    private static System.Drawing.Drawing2D.GraphicsPath Rounded(RectangleF r, float radius)
    {
        var path = new System.Drawing.Drawing2D.GraphicsPath(); float d = Math.Min(radius * 2, Math.Min(r.Width, r.Height));
        path.AddArc(r.X, r.Y, d, d, 180, 90); path.AddArc(r.Right - d, r.Y, d, d, 270, 90); path.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90); path.AddArc(r.X, r.Bottom - d, d, d, 90, 90); path.CloseFigure(); return path;
    }
}
