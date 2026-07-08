namespace LemmingsStudio.Windows;

/// <summary>
/// buildfix243: full Windows piano-roll editing surface with note selection/editing,
/// velocity and expressive MIDI lanes, scale highlighting, ghost notes and live preview.
/// </summary>
public sealed class PianoRollPanel : UserControl
{
    private readonly ComboBox trackBox = new() { DropDownStyle = ComboBoxStyle.DropDownList, Width = 180 };
    private readonly ComboBox clipBox = new() { DropDownStyle = ComboBoxStyle.DropDownList, Width = 180 };
    private readonly ComboBox gridBox = new() { DropDownStyle = ComboBoxStyle.DropDownList, Width = 72 };
    private readonly ComboBox laneBox = new() { DropDownStyle = ComboBoxStyle.DropDownList, Width = 92 };
    private readonly ComboBox scaleBox = new() { DropDownStyle = ComboBoxStyle.DropDownList, Width = 105 };
    private readonly NumericUpDown lengthBox = new() { Minimum = 1, Maximum = 64, Value = 1, Width = 50 };
    private readonly NumericUpDown velocityBox = new() { Minimum = 1, Maximum = 127, Value = 100, Width = 56 };
    private readonly RollCanvas canvas = new() { Dock = DockStyle.Fill };
    private readonly LiveMidiSynth previewSynth = new();
    private readonly System.Windows.Forms.Timer previewOffTimer = new() { Interval = 180 };

    public StudioProject? Project { get; set; }
    public Action? Changed { get; set; }

