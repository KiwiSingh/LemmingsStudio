namespace LemmingsStudio.Windows.Features;

/// <summary>
/// buildfix244 mixer surface. Controls are bound directly to StudioProject routing state;
/// meters are sourced from AudioEngine render/playback measurements.
/// </summary>
public sealed class MixerPanel : UserControl
{
    public StudioProject? Project { get; set; }
    public AudioEngine? Engine { get; set; }
    public Action? Changed { get; set; }
    public Action<string>? Log { get; set; }

    private readonly FlowLayoutPanel strips = new()
    {
        Dock = DockStyle.Fill,
        AutoScroll = true,
        WrapContents = false,
        FlowDirection = FlowDirection.LeftToRight,
        Padding = new Padding(8)
    };
    private readonly System.Windows.Forms.Timer meterTimer = new() { Interval = 80 };
    private readonly Dictionary<string, MeterBar> meters = new();

    public MixerPanel()
    {
        Dock = DockStyle.Fill;
        Controls.Add(strips);
        meterTimer.Tick += (_, _) => RefreshMeters();
        meterTimer.Start();
    }

    public void Reload()
    {
        if (Project == null) return;
        strips.SuspendLayout();
        strips.Controls.Clear();
        meters.Clear();

        foreach (var track in Project.Tracks)
            strips.Controls.Add(BuildTrackStrip(track));

        foreach (var bus in Project.ReturnBuses)
            strips.Controls.Add(BuildReturnStrip(bus));

        strips.Controls.Add(BuildMasterStrip());
        strips.ResumeLayout();
        RefreshMeters();
    }

    private Control BuildTrackStrip(Track track)
    {
        var box = NewStrip(track.Name, track.Type.ToString());
        var meter = new MeterBar { Width = 24, Height = 150, Margin = new Padding(8, 4, 8, 4) };
        meters["track:" + track.Id] = meter;

        var vol = NewFader(track.Volume, v => { track.Volume = v; Changed?.Invoke(); });
        var pan = NewPan(track.Pan, v => { track.Pan = v; Changed?.Invoke(); });
        var buttons = new FlowLayoutPanel { Width = 112, Height = 34, WrapContents = false };
        buttons.Controls.Add(Toggle("M", track.Muted, v => { track.Muted = v; Changed?.Invoke(); }));
        buttons.Controls.Add(Toggle("S", track.Solo, v => { track.Solo = v; Changed?.Invoke(); }));
        buttons.Controls.Add(Toggle("R", track.Armed, v => { track.Armed = v; Changed?.Invoke(); }));

        box.Controls.Add(meter);
        box.Controls.Add(vol);
        box.Controls.Add(new Label { Text = "Volume", AutoSize = true });
        box.Controls.Add(pan);
        box.Controls.Add(buttons);

        if (Project != null)
        {
            var route = new ComboBox { Width = 120, DropDownStyle = ComboBoxStyle.DropDownList };
            route.Items.Add(new RouteChoice("Master", null));
            foreach (var target in Project.ReturnBuses) route.Items.Add(new RouteChoice(target.Name, target.Id));
            int routeIndex = 0;
            for (int i = 0; i < route.Items.Count; i++)
                if (route.Items[i] is RouteChoice choice && choice.Id == track.OutputBusId) { routeIndex = i; break; }
            route.SelectedIndex = routeIndex;
            route.SelectedIndexChanged += (_, _) => { if (route.SelectedItem is RouteChoice choice) { track.OutputBusId = choice.Id; Changed?.Invoke(); } };
            box.Controls.Add(new Label { Text = "Output", AutoSize = true });
            box.Controls.Add(route);
        }

        if (Project != null)
        {
            foreach (var bus in Project.ReturnBuses)
            {
                float current = track.Sends.TryGetValue(bus.Id, out var amount) ? amount : 0f;
                var sendRow = new FlowLayoutPanel { Width = 126, Height = 30, WrapContents = false };
                sendRow.Controls.Add(new Label { Text = bus.Name, Width = 56, Padding = new Padding(0, 6, 0, 0) });
                var send = new TrackBar { Minimum = 0, Maximum = 100, Value = (int)Math.Round(current * 100), Width = 64, TickStyle = TickStyle.None };
                send.Scroll += (_, _) => { track.Sends[bus.Id] = send.Value / 100f; Changed?.Invoke(); };
                sendRow.Controls.Add(send);
                box.Controls.Add(sendRow);
            }
        }
        return box;
    }

