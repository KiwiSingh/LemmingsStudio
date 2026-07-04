using System.Text.Json.Serialization;

namespace LemmingsStudio.Windows;

public enum TrackType { Audio, Midi, Instrument, Bus }
public enum ClipType { Audio, Midi }
public enum AutomationTargetKind { Volume, Pan, Tempo, DeviceOn, DeviceParameter }
public enum DeviceKind { Stock, Vst3, ExternalBridge }
public enum MidiRecordMode { Overdub, Replace }
public enum MidiClipEventKind { ControlChange, SustainPedal, PitchBend, ProgramChange, ChannelPressure, PolyPressure }

public sealed class StudioProject
{
    public string Name { get; set; } = "Untitled";
    public double Tempo { get; set; } = 128.0;
    public string Key { get; set; } = "C minor";
    public List<Track> Tracks { get; set; } = new();
    public List<AutomationLane> GlobalAutomation { get; set; } = new();
    public bool MetronomeEnabled { get; set; } = false;
    public int BeatsPerBar { get; set; } = 4;
    public bool CountInEnabled { get; set; } = true;
    public int RecordCountInBars { get; set; } = 1;
    public bool QuantizeOnRecord { get; set; } = false;
    public double QuantizeGridBeats { get; set; } = 0.25;
    public MidiRecordMode MidiRecordMode { get; set; } = MidiRecordMode.Overdub;

    public static StudioProject New()
    {
        var p = new StudioProject();
        p.GlobalAutomation.Add(new AutomationLane
        {
            Name = "Project Tempo",
            Kind = AutomationTargetKind.Tempo,
            Minimum = 40,
            Maximum = 220,
            Points = new List<AutomationPoint> { new(0, 128) }
        });
        p.Tracks.Add(Track.Audio("Audio 1"));
        p.Tracks.Add(Track.Instrument("Instrument 1"));
        return p;
    }
}

public sealed class Track
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Name { get; set; } = "Track";
    public TrackType Type { get; set; }
    public bool Muted { get; set; }
    public bool Solo { get; set; }
    public bool Armed { get; set; }
    public float Volume { get; set; } = 0.80f;
    public float Pan { get; set; }
    public string? MidiInputName { get; set; }
    public int MidiChannel { get; set; } = 0; // 0 = omni, 1..16 = channel filter
    public int PitchBendRangeSemitones { get; set; } = 2;
    public double ModWheelDepthSemitones { get; set; } = 0.35;
    public List<ProjectClip> Clips { get; set; } = new();
    public List<DeviceSlot> Devices { get; set; } = new();
    public List<AutomationLane> Automation { get; set; } = new();
    public bool UseStepSequencer { get; set; }
    public StepPattern StepPattern { get; set; } = StepPattern.DefaultDrumPattern();
    public List<SequencerLayer> SequencerLayers { get; set; } = SequencerLayer.DefaultKit();
    public string ColorHex { get; set; } = "#6A93F5";

    public static Track Audio(string name) => new()
    {
        Name = name,
        Type = TrackType.Audio,
        Automation = DefaultAutomation()
    };

    public static Track Instrument(string name) => new()
    {
        Name = name,
        Type = TrackType.Instrument,
        Devices = new List<DeviceSlot> { DeviceSlot.Stock("Oscillatron") },
        Automation = DefaultAutomation()
    };

    public override string ToString() => Name;

    private static List<AutomationLane> DefaultAutomation() => new()
    {
        new AutomationLane { Name = "Volume", Kind = AutomationTargetKind.Volume, Minimum = 0, Maximum = 1 },
        new AutomationLane { Name = "Pan", Kind = AutomationTargetKind.Pan, Minimum = -1, Maximum = 1 }
    };
}

public sealed class ProjectClip
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public ClipType Type { get; set; }
    public string Name { get; set; } = "Clip";
    public string? SourcePath { get; set; }
    public double StartBeat { get; set; }
    public double LengthBeats { get; set; } = 4;
    public double SourceTempo { get; set; } = 128;
    public double Gain { get; set; } = 1.0;
    public int PitchSemitones { get; set; }
    public int PitchCents { get; set; }
    public List<MidiNote> Notes { get; set; } = new();
    public List<MidiClipEvent> MidiEvents { get; set; } = new();
    public bool WarpEnabled { get; set; } = true;
}

public sealed record MidiNote(double Beat, double Length, int Note, int Velocity);

public sealed class MidiClipEvent
{
    public double Beat { get; set; }
    public MidiClipEventKind Kind { get; set; } = MidiClipEventKind.ControlChange;
    public int Channel { get; set; } = 1;
    public int Data1 { get; set; }
    public int Data2 { get; set; }
}

public sealed class StepPattern
{
    public int StepCount { get; set; } = 16;
    public int StepsPerBeat { get; set; } = 4;
    public List<StepHit> Hits { get; set; } = new();

    public bool IsOn(int step, int note) => Hits.Any(h => h.Step == step && h.Note == note);

