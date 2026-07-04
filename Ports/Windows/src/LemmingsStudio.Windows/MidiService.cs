using NAudio.Midi;

namespace LemmingsStudio.Windows;

public sealed class MidiService : IDisposable
{
    public static MidiService Shared { get; } = new();

    public event Action<string>? Log;
    public event Action<int, int, int>? NoteOn;
    public event Action<int, int>? NoteOff;
    public event Action<int, int, int>? ControlChange;
    public event Action<int, int>? PitchBend;
    public event Action<int, MidiClipEventKind, int, int>? ChannelEvent;

    private MidiIn? input;
    private readonly List<MidiOut> outputs = new();
    private Action<int, int, int>? learnTarget;
    private string? learnDescription;

    public IReadOnlyList<string> InputNames()
    {
        var list = new List<string>();
        for (int i = 0; i < MidiIn.NumberOfDevices; i++)
        {
            try { list.Add(MidiIn.DeviceInfo(i).ProductName); }
            catch { list.Add($"MIDI In {i}"); }
        }
        return list;
    }

    public IReadOnlyList<string> OutputNames()
    {
        var list = new List<string>();
        for (int i = 0; i < MidiOut.NumberOfDevices; i++)
        {
            try { list.Add(MidiOut.DeviceInfo(i).ProductName); }
            catch { list.Add($"MIDI Out {i}"); }
        }
        return list;
    }

    public void OpenInput(int index)
    {
        CloseInput();
        if (index < 0 || index >= MidiIn.NumberOfDevices) throw new ArgumentOutOfRangeException(nameof(index));
        input = new MidiIn(index);
        input.MessageReceived += OnMessage;
        input.ErrorReceived += (_, e) => Log?.Invoke("MIDI input error: " + e.Error);
        input.Start();
        Log?.Invoke($"MIDI input opened: {MidiIn.DeviceInfo(index).ProductName}");
    }

    public void CloseInput()
    {
        if (input != null)
        {
            try { input.Stop(); } catch { }
            input.Dispose(); input = null;
        }
    }

    public void SendToOutput(int outputIndex, MidiEvent evt)
    {
        if (outputIndex < 0 || outputIndex >= MidiOut.NumberOfDevices) return;
        try
        {
            using var output = new MidiOut(outputIndex);
            output.Send(evt.GetAsShortMessage());
        }
        catch (Exception ex) { Log?.Invoke("MIDI output send failed: " + ex.Message); }
    }

    public void LearnNextControl(string description, Action<int, int, int> target)
    {
        learnDescription = description;
        learnTarget = target;
        Log?.Invoke("MIDI learn armed: move a knob/fader for " + description);
    }

    private void OnMessage(object? sender, MidiInMessageEventArgs e)
    {
        try
        {
            if (e.MidiEvent is NoteOnEvent on)
            {
                if (on.Velocity > 0) NoteOn?.Invoke(on.Channel, on.NoteNumber, on.Velocity);
                else NoteOff?.Invoke(on.Channel, on.NoteNumber);
            }
            else if (e.MidiEvent is NoteEvent off && off.CommandCode == MidiCommandCode.NoteOff)
            {
                NoteOff?.Invoke(off.Channel, off.NoteNumber);
            }
            else if (e.MidiEvent is ControlChangeEvent cc)
            {
                int controller = (int)cc.Controller;
                int value = cc.ControllerValue;
                if (learnTarget != null)
                {
                    var target = learnTarget;
                    var desc = learnDescription ?? "parameter";
                    learnTarget = null; learnDescription = null;
                    target(cc.Channel, controller, value);
                    Log?.Invoke($"MIDI learn mapped {desc} → Ch {cc.Channel} CC {controller}");
                }
                ControlChange?.Invoke(cc.Channel, controller, value);
                ChannelEvent?.Invoke(cc.Channel, controller == 64 ? MidiClipEventKind.SustainPedal : MidiClipEventKind.ControlChange, controller, value);
            }

            // NAudio exposes pitch-bend/program/pressure through different event
            // subclasses across versions. Decode the packed WinMM short message too
            // so recording these controllers is robust on Windows VMs.
            int raw = e.MidiEvent.GetAsShortMessage();
            int status = raw & 0xFF;
            int command = status & 0xF0;
            int channel = (status & 0x0F) + 1;
            int data1 = (raw >> 8) & 0x7F;
            int data2 = (raw >> 16) & 0x7F;
            if (command == 0xE0)
            {
                int bend = (data2 << 7) | data1;
                PitchBend?.Invoke(channel, bend);
                ChannelEvent?.Invoke(channel, MidiClipEventKind.PitchBend, bend, 0);
            }
            else if (command == 0xA0)
            {
                ChannelEvent?.Invoke(channel, MidiClipEventKind.PolyPressure, data1, data2);
            }
            else if (command == 0xC0)
            {
                ChannelEvent?.Invoke(channel, MidiClipEventKind.ProgramChange, data1, 0);
            }
            else if (command == 0xD0)
            {
                ChannelEvent?.Invoke(channel, MidiClipEventKind.ChannelPressure, data1, 0);
            }
        }
        catch (Exception ex) { Log?.Invoke("MIDI message handling failed: " + ex.Message); }
    }

    public void Dispose() => CloseInput();
}