    private Control BuildReturnStrip(ReturnBus bus)
    {
        var box = NewStrip(bus.Name, "Return");
        var meter = new MeterBar { Width = 24, Height = 150, Margin = new Padding(8, 4, 8, 4) };
        meters["return:" + bus.Id] = meter;
        var vol = NewFader(bus.Volume, v => { bus.Volume = v; Changed?.Invoke(); });
        var pan = NewPan(bus.Pan, v => { bus.Pan = v; Changed?.Invoke(); });
        var buttons = new FlowLayoutPanel { Width = 112, Height = 34, WrapContents = false };
        buttons.Controls.Add(Toggle("M", bus.Muted, v => { bus.Muted = v; Changed?.Invoke(); }));
        buttons.Controls.Add(Toggle("S", bus.Solo, v => { bus.Solo = v; Changed?.Invoke(); }));
        box.Controls.Add(meter); box.Controls.Add(vol); box.Controls.Add(new Label { Text = "Return", AutoSize = true }); box.Controls.Add(pan); box.Controls.Add(buttons);
        var addFx = new Button { Text = "+ Effect", Width = 108 };
        addFx.Click += (_, _) =>
        {
            var menu = new ContextMenuStrip();
            foreach (var name in new[] { "Auto Filter", "Saturator", "Bit Crusher", "EQ Three", "Compressor", "Reverb", "Delay", "Utility" })
                menu.Items.Add(name, null, (_, _) => { bus.Devices.Add(DeviceSlot.Stock(name)); Log?.Invoke($"Added {name} to {bus.Name}"); Changed?.Invoke(); Reload(); });
            menu.Show(addFx, new Point(0, addFx.Height));
        };
        box.Controls.Add(addFx);
        return box;
    }

    private Control BuildMasterStrip()
    {
        if (Project == null) return new Panel();
        var box = NewStrip("MASTER", "Main Out");
        var meter = new MeterBar { Width = 24, Height = 150, Margin = new Padding(8, 4, 8, 4) };
        meters["master"] = meter;
        var vol = NewFader(Project.MasterVolume, v => { Project.MasterVolume = v; Changed?.Invoke(); });
        box.Controls.Add(meter); box.Controls.Add(vol); box.Controls.Add(new Label { Text = "Master", AutoSize = true });
        box.Controls.Add(Toggle("MUTE", Project.MasterMuted, v => { Project.MasterMuted = v; Changed?.Invoke(); }));
        var resetClip = new Button { Text = "Reset Clip", Width = 108 };
        resetClip.Click += (_, _) => { Engine?.ResetClipIndicators(); RefreshMeters(); };
        box.Controls.Add(resetClip);
        return box;
    }

    private static FlowLayoutPanel NewStrip(string title, string subtitle)
    {
        var p = new FlowLayoutPanel { Width = 142, Height = 430, FlowDirection = FlowDirection.TopDown, WrapContents = false, BorderStyle = BorderStyle.FixedSingle, Padding = new Padding(7), Margin = new Padding(4) };
        p.Controls.Add(new Label { Text = title, Font = new Font(SystemFonts.DefaultFont, FontStyle.Bold), Width = 124, Height = 22, AutoEllipsis = true });
        p.Controls.Add(new Label { Text = subtitle, Width = 124, Height = 18, ForeColor = Color.Gray });
        return p;
    }

    private static TrackBar NewFader(float value, Action<float> changed)
    {
        var f = new TrackBar { Orientation = Orientation.Vertical, Minimum = 0, Maximum = 125, Value = Math.Clamp((int)Math.Round(value * 100), 0, 125), Height = 150, TickFrequency = 25 };
        f.Scroll += (_, _) => changed(f.Value / 100f);
        return f;
    }

    private static TrackBar NewPan(float value, Action<float> changed)
    {
        var p = new TrackBar { Minimum = -100, Maximum = 100, Value = Math.Clamp((int)Math.Round(value * 100), -100, 100), Width = 118, TickFrequency = 50 };
        p.Scroll += (_, _) => changed(p.Value / 100f);
        return p;
    }

    private static CheckBox Toggle(string text, bool value, Action<bool> changed)
    {
        var b = new CheckBox { Appearance = Appearance.Button, Text = text, Checked = value, AutoSize = true, TextAlign = ContentAlignment.MiddleCenter };
        b.CheckedChanged += (_, _) => changed(b.Checked);
        return b;
    }

    private void RefreshMeters()
    {
        if (Engine == null) return;
        foreach (var pair in meters)
        {
            if (Engine.LastMeters.TryGetValue(pair.Key, out var m))
            {
                pair.Value.Level = m.Peak;
                pair.Value.Hold = m.HoldPeak;
                pair.Value.Clipped = m.Clipped;
            }
            else pair.Value.Level = 0;
        }
    }
}

internal sealed record RouteChoice(string Name, Guid? Id)
{
    public override string ToString() => Name;
}

public sealed class MeterBar : Control
{
    private float level;
    public float Level { get => level; set { level = Math.Clamp(value, 0, 1.25f); Invalidate(); } }
    public float Hold { get; set; }
    public bool Clipped { get; set; }
    public MeterBar() { DoubleBuffered = true; BackColor = Color.FromArgb(30, 32, 38); }
    protected override void OnPaint(PaintEventArgs e)
    {
        base.OnPaint(e);
        int h = (int)(ClientSize.Height * Math.Min(1f, Level));
        using var fill = new SolidBrush(Level >= 1f ? Color.OrangeRed : (Level > 0.75f ? Color.Gold : Color.LimeGreen));
        e.Graphics.FillRectangle(fill, 2, ClientSize.Height - h, Math.Max(1, ClientSize.Width - 4), h);
        int holdY = ClientSize.Height - (int)(ClientSize.Height * Math.Min(1f, Hold));
        using var pen = new Pen(Clipped ? Color.Red : Color.White, 2);
        e.Graphics.DrawLine(pen, 1, holdY, ClientSize.Width - 2, holdY);
        if (Clipped) e.Graphics.DrawString("CLIP", Font, Brushes.Red, 0, 0);
    }
}