    public PianoRollPanel()
    {
        Dock = DockStyle.Fill;
        gridBox.Items.AddRange(new object[] { "1/4", "1/8", "1/16", "1/32" }); gridBox.SelectedIndex = 2;
        laneBox.Items.AddRange(new object[] { "Velocity", "CC1 Mod", "Pitch Bend", "Sustain" }); laneBox.SelectedIndex = 0;
        scaleBox.Items.AddRange(new object[] { "Chromatic", "Major", "Minor", "Dorian", "Pentatonic" }); scaleBox.SelectedIndex = 0;

        var top = new FlowLayoutPanel { Dock = DockStyle.Top, Height = 76, Padding = new Padding(6), BackColor = Color.FromArgb(32, 32, 38), WrapContents = true };
        Add(top, new Label { Text = "Piano Roll", AutoSize = true, ForeColor = Color.White, Padding = new Padding(0, 8, 10, 0), Font = new Font(SystemFonts.MessageBoxFont, FontStyle.Bold) });
        Add(top, trackBox, clipBox, Label("Grid"), gridBox, Label("Lane"), laneBox, Label("Scale"), scaleBox, Label("Len"), lengthBox, Label("Vel"), velocityBox);
        AddButton(top, "New Clip", CreateClip); AddButton(top, "Quantize", Quantize); AddButton(top, "Humanize", Humanize);
        AddButton(top, "-12", () => Transpose(-12)); AddButton(top, "-1", () => Transpose(-1)); AddButton(top, "+1", () => Transpose(1)); AddButton(top, "+12", () => Transpose(12));
        AddButton(top, "Duplicate", DuplicateSelection); AddButton(top, "Delete", DeleteSelection);

        trackBox.DisplayMember = nameof(Track.Name); clipBox.DisplayMember = nameof(ProjectClip.Name);
        trackBox.SelectedIndexChanged += (_, _) => ReloadClips();
        clipBox.SelectedIndexChanged += (_, _) => BindCanvas();
        gridBox.SelectedIndexChanged += (_, _) => { canvas.GridBeats = GridBeats; canvas.Invalidate(); };
        laneBox.SelectedIndexChanged += (_, _) => { canvas.Lane = laneBox.Text; canvas.Invalidate(); };
        scaleBox.SelectedIndexChanged += (_, _) => { canvas.ScaleMode = scaleBox.Text; canvas.Invalidate(); };
        velocityBox.ValueChanged += (_, _) => canvas.DefaultVelocity = (int)velocityBox.Value;
        lengthBox.ValueChanged += (_, _) => canvas.DefaultLength = Math.Max(GridBeats, (double)lengthBox.Value * GridBeats);

        canvas.NoteEdited += () => { Changed?.Invoke(); canvas.Invalidate(); };
        canvas.PreviewNote += PreviewNote;
        previewOffTimer.Tick += (_, _) => { previewOffTimer.Stop(); canvas.LastPreviewNote.IfSome(n => previewSynth.NoteOff(n)); };
        Controls.Add(canvas); Controls.Add(top);
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing) { previewOffTimer.Dispose(); previewSynth.Dispose(); }
        base.Dispose(disposing);
    }

    private static Label Label(string text) => new() { Text = text, AutoSize = true, ForeColor = Color.Gainsboro, Padding = new Padding(8, 8, 2, 0) };
    private static void Add(FlowLayoutPanel p, params Control[] c) => p.Controls.AddRange(c);
    private static void AddButton(FlowLayoutPanel p, string text, Action click) { var b = new Button { Text = text, AutoSize = true }; b.Click += (_, _) => click(); p.Controls.Add(b); }

    private double GridBeats => gridBox.SelectedIndex switch { 0 => 1.0, 1 => 0.5, 2 => 0.25, 3 => 0.125, _ => 0.25 };
    private Track? SelectedTrack => trackBox.SelectedItem as Track;
    private ProjectClip? SelectedClip => clipBox.SelectedItem as ProjectClip;

    public void Reload()
    {
        var oldTrack = (trackBox.SelectedItem as Track)?.Id;
        trackBox.Items.Clear();
        if (Project != null) foreach (var t in Project.Tracks.Where(t => t.Type is TrackType.Instrument or TrackType.Midi)) trackBox.Items.Add(t);
        if (trackBox.Items.Count > 0)
        {
            var found = Enumerable.Range(0, trackBox.Items.Count).FirstOrDefault(i => ((Track)trackBox.Items[i]!).Id == oldTrack);
            trackBox.SelectedIndex = found >= 0 && found < trackBox.Items.Count ? found : 0;
        }
        else ReloadClips();
    }

    private void ReloadClips()
    {
        var old = SelectedClip?.Id; clipBox.Items.Clear();
        if (SelectedTrack != null) foreach (var c in SelectedTrack.Clips.Where(c => c.Type == ClipType.Midi)) clipBox.Items.Add(c);
        if (clipBox.Items.Count > 0)
        {
            var found = Enumerable.Range(0, clipBox.Items.Count).FirstOrDefault(i => ((ProjectClip)clipBox.Items[i]!).Id == old);
            clipBox.SelectedIndex = found >= 0 && found < clipBox.Items.Count ? found : 0;
        }
        BindCanvas();
    }

    private void BindCanvas()
    {
        canvas.Clip = SelectedClip; canvas.Track = SelectedTrack; canvas.Project = Project;
        previewSynth.TargetTrack = SelectedTrack;
        canvas.GridBeats = GridBeats; canvas.Lane = laneBox.Text; canvas.ScaleMode = scaleBox.Text;
        canvas.DefaultVelocity = (int)velocityBox.Value; canvas.DefaultLength = Math.Max(GridBeats, (double)lengthBox.Value * GridBeats);
        canvas.ClearSelection(); canvas.Invalidate();
    }

    private void CreateClip()
    {
        if (SelectedTrack is not { } t) return;
        var clip = new ProjectClip { Type = ClipType.Midi, Name = "MIDI Clip " + (t.Clips.Count + 1), StartBeat = 0, LengthBeats = 4 };
        t.Clips.Add(clip); Changed?.Invoke(); ReloadClips(); clipBox.SelectedItem = clip;
    }

    private void Quantize()
    {
        if (SelectedClip is not { } c) return; var g = GridBeats;
        var ids = canvas.SelectedIndices;
        c.Notes = c.Notes.Select((n, i) => ids.Count == 0 || ids.Contains(i) ? n with { Beat = Math.Round(n.Beat / g) * g, Length = Math.Max(g / 4, Math.Round(n.Length / g) * g) } : n).OrderBy(n => n.Beat).ToList();
        canvas.ClearSelection(); Changed?.Invoke(); canvas.Invalidate();
    }

    private void Humanize()
    {
        if (SelectedClip is not { } c) return; var rng = new Random(); var ids = canvas.SelectedIndices;
        var maxJitter = GridBeats * 0.12;
        c.Notes = c.Notes.Select((n, i) => ids.Count == 0 || ids.Contains(i)
            ? n with { Beat = Math.Max(0, n.Beat + (rng.NextDouble() * 2 - 1) * maxJitter), Velocity = Math.Clamp(n.Velocity + rng.Next(-8, 9), 1, 127) } : n).OrderBy(n => n.Beat).ToList();
        canvas.ClearSelection(); Changed?.Invoke(); canvas.Invalidate();
    }

    private void Transpose(int semitones)
    {
        if (SelectedClip is not { } c) return; var ids = canvas.SelectedIndices;
        c.Notes = c.Notes.Select((n, i) => ids.Count == 0 || ids.Contains(i) ? n with { Note = Math.Clamp(n.Note + semitones, 0, 127) } : n).ToList();
        canvas.ClearSelection(); Changed?.Invoke(); canvas.Invalidate();
    }

    private void DuplicateSelection() { canvas.DuplicateSelection(); Changed?.Invoke(); }
    private void DeleteSelection() { canvas.DeleteSelection(); Changed?.Invoke(); }

    private void PreviewNote(int note, int velocity)
    {
        previewOffTimer.Stop(); canvas.LastPreviewNote.IfSome(n => previewSynth.NoteOff(n));
        canvas.LastPreviewNote = note; previewSynth.NoteOn(note, velocity, SelectedTrack); previewOffTimer.Start();
    }

    private sealed class RollCanvas : Control
    {
        public ProjectClip? Clip { get; set; }
        public Track? Track { get; set; }
        public StudioProject? Project { get; set; }
        public Action? NoteEdited { get; set; }
        public Action<int, int>? PreviewNote { get; set; }
        public double GridBeats { get; set; } = 0.25;
        public string Lane { get; set; } = "Velocity";
        public string ScaleMode { get; set; } = "Chromatic";
        public int DefaultVelocity { get; set; } = 100;
        public double DefaultLength { get; set; } = 0.25;
        public int? LastPreviewNote { get; set; }
        public HashSet<int> SelectedIndices { get; } = new();

        private const int NoteMin = 24, NoteMax = 96, KeyW = 72, StepW = 28, RowH = 12, LaneH = 118;
        private Point dragStart; private Rectangle marquee; private bool marquing; private int dragIndex = -1; private bool resizing; private MidiNote? dragOriginal;
        private double pixelsPerBeat => StepW / 0.25;

        public RollCanvas() { DoubleBuffered = true; BackColor = Color.FromArgb(22,22,26); SetStyle(ControlStyles.Selectable, true); TabStop = true; }
        public void ClearSelection() { SelectedIndices.Clear(); }

        protected override void OnPaint(PaintEventArgs e)
        {
            var g = e.Graphics; g.Clear(BackColor);
            if (Clip == null) { using var br = new SolidBrush(Color.Gainsboro); g.DrawString("Select or create a MIDI clip.", Font, br, 24, 24); return; }
            int rows = NoteMax - NoteMin + 1; int rollH = Math.Max(0, Height - LaneH); float rowH = Math.Max(8, rollH / (float)rows);
            int steps = Math.Max(16, (int)Math.Ceiling(Clip.LengthBeats / 0.25));
            using var grid = new Pen(Color.FromArgb(42,42,48)); using var beat = new Pen(Color.FromArgb(74,74,86));
            using var text = new SolidBrush(Color.Gainsboro); using var noteBrush = new SolidBrush(Color.FromArgb(0, 190, 135)); using var selectedBrush = new SolidBrush(Color.FromArgb(255, 180, 70));
            for (int r=0;r<rows;r++)
            {
                int y = (int)(r * rowH); int note = NoteMax-r;
                bool inScale = IsScaleTone(note);
                using var bg = new SolidBrush(inScale ? Color.FromArgb(31,31,38) : Color.FromArgb(24,24,29));
                g.FillRectangle(bg, KeyW, y, Width-KeyW, (int)Math.Ceiling(rowH));
                if (note % 12 == 0) { using var c = new SolidBrush(Color.FromArgb(42,42,52)); g.FillRectangle(c, KeyW, y, Width-KeyW, (int)Math.Ceiling(rowH)); }
                if (rowH >= 10) g.DrawString(NoteName(note), Font, text, 4, y-2); g.DrawLine(grid, KeyW, y, Width, y);
            }
            for (int s=0;s<=steps;s++) g.DrawLine(s%4==0?beat:grid, KeyW + s*StepW, 0, KeyW + s*StepW, rollH);

            DrawGhostNotes(g, rollH, rowH);
            for (int i=0;i<Clip.Notes.Count;i++)
            {
                var n=Clip.Notes[i]; var rect=NoteRect(n,rowH);
                g.FillRectangle(SelectedIndices.Contains(i)?selectedBrush:noteBrush, rect);
                if (SelectedIndices.Contains(i)) { using var p = new Pen(Color.White); g.DrawRectangle(p, rect); g.FillRectangle(Brushes.White, rect.Right-4, rect.Top+2, 3, Math.Max(2, rect.Height-4)); }
            }
            DrawLane(g, rollH);
            if (marquing) { using var p = new Pen(Color.White) { DashStyle = System.Drawing.Drawing2D.DashStyle.Dash }; g.DrawRectangle(p, marquee); }
        }

        private void DrawGhostNotes(Graphics g, int rollH, float rowH)
        {
            if (Project == null || Track == null || Clip == null) return;
            using var ghost = new SolidBrush(Color.FromArgb(45, 150, 190, 255));
            foreach (var t in Project.Tracks.Where(t => t.Id != Track.Id && t.Type is TrackType.Instrument or TrackType.Midi))
                foreach (var c in t.Clips.Where(c => c.Type == ClipType.Midi && RangesOverlap(c.StartBeat,c.StartBeat+c.LengthBeats,Clip.StartBeat,Clip.StartBeat+Clip.LengthBeats)))
                    foreach (var n in c.Notes)
                    {
                        var localBeat = c.StartBeat + n.Beat - Clip.StartBeat; if (localBeat < 0 || localBeat > Clip.LengthBeats) continue;
                        var r = NoteRect(n with { Beat = localBeat }, rowH); g.FillRectangle(ghost, r);
                    }
        }

        private void DrawLane(Graphics g, int rollH)
        {
            if (Clip == null) return; var area = new Rectangle(KeyW, rollH, Math.Max(0,Width-KeyW), LaneH);
            using var bg = new SolidBrush(Color.FromArgb(27,27,33)); g.FillRectangle(bg, area); using var border = new Pen(Color.FromArgb(80,80,92)); g.DrawLine(border,0,rollH,Width,rollH);
            using var label = new SolidBrush(Color.Gainsboro); g.DrawString(Lane, Font, label, 6, rollH+4);
            if (Lane == "Velocity")
            {
                using var br = new SolidBrush(Color.FromArgb(90, 0, 190, 135));
                foreach (var n in Clip.Notes) { int x=BeatX(n.Beat), h=(int)((LaneH-20)*(n.Velocity/127.0)); g.FillRectangle(br,x,Height-h-2,Math.Max(3,(int)(n.Length*pixelsPerBeat)-2),h); }
                return;
            }
            var events = EventsForLane().OrderBy(x=>x.Beat).ToList(); if(events.Count==0)return;
            using var pen = new Pen(Color.FromArgb(255,180,70),2); Point? prev=null;
            foreach(var ev in events){ int x=BeatX(EventLocalBeat(ev)); int y=EventY(ev,rollH); var pt=new Point(x,y); if(prev!=null)g.DrawLine(pen,prev.Value,pt); g.FillEllipse(Brushes.White,x-3,y-3,6,6); prev=pt; }
        }

        protected override void OnMouseDown(MouseEventArgs e)
        {
            Focus(); if (Clip == null) return; int rollH=Math.Max(0,Height-LaneH); float rowH=Math.Max(8,rollH/(float)(NoteMax-NoteMin+1)); dragStart=e.Location;
            if (e.Y >= rollH) { EditLane(e, rollH); return; }
            int hit=HitNote(e.Location,rowH);
            if (hit>=0)
            {
                if ((ModifierKeys & Keys.Control)==0 && !SelectedIndices.Contains(hit)) SelectedIndices.Clear();
                if ((ModifierKeys & Keys.Control)!=0 && SelectedIndices.Contains(hit)) SelectedIndices.Remove(hit); else SelectedIndices.Add(hit);
                dragIndex=hit; dragOriginal=Clip.Notes[hit]; var r=NoteRect(dragOriginal,rowH); resizing=e.X>=r.Right-7; PreviewNote?.Invoke(dragOriginal.Note,dragOriginal.Velocity); Invalidate(); return;
            }
            if (e.Button==MouseButtons.Right) return;
            if ((ModifierKeys & Keys.Control)==0) SelectedIndices.Clear(); marquing=true; marquee=new Rectangle(e.X,e.Y,0,0); Invalidate();
        }

        protected override void OnMouseMove(MouseEventArgs e)
        {
            if (Clip==null || e.Button!=MouseButtons.Left) return; int rollH=Math.Max(0,Height-LaneH); float rowH=Math.Max(8,rollH/(float)(NoteMax-NoteMin+1));
            if(marquing){ marquee=Normalize(dragStart,e.Location); Invalidate(); return; }
            if(dragIndex<0 || dragOriginal==null || dragIndex>=Clip.Notes.Count)return;
            var original=dragOriginal; double dx=(e.X-dragStart.X)/pixelsPerBeat; int dy=(int)Math.Round((dragStart.Y-e.Y)/rowH);
            if(resizing){ var len=Math.Max(GridBeats/4, Snap(original.Length+dx)); Clip.Notes[dragIndex]=original with{Length=len}; }
            else { Clip.Notes[dragIndex]=original with{Beat=Math.Max(0,Snap(original.Beat+dx)),Note=Math.Clamp(original.Note+dy,0,127)}; }
            NoteEdited?.Invoke();
        }

        protected override void OnMouseUp(MouseEventArgs e)
        {
            if(Clip==null)return; int rollH=Math.Max(0,Height-LaneH); float rowH=Math.Max(8,rollH/(float)(NoteMax-NoteMin+1));
            if(marquing){ for(int i=0;i<Clip.Notes.Count;i++) if(marquee.IntersectsWith(NoteRect(Clip.Notes[i],rowH)))SelectedIndices.Add(i); marquing=false; }
            else if(dragIndex<0 && e.Button==MouseButtons.Left && e.Y<rollH && Math.Abs(e.X-dragStart.X)<4 && Math.Abs(e.Y-dragStart.Y)<4)
            {
                double beat=Snap(Math.Max(0,(e.X-KeyW)/pixelsPerBeat)); int note=NoteMax-Math.Clamp((int)(e.Y/rowH),0,NoteMax-NoteMin);
                var n=new MidiNote(beat,DefaultLength,note,DefaultVelocity); Clip.Notes.Add(n); Clip.Notes=Clip.Notes.OrderBy(n=>n.Beat).ThenBy(n=>n.Note).ToList(); Clip.LengthBeats=Math.Max(Clip.LengthBeats,beat+DefaultLength); PreviewNote?.Invoke(note,DefaultVelocity); NoteEdited?.Invoke();
            }
            dragIndex=-1; dragOriginal=null; resizing=false; Invalidate();
        }

        protected override void OnKeyDown(KeyEventArgs e)
        {
            if(e.KeyCode==Keys.Delete||e.KeyCode==Keys.Back){DeleteSelection();e.Handled=true;}
            else if(e.Control&&e.KeyCode==Keys.D){DuplicateSelection();e.Handled=true;}
            else if(e.KeyCode==Keys.Up){NudgePitch(e.Shift?12:1);e.Handled=true;}
            else if(e.KeyCode==Keys.Down){NudgePitch(e.Shift?-12:-1);e.Handled=true;}
            else if(e.KeyCode==Keys.Left){NudgeTime(-GridBeats);e.Handled=true;}
            else if(e.KeyCode==Keys.Right){NudgeTime(GridBeats);e.Handled=true;}
            base.OnKeyDown(e);
        }

        public void DuplicateSelection()
        {
            if(Clip==null||SelectedIndices.Count==0)return; var src=SelectedIndices.OrderBy(i=>i).Select(i=>Clip.Notes[i]).ToList(); SelectedIndices.Clear();
            foreach(var n in src){Clip.Notes.Add(n with{Beat=n.Beat+GridBeats});SelectedIndices.Add(Clip.Notes.Count-1);} Clip.LengthBeats=Math.Max(Clip.LengthBeats,src.Max(n=>n.Beat+n.Length)+GridBeats); NoteEdited?.Invoke(); Invalidate();
        }
        public void DeleteSelection(){if(Clip==null||SelectedIndices.Count==0)return; Clip.Notes=Clip.Notes.Where((_,i)=>!SelectedIndices.Contains(i)).ToList();SelectedIndices.Clear();NoteEdited?.Invoke();Invalidate();}
        private void NudgePitch(int d){if(Clip==null)return;Clip.Notes=Clip.Notes.Select((n,i)=>SelectedIndices.Contains(i)?n with{Note=Math.Clamp(n.Note+d,0,127)}:n).ToList();NoteEdited?.Invoke();}
        private void NudgeTime(double d){if(Clip==null)return;Clip.Notes=Clip.Notes.Select((n,i)=>SelectedIndices.Contains(i)?n with{Beat=Math.Max(0,n.Beat+d)}:n).ToList();NoteEdited?.Invoke();}

        private void EditLane(MouseEventArgs e,int rollH)
        {
            if(Clip==null)return; double beat=Snap(Math.Max(0,(e.X-KeyW)/pixelsPerBeat)); double norm=Math.Clamp((Height-e.Y)/(double)Math.Max(1,LaneH-12),0,1);
            if(Lane=="Velocity")
            {
                int index=Clip.Notes.Select((n,i)=>(n,i)).Where(x=>Math.Abs(x.n.Beat-beat)<=Math.Max(GridBeats,0.125)).OrderBy(x=>Math.Abs(x.n.Beat-beat)).Select(x=>x.i).DefaultIfEmpty(-1).First();
                if(index>=0){var n=Clip.Notes[index];Clip.Notes[index]=n with{Velocity=Math.Clamp((int)Math.Round(norm*127),1,127)};}
            }
            else
            {
                var kind=Lane switch{"CC1 Mod"=>MidiClipEventKind.ControlChange,"Pitch Bend"=>MidiClipEventKind.PitchBend,"Sustain"=>MidiClipEventKind.SustainPedal,_=>MidiClipEventKind.ControlChange};
                Clip.MidiEvents.RemoveAll(x=>x.Kind==kind && (kind!=MidiClipEventKind.ControlChange||x.Data1==1) && Math.Abs(EventLocalBeat(x)-beat)<GridBeats*0.45);
                int d1=kind==MidiClipEventKind.PitchBend?(int)Math.Round(norm*16383):kind==MidiClipEventKind.ControlChange?1:64;
                int d2=kind==MidiClipEventKind.PitchBend?0:kind==MidiClipEventKind.SustainPedal?(norm>=0.5?127:0):(int)Math.Round(norm*127);
                Clip.MidiEvents.Add(new MidiClipEvent{Beat=Clip.StartBeat+beat,Kind=kind,Channel=1,Data1=d1,Data2=d2});
            }
            NoteEdited?.Invoke(); Invalidate();
        }

        private IEnumerable<MidiClipEvent> EventsForLane()=>Clip?.MidiEvents.Where(ev=>Lane switch{"CC1 Mod"=>ev.Kind==MidiClipEventKind.ControlChange&&ev.Data1==1,"Pitch Bend"=>ev.Kind==MidiClipEventKind.PitchBend,"Sustain"=>ev.Kind==MidiClipEventKind.SustainPedal,_=>false})??Enumerable.Empty<MidiClipEvent>();
        private int EventY(MidiClipEvent ev,int rollH){double norm=Lane switch{"Pitch Bend"=>ev.Data1/16383.0,"Sustain"=>ev.Data2>=64?1:0,_=>ev.Data2/127.0};return Height-2-(int)(norm*(LaneH-18));}
        private double EventLocalBeat(MidiClipEvent ev)=>Clip==null?ev.Beat:Math.Max(0,ev.Beat-Clip.StartBeat);
        private int HitNote(Point p,float rowH){if(Clip==null)return-1;for(int i=Clip.Notes.Count-1;i>=0;i--)if(NoteRect(Clip.Notes[i],rowH).Contains(p))return i;return-1;}
        private Rectangle NoteRect(MidiNote n,float rowH){int x=BeatX(n.Beat),y=(int)((NoteMax-n.Note)*rowH),w=Math.Max(8,(int)Math.Round(n.Length*pixelsPerBeat)-2),h=Math.Max(5,(int)Math.Ceiling(rowH)-2);return new Rectangle(x+1,y+1,w,h);}
        private int BeatX(double beat)=>KeyW+(int)Math.Round(beat*pixelsPerBeat);
        private double Snap(double beat)=>Math.Round(beat/Math.Max(0.0001,GridBeats))*GridBeats;
        private bool IsScaleTone(int note){if(ScaleMode=="Chromatic")return true;int root=ParseRoot(Project?.Key??"C");int pc=((note-root)%12+12)%12;int[] set=ScaleMode switch{"Major"=>new[]{0,2,4,5,7,9,11},"Minor"=>new[]{0,2,3,5,7,8,10},"Dorian"=>new[]{0,2,3,5,7,9,10},"Pentatonic"=>new[]{0,2,4,7,9},_=>Enumerable.Range(0,12).ToArray()};return set.Contains(pc);}
        private static int ParseRoot(string key){string k=(key??"C").Trim().ToUpperInvariant();string[] names={"C","C#","D","D#","E","F","F#","G","G#","A","A#","B"};for(int i=0;i<names.Length;i++)if(k.StartsWith(names[i],StringComparison.OrdinalIgnoreCase))return i;return 0;}
        private static Rectangle Normalize(Point a,Point b)=>new(Math.Min(a.X,b.X),Math.Min(a.Y,b.Y),Math.Abs(a.X-b.X),Math.Abs(a.Y-b.Y));
        private static bool RangesOverlap(double a0,double a1,double b0,double b1)=>a0<b1&&b0<a1;
        private static string NoteName(int n){string[] names={"C","C#","D","D#","E","F","F#","G","G#","A","A#","B"};return names[n%12]+(n/12-1);}
    }
}

internal static class OptionalIntExtensions
{
    public static void IfSome(this int? value, Action<int> action) { if (value.HasValue) action(value.Value); }
}