    public void Set(int step, int note, bool on, int velocity = 108)
    {
        step = ((step % Math.Max(1, StepCount)) + Math.Max(1, StepCount)) % Math.Max(1, StepCount);
        Hits.RemoveAll(h => h.Step == step && h.Note == note);
        if (on) Hits.Add(new StepHit { Step = step, Note = note, Velocity = Math.Clamp(velocity, 1, 127) });
        Hits = Hits.OrderBy(h => h.Step).ThenBy(h => h.Note).ToList();
    }

    public void Toggle(int step, int note) => Set(step, note, !IsOn(step, note));

    public void ClearLane(int note) => Hits.RemoveAll(h => h.Note == note);
    public void Clear() => Hits.Clear();

    public static StepPattern Empty(int steps = 16, int stepsPerBeat = 4) => new() { StepCount = steps, StepsPerBeat = stepsPerBeat };

    public static StepPattern DefaultDrumPattern()
    {
        var p = Empty();
        foreach (var step in new[] { 0, 4, 8, 12 }) p.Set(step, 36, true, 124);
        foreach (var step in new[] { 4, 12 }) p.Set(step, 38, true, 112);
        foreach (var step in new[] { 2, 6, 10, 14 }) p.Set(step, 42, true, 84);
        p.Set(15, 46, true, 70);
        return p;
    }
}

public sealed class StepHit
{
    public int Step { get; set; }
    public int Note { get; set; }
    public int Velocity { get; set; } = 108;
}

public sealed class SequencerLayer
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Name { get; set; } = "Layer";
    public int Note { get; set; } = 60;
    public string? SourcePath { get; set; }
    public double Volume { get; set; } = 1.0;
    public double Pan { get; set; }
    public int OctaveOffset { get; set; }

    public static List<SequencerLayer> DefaultKit() => new()
    {
        new SequencerLayer { Name = "Kick", Note = 36 },
        new SequencerLayer { Name = "Snare / Clap", Note = 38 },
        new SequencerLayer { Name = "Closed Hat", Note = 42 },
        new SequencerLayer { Name = "Open Hat", Note = 46 },
        new SequencerLayer { Name = "Perc", Note = 39 },
        new SequencerLayer { Name = "Tom", Note = 45 },
        new SequencerLayer { Name = "Ride", Note = 51 },
        new SequencerLayer { Name = "Crash", Note = 49 },
    };
}

public sealed record AutomationPoint(double Beat, double Value);

public sealed class AutomationLane
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Name { get; set; } = "Automation";
    public AutomationTargetKind Kind { get; set; }
    public string? DeviceId { get; set; }
    public string? ParameterId { get; set; }
    public double Minimum { get; set; } = 0;
    public double Maximum { get; set; } = 1;
    public List<AutomationPoint> Points { get; set; } = new();
}

public sealed class DeviceSlot
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Name { get; set; } = "Device";
    public bool Enabled { get; set; } = true;
    public DeviceKind Kind { get; set; } = DeviceKind.Stock;
    public string? PluginPath { get; set; }
    public string? PluginManufacturer { get; set; }
    public string? PluginFormat { get; set; }
    public string? EditorBridge { get; set; }
    public bool NativeHostEnabled { get; set; }
    public string? NativeHostStatus { get; set; }
    public string? PluginStateBase64 { get; set; }
    public int PluginLatencySamples { get; set; }
    public int PluginInputChannels { get; set; }
    public int PluginOutputChannels { get; set; }
    public string? PluginBusLayout { get; set; }
    public bool PluginSupportsEditor { get; set; }
    public bool PluginHasCustomEditor { get; set; }
    public int PluginProgramIndex { get; set; } = -1;
    public List<Vst3ParameterInfo> Vst3Parameters { get; set; } = new();
    public Dictionary<string, double> Parameters { get; set; } = new();
    public Dictionary<string, MidiMapping> MidiMappings { get; set; } = new();
    public bool IsVst3 => Kind == DeviceKind.Vst3 || string.Equals(PluginFormat, "VST3", StringComparison.OrdinalIgnoreCase);

    public static DeviceSlot Stock(string name) => new()
    {
        Name = name,
        Kind = DeviceKind.Stock,
        Parameters = new Dictionary<string, double>
        {
            ["Cutoff"] = 0.65,
            ["Resonance"] = 0.25,
            ["Drive"] = 0.10,
            ["Wet"] = 0.50
        }
    };

    public static DeviceSlot Vst3(string name, string path) => new()
    {
        Name = name,
        Kind = DeviceKind.Vst3,
        PluginFormat = "VST3",
        PluginPath = path,
        Parameters = new Dictionary<string, double>
        {
            ["Input Gain"] = 1.0,
            ["Output Gain"] = 1.0
        }
    };
}

public sealed class Vst3ParameterInfo
{
    public string Id { get; set; } = "";
    public string Name { get; set; } = "Parameter";
    public int Index { get; set; }
    public double NormalizedValue { get; set; }
    public string DisplayValue { get; set; } = "";
    public bool Automatable { get; set; } = true;
}

public sealed class MidiMapping
{
    public int Channel { get; set; } = 0; // 0 = omni
    public int Controller { get; set; }
    public double Minimum { get; set; } = 0.0;
    public double Maximum { get; set; } = 1.0;
}

