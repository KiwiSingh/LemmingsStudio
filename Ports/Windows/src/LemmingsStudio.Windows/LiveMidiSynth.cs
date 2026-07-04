using System.Collections.Concurrent;
using NAudio.Wave;

namespace LemmingsStudio.Windows;

/// <summary>Small always-on live audition synth for native Windows MIDI input.</summary>
public sealed class LiveMidiSynth : ISampleProvider, IDisposable
{
    private readonly WaveOutEvent output;
    private readonly ConcurrentDictionary<int, Voice> voices = new();
    private readonly WaveFormat format = WaveFormat.CreateIeeeFloatWaveFormat(AudioEngine.SampleRate, AudioEngine.Channels);
    private volatile double pitchBendSemitones;
    private volatile double modWheel01;

    public WaveFormat WaveFormat => format;
    public bool Enabled { get; set; } = true;
    public Track? TargetTrack { get; set; }

    public LiveMidiSynth()
    {
        output = new WaveOutEvent { DesiredLatency = 45 };
        output.Init(this);
        output.Play();
    }

    public void NoteOn(int note, int velocity, Track? track = null)
    {
        if (!Enabled) return;
        var t = track ?? TargetTrack;
        var dev = t?.Devices.FirstOrDefault(d => d.Enabled && (d.Name.Contains("Oscillatron", StringComparison.OrdinalIgnoreCase) || d.Name.Contains("LemmingBass", StringComparison.OrdinalIgnoreCase)))
                  ?? t?.Devices.FirstOrDefault(d => d.Enabled);
        voices[note] = new Voice(note, Math.Clamp(velocity / 127f, 0f, 1f), dev, () => pitchBendSemitones, () => modWheel01, () => t?.ModWheelDepthSemitones ?? 0.35);
    }

    public void NoteOff(int note)
    {
        if (voices.TryGetValue(note, out var v)) v.Releasing = true;
    }

    public void PitchBend(int value14Bit, int rangeSemitones)
    {
        value14Bit = Math.Clamp(value14Bit, 0, 16383);
        var centered = (value14Bit - 8192) / 8192.0;
        pitchBendSemitones = centered * Math.Clamp(rangeSemitones, 0, 48);
    }

    public void ModWheel(int value)
    {
        modWheel01 = Math.Clamp(value / 127.0, 0.0, 1.0);
    }

    public int Read(float[] buffer, int offset, int count)
    {
        Array.Clear(buffer, offset, count);
        int frames = count / 2;
        var dead = new List<int>();
        foreach (var kv in voices)
        {
            var v = kv.Value;
            for (int f = 0; f < frames; f++)
            {
                float s = v.Next();
                buffer[offset + f * 2] += s;
                buffer[offset + f * 2 + 1] += s;
            }
            if (v.Done) dead.Add(kv.Key);
        }
        foreach (var k in dead) voices.TryRemove(k, out _);
        for (int i = offset; i < offset + count; i++) buffer[i] = Math.Clamp(buffer[i], -0.85f, 0.85f);
        return count;
    }

    public void Dispose() => output.Dispose();

    private sealed class Voice
    {
        private readonly double baseFreq;
        private readonly Func<double> pitchBendSemis;
        private readonly Func<double> mod01;
        private readonly Func<double> modDepthSemis;
        private double phase;
        private double vibratoPhase;
        private float amp;
        private readonly bool bass;
        private readonly float drive;
        public bool Releasing { get; set; }
        public bool Done => amp < 0.0002f;

        public Voice(int note, float velocity, DeviceSlot? dev, Func<double> pitchBendSemis, Func<double> mod01, Func<double> modDepthSemis)
        {
            baseFreq = 440.0 * Math.Pow(2.0, (note - 69) / 12.0);
            this.pitchBendSemis = pitchBendSemis;
            this.mod01 = mod01;
            this.modDepthSemis = modDepthSemis;
            amp = velocity * 0.25f;
            bass = dev?.Name.Contains("LemmingBass", StringComparison.OrdinalIgnoreCase) == true;
            drive = (float)(1.0 + (dev?.Parameters.TryGetValue("Drive", out var d) == true ? d : 0.15) * 4.0);
        }

        public float Next()
        {
            vibratoPhase += 5.5 / AudioEngine.SampleRate;
            if (vibratoPhase >= 1.0) vibratoPhase -= 1.0;
            double mod = mod01();
            double vibrato = Math.Sin(vibratoPhase * Math.PI * 2.0) * mod * Math.Max(0.0, modDepthSemis());
            double semis = pitchBendSemis() + vibrato;
            double inc = baseFreq * Math.Pow(2.0, semis / 12.0) / AudioEngine.SampleRate;
            phase += inc; if (phase >= 1.0) phase -= Math.Floor(phase);
            float sine = (float)Math.Sin(phase * Math.PI * 2.0);
            float saw = (float)(2.0 * phase - 1.0);
            float raw = bass ? (0.78f * sine + 0.22f * Math.Sign(sine)) : (0.55f * saw + 0.45f * sine);
            float brightness = (float)(1.0 + mod * 0.20);
            float s = (float)Math.Tanh(raw * drive * brightness) * amp;
            amp *= Releasing ? 0.992f : 0.9996f;
            return s;
        }
    }
}
