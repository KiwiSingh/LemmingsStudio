using NAudio.Wave;
using NAudio.Wave.SampleProviders;

namespace LemmingsStudio.Windows;

/// <summary>
/// First real audio-engine parity layer for the Windows port.
///
/// Renders the arrangement to an in-memory 44.1 kHz stereo float buffer:
///   • Audio clips are decoded with NAudio (WAV/MP3/AIFF/FLAC), resampled to the
///     project rate, optionally tempo-warped (naive linear resample), placed at
///     their beat position and summed with per-track volume/pan/mute/solo.
///   • MIDI clips on instrument tracks are voiced by a small built-in poly synth
///     (saw+square → one-pole low-pass from the stock device "Cutoff" → ADSR) so
///     instrument tracks are audible without a plugin host yet.
///
/// The same rendered buffer powers both realtime playback (WaveOutEvent) and WAV
/// export (WaveFileWriter), so what you hear is what you bounce.
///
/// Time-stretch fidelity, MIDI-clip warping nuance and VST3 instruments are later
/// port layers — see Docs/WindowsPortPlan.md.
/// </summary>
public sealed class AudioEngine : IDisposable
{
    public const int SampleRate = 44100;
    public const int Channels = 2;

    public event Action<string>? Log;
    public event Action? PlaybackStopped;
    public readonly record struct MeterState(float Peak, float Rms, float HoldPeak, bool Clipped);
    public Dictionary<string, MeterState> LastMeters { get; } = new();
    private readonly Dictionary<string, float> _meterHold = new();
    private readonly HashSet<string> _meterClipped = new();

    public void ResetClipIndicators()
    {
        _meterClipped.Clear();
        _meterHold.Clear();
        foreach (var key in LastMeters.Keys.ToList())
        {
            var m = LastMeters[key];
            LastMeters[key] = m with { HoldPeak = m.Peak, Clipped = false };
        }
    }

    private WaveOutEvent? _output;
    private FloatBufferSampleProvider? _provider;

    public bool IsPlaying { get; private set; }

    /// <summary>Output buffer latency in ms. Lower = snappier transport but higher risk of
    /// audio dropouts on slower machines / inside a VM. Surfaced in the transport bar.</summary>
    public int OutputLatencyMs { get; set; } = 200;

    /// <summary>Beats → seconds at a fixed tempo.</summary>
    private static double BeatsToSeconds(double beats, double tempo) => beats * 60.0 / Math.Max(1.0, tempo);

    /// <summary>Render the project with per-track buffers, post-fader sends, return buses and master stage.</summary>
    public float[] Render(StudioProject project)
    {
        double tempo = project.Tempo <= 0 ? 120 : project.Tempo;
        double maxBeat = 4;
        foreach (var t in project.Tracks)
        {
            foreach (var c in t.Clips) maxBeat = Math.Max(maxBeat, c.StartBeat + Math.Max(0.25, c.LengthBeats));
            if (t.UseStepSequencer && t.StepPattern.Hits.Count > 0)
                maxBeat = Math.Max(maxBeat, Math.Max(4.0, t.StepPattern.StepCount / (double)Math.Max(1, t.StepPattern.StepsPerBeat)));
        }

        int totalFrames = (int)Math.Ceiling(BeatsToSeconds(maxBeat, tempo) * SampleRate) + SampleRate;
        var master = new float[totalFrames * Channels];
        var returnInputs = project.ReturnBuses.ToDictionary(b => b.Id, _ => new float[totalFrames * Channels]);
        bool anyTrackSolo = project.Tracks.Any(t => t.Solo);
        bool anyReturnSolo = project.ReturnBuses.Any(b => b.Solo);

        LastMeters.Clear();

        foreach (var track in project.Tracks)
        {
            if (track.Muted) { UpdateMeter("track:" + track.Id, Array.Empty<float>()); continue; }
            if (anyTrackSolo && !track.Solo) { UpdateMeter("track:" + track.Id, Array.Empty<float>()); continue; }

            var trackBuffer = RenderTrackBuffer(track, tempo, totalFrames);
            ApplyTrackFaderAndPan(trackBuffer, track.Volume, track.Pan);
            UpdateMeter("track:" + track.Id, trackBuffer);

            // Direct output routing: Master by default, or route the full post-fader signal to a return bus.
            if (track.OutputBusId is Guid outputBus && returnInputs.TryGetValue(outputBus, out var routedBus))
                MixInto(routedBus, totalFrames, trackBuffer, 0, 1f, 1f);
            else
                MixInto(master, totalFrames, trackBuffer, 0, 1f, 1f);

            // buildfix244: post-fader sends feed independent return-bus buffers.
            foreach (var send in track.Sends)
            {
                if (send.Value <= 0 || !returnInputs.TryGetValue(send.Key, out var busBuffer)) continue;
                float amount = Math.Clamp(send.Value, 0f, 1.5f);
                MixInto(busBuffer, totalFrames, trackBuffer, 0, amount, amount);
            }
        }

        foreach (var bus in project.ReturnBuses)
        {
            if (!returnInputs.TryGetValue(bus.Id, out var input)) continue;
            if (bus.Muted || (anyReturnSolo && !bus.Solo))
            {
                UpdateMeter("return:" + bus.Id, Array.Empty<float>());
                continue;
            }

            var pseudoTrack = new Track
            {
                Name = bus.Name,
                Type = TrackType.Bus,
                Devices = bus.Devices,
                Automation = bus.Automation
            };
            var processed = ApplyDeviceChain(input, pseudoTrack, 0, tempo);
            ApplyTrackFaderAndPan(processed, bus.Volume, bus.Pan);
            UpdateMeter("return:" + bus.Id, processed);
            MixInto(master, totalFrames, processed, 0, 1f, 1f);
        }

        if (project.MetronomeEnabled)
            RenderMetronome(master, totalFrames, maxBeat, tempo, Math.Max(1, project.BeatsPerBar));

        float masterGain = project.MasterMuted ? 0f : Math.Clamp(project.MasterVolume, 0f, 1.25f);
        for (int i = 0; i < master.Length; i++) master[i] *= masterGain;
        UpdateMeter("master", master);

        // Safety clamp after metering so CLIP indicators still report overs.
        for (int i = 0; i < master.Length; i++) master[i] = Math.Clamp(master[i], -1f, 1f);
        return master;
    }

    private float[] RenderTrackBuffer(Track track, double tempo, int totalFrames)
    {
        var output = new float[totalFrames * Channels];

        if (track.UseStepSequencer && track.StepPattern.Hits.Count > 0)
        {
            try
            {
                ApplyDeviceAutomation(track, 0);
                var stepStereo = ApplyDeviceChain(RenderStepSequencerTrack(track, tempo), track, 0, tempo);
                MixInto(output, totalFrames, stepStereo, 0, 1f, 1f);
            }
            catch (Exception ex) { Log?.Invoke($"Render skipped step sequencer on '{track.Name}': {ex.Message}"); }
        }

        foreach (var clip in track.Clips)
        {
            int startFrame = Math.Max(0, (int)Math.Round(BeatsToSeconds(clip.StartBeat, tempo) * SampleRate));
            try
            {
                float[]? clipStereo = null;
                if (clip.Type == ClipType.Audio && !string.IsNullOrWhiteSpace(clip.SourcePath) && File.Exists(clip.SourcePath))
                {
                    clipStereo = DecodeToStereo(clip.SourcePath!);
                    double stretch = (clip.WarpEnabled && clip.SourceTempo > 0) ? clip.SourceTempo / tempo : 1.0;
                    if (Math.Abs(stretch - 1.0) > 0.001) clipStereo = ResampleInterleavedStereo(clipStereo, stretch);
                    int offsetFrames = Math.Max(0, (int)Math.Round(BeatsToSeconds(clip.SourceOffsetBeats, tempo) * SampleRate));
                    int wantedFrames = Math.Max(1, (int)Math.Round(BeatsToSeconds(clip.LengthBeats, tempo) * SampleRate));
                    clipStereo = SliceInterleavedStereo(clipStereo, offsetFrames, wantedFrames);
                }
                else if (clip.Type == ClipType.Midi && clip.Notes.Count > 0)
                    clipStereo = RenderMidiClip(clip, track, tempo);

                if (clipStereo == null) continue;
                ApplyDeviceAutomation(track, clip.StartBeat);
                clipStereo = ApplyDeviceChain(clipStereo, track, clip.StartBeat, tempo);
                float clipGain = (float)Math.Clamp(clip.Gain, 0.0, 4.0);
                MixInto(output, totalFrames, clipStereo, startFrame, clipGain, clipGain);
            }
            catch (Exception ex) { Log?.Invoke($"Render skipped clip '{clip.Name}': {ex.Message}"); }
        }
        return output;
    }

    private static void ApplyTrackFaderAndPan(float[] stereo, float volume, float pan)
    {
        float vol = Math.Clamp(volume, 0f, 1.25f);
        double angle = (Math.Clamp(pan, -1f, 1f) + 1.0) * Math.PI / 4.0;
        float gl = vol * (float)Math.Cos(angle);
        float gr = vol * (float)Math.Sin(angle);
        for (int i = 0; i + 1 < stereo.Length; i += 2)
        {
            stereo[i] *= gl;
            stereo[i + 1] *= gr;
        }
    }

    private void UpdateMeter(string key, float[] stereo)
    {
        float peak = 0f;
        double sum = 0;
        if (stereo.Length > 0)
        {
            foreach (var v in stereo)
            {
                float a = Math.Abs(v);
                if (a > peak) peak = a;
                sum += v * v;
            }
        }
        float rms = stereo.Length == 0 ? 0f : (float)Math.Sqrt(sum / stereo.Length);
        float hold = Math.Max(peak, _meterHold.TryGetValue(key, out var old) ? old * 0.985f : 0f);
        _meterHold[key] = hold;
        if (peak >= 1f) _meterClipped.Add(key);
        LastMeters[key] = new MeterState(peak, rms, hold, _meterClipped.Contains(key));
    }

    private static float[] RenderStepSequencerTrack(Track track, double tempo)
    {
        var pattern = track.StepPattern;
        double stepBeats = 1.0 / Math.Max(1, pattern.StepsPerBeat);
        double patternBeats = Math.Max(stepBeats, pattern.StepCount * stepBeats);
        int totalFrames = (int)Math.Ceiling(BeatsToSeconds(patternBeats, tempo) * SampleRate) + SampleRate;
        var output = new float[totalFrames * Channels];

        // Preserve synth/drum-machine playback for lanes without a sample path.
        var midiClip = new ProjectClip { Type = ClipType.Midi, Name = track.Name + " Pattern", StartBeat = 0, LengthBeats = patternBeats };
        foreach (var hit in pattern.Hits.OrderBy(h => h.Step))
        {
            var layer = track.SequencerLayers.FirstOrDefault(l => l.Note == hit.Note);
            if (layer != null && !string.IsNullOrWhiteSpace(layer.SourcePath) && File.Exists(layer.SourcePath))
            {
                var sample = DecodeToStereo(layer.SourcePath);
                int startFrame = (int)Math.Round(BeatsToSeconds(hit.Step * stepBeats, tempo) * SampleRate);
                float layerVol = (float)Math.Clamp(layer.Volume, 0.0, 4.0);
                double panAngle = (Math.Clamp(layer.Pan, -1.0, 1.0) + 1.0) * Math.PI / 4.0;
                float left = layerVol * (float)Math.Cos(panAngle);
                float right = layerVol * (float)Math.Sin(panAngle);
                MixInto(output, totalFrames, sample, startFrame, left, right);
            }
            else
            {
                int octave = layer?.OctaveOffset ?? 0;
                midiClip.Notes.Add(new MidiNote(hit.Step * stepBeats, Math.Min(stepBeats * 0.9, 0.24), hit.Note + octave * 12, hit.Velocity));
            }
        }

        if (midiClip.Notes.Count > 0)
        {
            var synth = RenderMidiClip(midiClip, track, tempo);
            MixInto(output, totalFrames, synth, 0, 1f, 1f);
        }
        return output;
    }

    private static void ApplyDeviceAutomation(Track track, double beat)
    {
        foreach (var lane in track.Automation.Where(a => a.Kind == AutomationTargetKind.DeviceParameter && !string.IsNullOrWhiteSpace(a.DeviceId) && !string.IsNullOrWhiteSpace(a.ParameterId)))
        {
            var device = track.Devices.FirstOrDefault(d => string.Equals(d.Id.ToString(), lane.DeviceId, StringComparison.OrdinalIgnoreCase));
            if (device == null) continue;
            var key = lane.ParameterId!;
            var value = EvaluateAutomation(lane, beat);
            value = Math.Clamp(value, lane.Minimum, lane.Maximum);
            var normalized = lane.Maximum > lane.Minimum ? (value - lane.Minimum) / (lane.Maximum - lane.Minimum) : value;
            normalized = Math.Clamp(normalized, 0.0, 1.0);
            device.Parameters[key] = normalized;
            if (device.IsVst3 && key.StartsWith("VST3:", StringComparison.OrdinalIgnoreCase))
                Vst3NativeHostBridge.Shared.SetParameter(device, key, normalized);
        }
    }

    private static double EvaluateAutomation(AutomationLane lane, double beat)
    {
        if (lane.Points.Count == 0) return lane.Minimum;
        var pts = lane.Points.OrderBy(p => p.Beat).ToList();
        if (beat <= pts[0].Beat) return pts[0].Value;
        if (beat >= pts[^1].Beat) return pts[^1].Value;
        for (int i = 0; i < pts.Count - 1; i++)
        {
            var a = pts[i]; var b = pts[i + 1];
            if (beat >= a.Beat && beat <= b.Beat)
            {
                var t = (beat - a.Beat) / Math.Max(0.000001, b.Beat - a.Beat);
                return a.Value + (b.Value - a.Value) * t;
            }
        }
        return pts[^1].Value;
    }

    /// <summary>Apply the track's enabled EFFECT devices to a stereo buffer, in order.</summary>
    private static float[] ApplyDeviceChain(float[] stereo, Track track, double startBeat, double tempo)
    {
        foreach (var device in track.Devices)
        {
            if (!device.Enabled) continue;
            if (device.Name.Contains("Auto Filter", StringComparison.OrdinalIgnoreCase))
                FilterDrive(stereo, Param(device, "Cutoff", 1.0), Param(device, "Drive", 0.0));
            else if (device.Name.Contains("Saturator", StringComparison.OrdinalIgnoreCase))
                FilterDrive(stereo, 1.0, Param(device, "Drive", 0.35), Param(device, "Wet", 1.0));
            else if (device.Name.Contains("Bit Crusher", StringComparison.OrdinalIgnoreCase)
                  || device.Name.Contains("Redux", StringComparison.OrdinalIgnoreCase))
                BitCrush(stereo, Param(device, "Bits", 0.4), Param(device, "Downsample", 0.3), Param(device, "Wet", 1.0));
            else if (device.Name.Contains("EQ Three", StringComparison.OrdinalIgnoreCase)
                  || device.Name.Equals("EQ", StringComparison.OrdinalIgnoreCase))
                EqThree(stereo, Param(device, "Low", 0.5), Param(device, "Mid", 0.5), Param(device, "High", 0.5), Param(device, "Gain", 0.5));
            else if (device.Name.Contains("Compressor", StringComparison.OrdinalIgnoreCase))
                Compress(stereo, Param(device, "Threshold", 0.5), Param(device, "Ratio", 0.4), Param(device, "Attack", 0.2), Param(device, "Release", 0.4), Param(device, "Makeup", 0.3));
            else if (device.Name.Contains("Reverb", StringComparison.OrdinalIgnoreCase))
                Reverb(stereo, Param(device, "Size", 0.5), Param(device, "Decay", 0.5), Param(device, "Wet", 0.3));
            else if (device.Name.Contains("Delay", StringComparison.OrdinalIgnoreCase))
                Delay(stereo, Param(device, "Time", 0.35), Param(device, "Feedback", 0.3), Param(device, "Wet", 0.3));
            else if (device.Name.Contains("Utility", StringComparison.OrdinalIgnoreCase))
                Utility(stereo, Param(device, "Gain", 0.5), Param(device, "Width", 0.5), Param(device, "Pan", 0.5));
            else if (device.IsVst3)
            {
                // buildfix231: run VST3 effects through the native helper during
                // playback/export. If the helper/plugin fails, keep the dry buffer
                // instead of making the entire render explode.
                var processed = Vst3NativeHostBridge.Shared.ProcessAudio(device, stereo, SampleRate, Channels, automation: BuildVst3Automation(track, device, startBeat, stereo.Length / Channels, tempo));
                if (processed is { Length: > 0 })
                {
                    stereo = processed;
                    if (device.PluginLatencySamples > 0 && device.PluginLatencySamples * Channels < stereo.Length)
                    {
                        var shift = device.PluginLatencySamples * Channels;
                        Array.Copy(stereo, shift, stereo, 0, stereo.Length - shift);
                        Array.Clear(stereo, stereo.Length - shift, shift);
                    }
                }
            }
        }
        return stereo;
    }

    /// <summary>One-pole low-pass (from Cutoff) + tanh drive, with optional dry/wet.</summary>
    private static void FilterDrive(float[] stereo, double cutoff, double drive, double wet = 1.0)
    {
        bool filter = cutoff < 0.999;
        bool dist = drive > 0.001;
        if (!filter && !dist) return;
        float alpha = OnePoleAlpha(cutoff, 18000.0);
        float driveAmt = (float)(1.0 + drive * 4.0);
        float wetF = (float)Math.Clamp(wet, 0.0, 1.0), dryF = 1f - wetF;
        int frames = stereo.Length / Channels; float lpL = 0f, lpR = 0f;
        for (int f = 0; f < frames; f++)
        {
            float l = stereo[f * 2], r = stereo[f * 2 + 1]; float dl = l, dr = r;
            if (filter) { lpL += alpha * (l - lpL); l = lpL; lpR += alpha * (r - lpR); r = lpR; }
            if (dist) { l = (float)Math.Tanh(l * driveAmt); r = (float)Math.Tanh(r * driveAmt); }
            stereo[f * 2] = dl * dryF + l * wetF; stereo[f * 2 + 1] = dr * dryF + r * wetF;
        }
    }

    /// <summary>Bit Crusher (Redux): amplitude bit-depth reduction + sample-rate sample-and-hold.</summary>
    private static void BitCrush(float[] stereo, double bitsNorm, double downsampleNorm, double wet)
    {
        // bitsNorm 1 → ~16-bit (clean), 0 → ~1-bit (heavy). downsampleNorm 0 → none, 1 → ~40x hold.
        double bitDepth = 1.0 + Math.Clamp(bitsNorm, 0.0, 1.0) * 15.0;
        float levels = (float)Math.Pow(2.0, bitDepth);
        int hold = 1 + (int)Math.Round(Math.Clamp(downsampleNorm, 0.0, 1.0) * 40.0);
        float wetF = (float)Math.Clamp(wet, 0.0, 1.0), dryF = 1f - wetF;
        int frames = stereo.Length / Channels;
        float heldL = 0f, heldR = 0f; int counter = 0;
        for (int f = 0; f < frames; f++)
        {
            if (counter == 0)
            {
                heldL = (float)(Math.Round(stereo[f * 2] * levels) / levels);
                heldR = (float)(Math.Round(stereo[f * 2 + 1] * levels) / levels);
            }
            counter = (counter + 1) % hold;
            stereo[f * 2] = stereo[f * 2] * dryF + heldL * wetF;
            stereo[f * 2 + 1] = stereo[f * 2 + 1] * dryF + heldR * wetF;
        }
    }

    private static float AlphaForHz(double fcHz)
    {
        double rc = 1.0 / (2.0 * Math.PI * Math.Max(20.0, fcHz));
        double dt = 1.0 / SampleRate;
        return (float)(dt / (rc + dt));
    }

    /// <summary>3-band EQ (low/mid/high gains, 0.5 = unity) + output gain.</summary>
    private static void EqThree(float[] s, double low, double mid, double high, double outGain)
    {
        float gl = (float)(low * 2), gm = (float)(mid * 2), gh = (float)(high * 2), gout = (float)(outGain * 2);
        float aLow = AlphaForHz(250), aHigh = AlphaForHz(3500);
        int frames = s.Length / Channels;
        float lpLowL = 0, lpLowR = 0, lpHiL = 0, lpHiR = 0;
        for (int f = 0; f < frames; f++)
        {
            float xl = s[f * 2], xr = s[f * 2 + 1];
            lpLowL += aLow * (xl - lpLowL); lpHiL += aHigh * (xl - lpHiL);
            lpLowR += aLow * (xr - lpLowR); lpHiR += aHigh * (xr - lpHiR);
            float yl = lpLowL * gl + (lpHiL - lpLowL) * gm + (xl - lpHiL) * gh;
            float yr = lpLowR * gl + (lpHiR - lpLowR) * gm + (xr - lpHiR) * gh;
            s[f * 2] = yl * gout; s[f * 2 + 1] = yr * gout;
        }
    }

    /// <summary>Feed-forward compressor with envelope follower + makeup gain.</summary>
    private static void Compress(float[] s, double threshold, double ratioN, double attack, double release, double makeup)
    {
        float thr = (float)(0.05 + threshold * 0.95);
        double ratio = 1.0 + ratioN * 9.0;
        float atk = (float)Math.Exp(-1.0 / ((0.001 + attack * 0.05) * SampleRate));
        float rel = (float)Math.Exp(-1.0 / ((0.02 + release * 0.4) * SampleRate));
        float makeupGain = (float)(1.0 + makeup * 2.0);
        int frames = s.Length / Channels; float env = 0f;
        for (int f = 0; f < frames; f++)
        {
            float l = s[f * 2], r = s[f * 2 + 1];
            float det = Math.Max(Math.Abs(l), Math.Abs(r));
            float coef = det > env ? atk : rel;
            env = coef * (env - det) + det;
            float g = env > thr ? (float)Math.Pow(env / thr, (1.0 / ratio) - 1.0) : 1f;
            g *= makeupGain;
            s[f * 2] = l * g; s[f * 2 + 1] = r * g;
        }
    }

    /// <summary>Freeverb-lite: four comb filters + one all-pass per channel, dry/wet mixed.</summary>
    private static void Reverb(float[] s, double size, double decay, double wet)
    {
        int frames = s.Length / Channels;
        if (frames == 0) return;
        double scale = 0.7 + size * 0.6;
        int[] combLen = { (int)(1116 * scale), (int)(1188 * scale), (int)(1277 * scale), (int)(1356 * scale) };
        int apLen = Math.Max(8, (int)(556 * scale));
        float fb = (float)Math.Min(0.97, 0.7 + decay * 0.28);
        float wetF = (float)Math.Clamp(wet, 0.0, 1.0), dryF = 1f - wetF * 0.5f;

        for (int ch = 0; ch < Channels; ch++)
        {
            var combs = new float[4][];
            var idx = new int[4];
            for (int c = 0; c < 4; c++) combs[c] = new float[Math.Max(8, combLen[c] + ch * 23)]; // small L/R offset for width
            var ap = new float[apLen + ch * 17];
            int apIdx = 0;
            for (int f = 0; f < frames; f++)
            {
                float x = s[f * 2 + ch];
                float combSum = 0f;
                for (int c = 0; c < 4; c++)
                {
                    int n = combs[c].Length;
                    float y = combs[c][idx[c]];
                    combSum += y;
                    combs[c][idx[c]] = x + y * fb;
                    idx[c] = (idx[c] + 1) % n;
                }
                combSum *= 0.25f;
                // all-pass
                float buf = ap[apIdx];
                float outAp = -combSum + buf;
                ap[apIdx] = combSum + buf * 0.5f;
                apIdx = (apIdx + 1) % ap.Length;
                s[f * 2 + ch] = x * dryF + outAp * wetF;
            }
        }
    }

    /// <summary>Feedback delay per channel, dry/wet mixed.</summary>
    private static void Delay(float[] s, double time, double feedback, double wet)
    {
        int frames = s.Length / Channels;
        int delaySamples = Math.Max(1, (int)((0.05 + time * 0.75) * SampleRate));
        float fb = (float)Math.Clamp(feedback * 0.9, 0.0, 0.9);
        float wetF = (float)Math.Clamp(wet, 0.0, 1.0);
        for (int ch = 0; ch < Channels; ch++)
        {
            var line = new float[delaySamples];
            int idx = 0;
            for (int f = 0; f < frames; f++)
            {
                float x = s[f * 2 + ch];
                float echo = line[idx];
                line[idx] = x + echo * fb;
                idx = (idx + 1) % delaySamples;
                s[f * 2 + ch] = x + echo * wetF;
            }
        }
    }

    /// <summary>Utility: gain (0.5 = unity), stereo width (mid/side), and pan.</summary>
    private static void Utility(float[] s, double gain, double width, double pan)
    {
        float g = (float)(gain * 2.0);
        float w = (float)(width * 2.0); // 0 = mono, 1 = normal, 2 = wide
        double panAngle = (Math.Clamp((pan - 0.5) * 2.0, -1.0, 1.0) + 1.0) * Math.PI / 4.0;
        float pl = (float)Math.Cos(panAngle), pr = (float)Math.Sin(panAngle);
        int frames = s.Length / Channels;
        for (int f = 0; f < frames; f++)
        {
            float l = s[f * 2], r = s[f * 2 + 1];
            float mid = (l + r) * 0.5f, side = (l - r) * 0.5f * w;
            l = mid + side; r = mid - side;
            // equal-power pan keeps centre ~unity (×√2 baked into pl/pr)
            s[f * 2] = l * g * pl * 1.41421f; s[f * 2 + 1] = r * g * pr * 1.41421f;
        }
    }


    /// <summary>Arrangement-synced metronome click, matching the Mac beta expectation that click follows render time.</summary>
    private static void RenderMetronome(float[] mix, int totalFrames, double maxBeat, double tempo, int beatsPerBar)
    {
        int clickFrames = (int)(0.035 * SampleRate);
        for (int beat = 0; beat <= Math.Ceiling(maxBeat) + 1; beat++)
        {
            int start = (int)Math.Round(BeatsToSeconds(beat, tempo) * SampleRate);
            if (start >= totalFrames) break;
            bool downbeat = beat % beatsPerBar == 0;
            double hz = downbeat ? 1760.0 : 1174.66;
            float gain = downbeat ? 0.32f : 0.22f;
            for (int i = 0; i < clickFrames; i++)
            {
                int f = start + i;
                if (f < 0 || f >= totalFrames) break;
                float env = 1f - i / (float)Math.Max(1, clickFrames);
                float sample = (float)(Math.Sin(2.0 * Math.PI * hz * i / SampleRate) * gain * env * env);
                mix[f * 2] += sample;
                mix[f * 2 + 1] += sample;
            }
        }
    }

    private static void MixInto(float[] mix, int mixFrames, float[] clipStereo, int startFrame, float gainL, float gainR)
    {
        int clipFrames = clipStereo.Length / Channels;
        for (int f = 0; f < clipFrames; f++)
        {
            int dst = startFrame + f;
            if (dst < 0) continue;
            if (dst >= mixFrames) break;
            mix[dst * 2] += clipStereo[f * 2] * gainL;
            mix[dst * 2 + 1] += clipStereo[f * 2 + 1] * gainR;
        }
    }

    /// <summary>Decode any NAudio-readable file to interleaved stereo at the project rate.</summary>
    private static float[] DecodeToStereo(string path)
    {
        using var reader = new AudioFileReader(path);
        int srcChannels = Math.Max(1, reader.WaveFormat.Channels);
        ISampleProvider sp = reader;
        if (reader.WaveFormat.SampleRate != SampleRate)
            sp = new WdlResamplingSampleProvider(sp, SampleRate);

        // Read everything (resampling preserves the source channel count).
        var raw = new List<float>(SampleRate * srcChannels);
        var buffer = new float[SampleRate * srcChannels];
        int read;
        while ((read = sp.Read(buffer, 0, buffer.Length)) > 0)
            for (int i = 0; i < read; i++) raw.Add(buffer[i]);

        int frames = raw.Count / srcChannels;
        var stereo = new float[frames * Channels];
        for (int f = 0; f < frames; f++)
        {
            float l = raw[f * srcChannels];
            float r = srcChannels > 1 ? raw[f * srcChannels + 1] : l;
            stereo[f * 2] = l;
            stereo[f * 2 + 1] = r;
        }
        return stereo;
    }


    private static float[] SliceInterleavedStereo(float[] input, int offsetFrames, int wantedFrames)
    {
        int totalFrames = input.Length / Channels;
        int start = Math.Clamp(offsetFrames, 0, totalFrames);
        int frames = Math.Clamp(wantedFrames, 0, totalFrames - start);
        if (frames <= 0) return Array.Empty<float>();
        var output = new float[frames * Channels];
        Array.Copy(input, start * Channels, output, 0, output.Length);
        return output;
    }

    /// <summary>Naive linear-interpolation time-stretch (changes pitch; placeholder for real warping).</summary>
    private static float[] ResampleInterleavedStereo(float[] input, double stretch)
    {
        int inFrames = input.Length / Channels;
        int outFrames = Math.Max(1, (int)Math.Round(inFrames * stretch));
        var output = new float[outFrames * Channels];
        double step = (double)inFrames / outFrames;
        for (int f = 0; f < outFrames; f++)
        {
            double pos = f * step;
            int i0 = (int)pos;
            int i1 = Math.Min(i0 + 1, inFrames - 1);
            float frac = (float)(pos - i0);
            for (int ch = 0; ch < Channels; ch++)
            {
                float a = input[i0 * 2 + ch];
                float b = input[i1 * 2 + ch];
                output[f * 2 + ch] = a + (b - a) * frac;
            }
        }
        return output;
    }


    private static List<Vst3AutomationEvent> BuildVst3Automation(Track track, DeviceSlot device, double startBeat, int frames, double tempo)
    {
        var events = new List<Vst3AutomationEvent>();
        foreach (var lane in track.Automation.Where(a => a.Kind == AutomationTargetKind.DeviceParameter &&
                                                         string.Equals(a.DeviceId, device.Id.ToString(), StringComparison.OrdinalIgnoreCase) &&
                                                         !string.IsNullOrWhiteSpace(a.ParameterId)))
        {
            if (!lane.ParameterId!.StartsWith("VST3:", StringComparison.OrdinalIgnoreCase)) continue;
            var points = lane.Points.OrderBy(p => p.Beat).ToList();
            if (points.Count == 0) continue;
            // buildfix234: densify automation into small frame steps, then the native
            // helper splits VST3 processing blocks at those events. This is much closer
            // to DAW automation behavior than the earlier clip/block-only changes while
            // avoiding a parameter write on literally every sample for every lane.
            const int automationStepFrames = 64;
            for (int frame = 0; frame < frames; frame += automationStepFrames)
            {
                double beat = startBeat + (frame / (double)SampleRate) * tempo / 60.0;
                double value = EvaluateAutomation(lane, beat);
                double norm = lane.Maximum > lane.Minimum ? (value - lane.Minimum) / (lane.Maximum - lane.Minimum) : value;
                events.Add(new Vst3AutomationEvent(frame, lane.ParameterId!, Math.Clamp(norm, 0.0, 1.0)));
            }
            foreach (var pt in points.Where(p => p.Beat >= startBeat))
            {
                int frame = (int)Math.Round(BeatsToSeconds(pt.Beat - startBeat, tempo) * SampleRate);
                if (frame < 0 || frame >= frames) continue;
                var norm = lane.Maximum > lane.Minimum ? (pt.Value - lane.Minimum) / (lane.Maximum - lane.Minimum) : pt.Value;
                events.Add(new Vst3AutomationEvent(frame, lane.ParameterId!, Math.Clamp(norm, 0.0, 1.0)));
            }
        }
        return events
            .GroupBy(e => (e.Frame, e.ParameterKey), e => e)
            .Select(g => g.Last())
            .OrderBy(e => e.Frame)
            .ToList();
    }

    private static double Param(DeviceSlot? d, string key, double fallback)
        => d != null && d.Parameters.TryGetValue(key, out var v) ? v : fallback;

    /// <summary>Voice a MIDI clip with the track's instrument (stock / Oscillatron / LemmingBass).</summary>
    private static float[] RenderMidiClip(ProjectClip clip, Track track, double tempo)
    {
        double clipSeconds = BeatsToSeconds(clip.LengthBeats, tempo) + 0.5; // release tail
        var playableNotes = ApplyRecordedSustain(clip);
        foreach (var n in playableNotes)
            clipSeconds = Math.Max(clipSeconds, BeatsToSeconds(n.Beat + n.Length, tempo) + 0.5);
        int frames = (int)Math.Ceiling(clipSeconds * SampleRate);
        var mono = new float[frames];

        // Pick the instrument by device kind/name. VST3 instruments render through
        // the native out-of-process host when available; stock devices stay local.
        var instrument = track.Devices.FirstOrDefault(d => d.Enabled && d.IsVst3)
            ?? track.Devices.FirstOrDefault(d => d.Enabled &&
                (d.Name.Contains("Oscillatron", StringComparison.OrdinalIgnoreCase) ||
                 d.Name.Contains("LemmingBass", StringComparison.OrdinalIgnoreCase)))
            ?? track.Devices.FirstOrDefault(d => d.Enabled);
        string kind = instrument?.Name ?? "";

        if (instrument?.IsVst3 == true)
        {
            var events = new List<Vst3MidiRenderEvent>();
            foreach (var note in playableNotes)
            {
                int start = Math.Max(0, (int)Math.Round(BeatsToSeconds(note.Beat, tempo) * SampleRate));
                int end = Math.Clamp((int)Math.Round(BeatsToSeconds(note.Beat + note.Length, tempo) * SampleRate), start + 1, Math.Max(start + 1, frames - 1));
                int velocity = Math.Clamp(note.Velocity, 1, 127);
                events.Add(new Vst3MidiRenderEvent(start, "on", 1, note.Note, velocity));
                events.Add(new Vst3MidiRenderEvent(end, "off", 1, note.Note, 0));
            }
            foreach (var ev in clip.MidiEvents)
            {
                var localBeat = ev.Beat - clip.StartBeat;
                if (localBeat < -0.0001 || localBeat > clip.LengthBeats + 0.0001) continue;
                int frame = Math.Clamp((int)Math.Round(BeatsToSeconds(Math.Max(0, localBeat), tempo) * SampleRate), 0, Math.Max(0, frames - 1));
                if (ev.Kind is MidiClipEventKind.ControlChange or MidiClipEventKind.SustainPedal)
                    events.Add(new Vst3MidiRenderEvent(frame, "cc", Math.Clamp(ev.Channel, 1, 16), 0, Math.Clamp(ev.Data2, 0, 127), Math.Clamp(ev.Data1, 0, 127)));
                else if (ev.Kind == MidiClipEventKind.PitchBend)
                    events.Add(new Vst3MidiRenderEvent(frame, "pitch", Math.Clamp(ev.Channel, 1, 16), 0, Math.Clamp(ev.Data1, 0, 16383)));
            }
            var vst = Vst3NativeHostBridge.Shared.RenderMidi(instrument, events.OrderBy(e => e.Frame).ToList(), frames, SampleRate, Channels, automation: BuildVst3Automation(track, instrument, clip.StartBeat, frames, tempo));
            if (vst is { Length: > 0 })
                return vst;
            // If native VST3 render fails, deliberately fall through to a local
            // stock synth safety render so playback/export remains audible.
        }

        foreach (var note in playableNotes)
        {
            double freq = 440.0 * Math.Pow(2.0, (note.Note - 69) / 12.0);
            int start = (int)Math.Round(BeatsToSeconds(note.Beat, tempo) * SampleRate);
            int dur = Math.Max(1, (int)Math.Round(BeatsToSeconds(note.Length, tempo) * SampleRate));
            float amp = Math.Clamp(note.Velocity / 127f, 0f, 1f);

            if (kind.Contains("Oscillatron", StringComparison.OrdinalIgnoreCase))
                VoiceOscillatron(mono, frames, start, dur, freq, amp, instrument, clip, track, note.Beat, tempo);
            else if (kind.Contains("LemmingBass", StringComparison.OrdinalIgnoreCase))
                VoiceLemmingBass(mono, frames, start, dur, freq, amp, instrument, clip, track, note.Beat, tempo);
            else
                VoiceStock(mono, frames, start, dur, freq, amp, instrument, clip, track, note.Beat, tempo);
        }

        var stereo = new float[frames * Channels];
        for (int f = 0; f < frames; f++) { stereo[f * 2] = mono[f]; stereo[f * 2 + 1] = mono[f]; }
        return stereo;
    }


    private static List<MidiNote> ApplyRecordedSustain(ProjectClip clip)
    {
        if (clip.MidiEvents.Count == 0 || !clip.MidiEvents.Any(e => e.Kind == MidiClipEventKind.SustainPedal))
            return clip.Notes.ToList();

        var sustainEvents = clip.MidiEvents
            .Where(e => e.Kind == MidiClipEventKind.SustainPedal)
            .OrderBy(e => e.Beat)
            .ToList();
        if (sustainEvents.Count == 0) return clip.Notes.ToList();

        var result = new List<MidiNote>();
        foreach (var n in clip.Notes)
        {
            double absStart = clip.StartBeat + n.Beat;
            double absEnd = absStart + n.Length;
            bool pedalDownAtEnd = false;
            double releaseBeat = absEnd;
            foreach (var ev in sustainEvents)
            {
                if (ev.Beat <= absEnd) pedalDownAtEnd = ev.Data2 >= 64;
                else if (pedalDownAtEnd && ev.Data2 < 64)
                {
                    releaseBeat = ev.Beat;
                    pedalDownAtEnd = false;
                    break;
                }
                else if (ev.Beat > absEnd && !pedalDownAtEnd) break;
            }
            if (pedalDownAtEnd) releaseBeat = Math.Max(absEnd, clip.StartBeat + clip.LengthBeats);
            result.Add(n with { Length = Math.Max(n.Length, releaseBeat - absStart) });
        }
        return result;
    }

    private static float OnePoleAlpha(double cutoffNorm, double maxHz)
    {
        double fc = 200.0 + cutoffNorm * cutoffNorm * maxHz;
        double rc = 1.0 / (2.0 * Math.PI * fc);
        double dt = 1.0 / SampleRate;
        return (float)(dt / (rc + dt));
    }

    private sealed record MidiExpressionPoint(double Beat, int Value);

    private static List<MidiExpressionPoint> PitchBendPoints(ProjectClip? clip)
    {
        if (clip == null) return new List<MidiExpressionPoint>();
        return clip.MidiEvents
            .Where(e => e.Kind == MidiClipEventKind.PitchBend)
            .OrderBy(e => e.Beat)
            .Select(e => new MidiExpressionPoint(e.Beat - clip.StartBeat, Math.Clamp(e.Data1, 0, 16383)))
            .ToList();
    }

    private static List<MidiExpressionPoint> ModWheelPoints(ProjectClip? clip)
    {
        if (clip == null) return new List<MidiExpressionPoint>();
        return clip.MidiEvents
            .Where(e => e.Kind == MidiClipEventKind.ControlChange && e.Data1 == 1)
            .OrderBy(e => e.Beat)
            .Select(e => new MidiExpressionPoint(e.Beat - clip.StartBeat, Math.Clamp(e.Data2, 0, 127)))
            .ToList();
    }

    private static void AdvanceMidiExpression(List<MidiExpressionPoint> points, double localBeat, ref int index, ref int current)
    {
        while (index < points.Count && points[index].Beat <= localBeat + 0.0000001)
        {
            current = points[index].Value;
            index++;
        }
    }

    private static double ExpressionSemitones(int bend14, int modWheel, Track? track, int frameOffset, double baseLfoHz = 5.5)
    {
        var range = Math.Clamp(track?.PitchBendRangeSemitones ?? 2, 0, 48);
        var bend = ((Math.Clamp(bend14, 0, 16383) - 8192) / 8192.0) * range;
        var modDepth = Math.Clamp(track?.ModWheelDepthSemitones ?? 0.35, 0.0, 12.0);
        var lfo = Math.Sin((frameOffset / (double)SampleRate) * Math.PI * 2.0 * baseLfoHz) * (Math.Clamp(modWheel, 0, 127) / 127.0) * modDepth;
        return bend + lfo;
    }

    /// <summary>The original stock synth: saw+square → low-pass → soft drive → AR envelope.</summary>
    private static void VoiceStock(float[] mono, int frames, int start, int dur, double freq, float vel, DeviceSlot? dev, ProjectClip? clip = null, Track? track = null, double noteBeat = 0, double tempo = 120)
    {
        double cutoff = Param(dev, "Cutoff", 0.65), drive = Param(dev, "Drive", 0.1);
        float alpha = OnePoleAlpha(cutoff, 12000.0);
        int attack = (int)(0.005 * SampleRate), release = (int)(0.08 * SampleRate);
        double phase = 0; float lp = 0f; float amp = vel * 0.22f;
        var bends = PitchBendPoints(clip); var mods = ModWheelPoints(clip);
        int bendIndex = 0, modIndex = 0, bend = 8192, mod = 0;
        for (int i = 0; i < dur + release; i++)
        {
            int dst = start + i; if (dst < 0) continue; if (dst >= frames) break;
            double localBeat = noteBeat + (i / (double)SampleRate) * Math.Max(1.0, tempo) / 60.0;
            AdvanceMidiExpression(bends, localBeat, ref bendIndex, ref bend);
            AdvanceMidiExpression(mods, localBeat, ref modIndex, ref mod);
            double semis = ExpressionSemitones(bend, mod, track, i);
            double inc = freq * Math.Pow(2.0, semis / 12.0) / SampleRate;
            phase += inc; if (phase >= 1.0) phase -= Math.Floor(phase);
            float saw = (float)(2.0 * phase - 1.0), square = phase < 0.5 ? 1f : -1f;
            float modBright = (float)(1.0 + (mod / 127.0) * 0.18);
            lp += alpha * (0.7f * saw + 0.3f * square - lp);
            float s = lp;
            if (drive > 0.001) s = (float)Math.Tanh(s * (1.0 + drive * 4.0) * modBright);
            mono[dst] += s * amp * Env(i, attack, dur, release);
        }
    }

    /// <summary>Oscillatron: three detuned saws + a sub sine, low-pass, AR envelope (rich/wide).</summary>
    private static void VoiceOscillatron(float[] mono, int frames, int start, int dur, double freq, float vel, DeviceSlot? dev, ProjectClip? clip = null, Track? track = null, double noteBeat = 0, double tempo = 120)
    {
        double cutoff = Param(dev, "Cutoff", 0.62), detune = Param(dev, "Detune", 0.35), subLevel = Param(dev, "Sub", 0.20);
        float alpha = OnePoleAlpha(cutoff, 14000.0);
        int attack = (int)(0.004 * SampleRate), release = (int)(0.18 * SampleRate);
        double cents2 = 7.0 * (0.3 + detune), cents3 = -12.0 * (0.3 + detune);
        double p1 = 0, p2 = 0, p3 = 0, pSub = 0; float lp = 0f; float amp = vel * 0.16f;
        var bends = PitchBendPoints(clip); var mods = ModWheelPoints(clip);
        int bendIndex = 0, modIndex = 0, bend = 8192, mod = 0;
        for (int i = 0; i < dur + release; i++)
        {
            int dst = start + i; if (dst < 0) continue; if (dst >= frames) break;
            double localBeat = noteBeat + (i / (double)SampleRate) * Math.Max(1.0, tempo) / 60.0;
            AdvanceMidiExpression(bends, localBeat, ref bendIndex, ref bend);
            AdvanceMidiExpression(mods, localBeat, ref modIndex, ref mod);
            double semis = ExpressionSemitones(bend, mod, track, i);
            double mult = Math.Pow(2.0, semis / 12.0);
            double i1 = freq * mult / SampleRate;
            double i2 = freq * mult * Math.Pow(2.0, cents2 / 1200.0) / SampleRate;
            double i3 = freq * mult * Math.Pow(2.0, cents3 / 1200.0) / SampleRate;
            double iSub = (freq * 0.5) * mult / SampleRate;
            p1 += i1; if (p1 >= 1) p1 -= Math.Floor(p1); p2 += i2; if (p2 >= 1) p2 -= Math.Floor(p2);
            p3 += i3; if (p3 >= 1) p3 -= Math.Floor(p3); pSub += iSub; if (pSub >= 1) pSub -= Math.Floor(pSub);
            float o1 = (float)(2 * p1 - 1), o2 = (float)(2 * p2 - 1), o3 = (float)(2 * p3 - 1);
            float sub = (float)Math.Sin(2 * Math.PI * pSub);
            float mix = 0.95f * o1 + 0.72f * o2 + 0.48f * o3 + (float)subLevel * sub;
            mix *= (float)(1.0 + (mod / 127.0) * 0.12);
            lp += alpha * (mix - lp);
            mono[dst] += lp * amp * Env(i, attack, dur, release);
        }
    }

    /// <summary>LemmingBass: sine + sub sine + click transient → drive → low-pass (deep mono bass).</summary>
    private static void VoiceLemmingBass(float[] mono, int frames, int start, int dur, double freq, float vel, DeviceSlot? dev, ProjectClip? clip = null, Track? track = null, double noteBeat = 0, double tempo = 120)
    {
        double cutoff = Param(dev, "Cutoff", 0.30), drive = Param(dev, "Drive", 0.36);
        double subLevel = Param(dev, "Sub", 0.55), punch = Param(dev, "Punch", 0.48), wave = Param(dev, "Wave", 0.35);
        float alpha = OnePoleAlpha(cutoff, 8000.0);
        int attack = (int)(0.0015 * SampleRate), release = (int)(0.075 * SampleRate);
        double phase = 0, pSub = 0; float lp = 0f; float amp = vel * 0.5f;
        int clickLen = (int)(0.006 * SampleRate);
        var bends = PitchBendPoints(clip); var mods = ModWheelPoints(clip);
        int bendIndex = 0, modIndex = 0, bend = 8192, mod = 0;
        for (int i = 0; i < dur + release; i++)
        {
            int dst = start + i; if (dst < 0) continue; if (dst >= frames) break;
            double localBeat = noteBeat + (i / (double)SampleRate) * Math.Max(1.0, tempo) / 60.0;
            AdvanceMidiExpression(bends, localBeat, ref bendIndex, ref bend);
            AdvanceMidiExpression(mods, localBeat, ref modIndex, ref mod);
            double mult = Math.Pow(2.0, ExpressionSemitones(bend, mod, track, i, 4.8) / 12.0);
            double inc = freq * mult / SampleRate, incSub = (freq * 0.5) * mult / SampleRate;
            phase += inc; if (phase >= 1) phase -= Math.Floor(phase); pSub += incSub; if (pSub >= 1) pSub -= Math.Floor(pSub);
            float sine = (float)Math.Sin(2 * Math.PI * phase);
            float square = phase < 0.5 ? 1f : -1f;
            float osc = (float)((1 - wave) * sine + wave * square);
            float sub = (float)Math.Sin(2 * Math.PI * pSub) * (float)subLevel;
            float s = osc + sub;
            if (i < clickLen) s += (float)punch * vel * (1f - i / (float)clickLen);
            s = (float)Math.Tanh(s * (1.0 + drive * 5.0) * (1.0 + (mod / 127.0) * 0.10));
            lp += alpha * (s - lp);
            mono[dst] += lp * amp * Env(i, attack, dur, release);
        }
    }

    private static float Env(int i, int attack, int dur, int release)
    {
        if (i < attack) return i / (float)Math.Max(1, attack);
        if (i < dur) return 1f;
        return Math.Max(0f, 1f - (i - dur) / (float)Math.Max(1, release));
    }

    // ----- Transport -----

    public void Play(StudioProject project)
    {
        Stop();
        float[] mix = Render(project);
        _provider = new FloatBufferSampleProvider(mix, SampleRate, Channels, (peak, rms) => UpdatePlaybackMasterMeter(peak, rms));
        _output = new WaveOutEvent { DesiredLatency = Math.Clamp(OutputLatencyMs, 30, 500) };
        _output.PlaybackStopped += OnPlaybackStopped;
        _output.Init(_provider);
        _output.Play();
        IsPlaying = true;
        Log?.Invoke($"Playback started — {mix.Length / Channels / (double)SampleRate:0.0}s rendered.");
    }

    private void UpdatePlaybackMasterMeter(float peak, float rms)
    {
        const string key = "master";
        float hold = Math.Max(peak, _meterHold.TryGetValue(key, out var old) ? old * 0.96f : 0f);
        _meterHold[key] = hold;
        if (peak >= 1f) _meterClipped.Add(key);
        LastMeters[key] = new MeterState(peak, rms, hold, _meterClipped.Contains(key));
    }

    public void Stop()
    {
        if (_output != null)
        {
            _output.PlaybackStopped -= OnPlaybackStopped;
            try { _output.Stop(); } catch { }
            _output.Dispose();
            _output = null;
        }
        _provider = null;
        IsPlaying = false;
    }

    private void OnPlaybackStopped(object? sender, StoppedEventArgs e)
    {
        IsPlaying = false;
        if (e.Exception != null) Log?.Invoke("Playback error: " + e.Exception.Message);
        PlaybackStopped?.Invoke();
    }

    /// <summary>Render the project and write it in the requested format/quality.</summary>
    public void Export(StudioProject project, string path, ExportSettings settings)
    {
        float[] mix = Render(project);
        double seconds = mix.Length / Channels / (double)SampleRate;
        switch (settings.Format)
        {
            case ExportFormat.Wav:  WriteWav(mix, path, settings.BitDepth); break;
            case ExportFormat.Aiff: WriteAiff(mix, path, settings.BitDepth); break;
            case ExportFormat.Mp3:  WriteViaFfmpeg(mix, path, settings, "mp3"); break;
            case ExportFormat.Flac: WriteViaFfmpeg(mix, path, settings, "flac"); break;
            default: WriteWav(mix, path, 16); break;
        }
        Log?.Invoke($"Exported {seconds:0.0}s → {Path.GetFileName(path)} ({settings.Describe()})");
    }

    /// <summary>Back-compat shim: 16-bit WAV.</summary>
    public void ExportWav(StudioProject project, string path)
        => Export(project, path, new ExportSettings { Format = ExportFormat.Wav, BitDepth = 16 });

    private void WriteWav(float[] mix, string path, int bitDepth)
    {
        var p = new FloatBufferSampleProvider(mix, SampleRate, Channels);
        if (bitDepth == 16)
            WaveFileWriter.CreateWaveFile16(path, p);
        else if (bitDepth == 24)
            WaveFileWriter.CreateWaveFile(path, new SampleToWaveProvider24(p));
        else // 32-bit IEEE float
            WaveFileWriter.CreateWaveFile(path, new SampleToWaveProvider(p));
    }

    private static void WriteAiff(float[] mix, string path, int bitDepth)
    {
        var p = new FloatBufferSampleProvider(mix, SampleRate, Channels);
        // AIFF is PCM big-endian; cap at 24-bit (32-bit float AIFF isn't widely supported).
        IWaveProvider wp = bitDepth >= 24 ? new SampleToWaveProvider24(p) : new SampleToWaveProvider16(p);
        // AiffFileWriter.CreateAiffFile wants a WaveStream; the sample-providers are
        // IWaveProvider, so drive the instance writer directly and pump the buffer.
        using var writer = new AiffFileWriter(path, wp.WaveFormat);
        var buffer = new byte[wp.WaveFormat.AverageBytesPerSecond];
        int read;
        while ((read = wp.Read(buffer, 0, buffer.Length)) > 0)
            writer.Write(buffer, 0, read);
    }

    /// <summary>Render a high-quality temp WAV, then transcode with the bundled ffmpeg.</summary>
    private void WriteViaFfmpeg(float[] mix, string outPath, ExportSettings settings, string codec)
    {
        string ffmpeg = FfmpegLocator.Find()
            ?? throw new FileNotFoundException(
                "ffmpeg was not found, so MP3/FLAC export isn't available. Put ffmpeg.exe next to " +
                "LemmingsStudio.exe (or in a 'ffmpeg' subfolder), add it to PATH, or set the " +
                "LEMMINGS_FFMPEG environment variable. WAV/AIFF export needs no ffmpeg.");

        string tmp = Path.Combine(Path.GetTempPath(), "lemmings_export_" + Guid.NewGuid().ToString("N") + ".wav");
        WriteWav(mix, tmp, 32); // 32-bit float intermediate = no quality loss before encode
        try
        {
            string args = codec == "mp3"
                ? $"-y -i \"{tmp}\" -codec:a libmp3lame -b:a {settings.Mp3Bitrate}k \"{outPath}\""
                : $"-y -i \"{tmp}\" -codec:a flac -compression_level {settings.FlacCompression} \"{outPath}\"";
            RunFfmpeg(ffmpeg, args);
        }
        finally
        {
            try { File.Delete(tmp); } catch { /* best effort */ }
        }
    }

    private void RunFfmpeg(string ffmpeg, string args)
    {
        var psi = new System.Diagnostics.ProcessStartInfo
        {
            FileName = ffmpeg,
            Arguments = args,
            RedirectStandardError = true,
            RedirectStandardOutput = true,
            UseShellExecute = false,
            CreateNoWindow = true
        };
        using var proc = System.Diagnostics.Process.Start(psi)
            ?? throw new InvalidOperationException("Could not start ffmpeg.");
        string err = proc.StandardError.ReadToEnd();
        proc.WaitForExit();
        if (proc.ExitCode != 0)
            throw new InvalidOperationException("ffmpeg failed (exit " + proc.ExitCode + "):\n" + err);
    }

    public void Dispose() => Stop();
}

/// <summary>Output container/encoding choices for export.</summary>
public enum ExportFormat { Wav, Aiff, Mp3, Flac }

public sealed class ExportSettings
{
    public ExportFormat Format { get; set; } = ExportFormat.Wav;
    public int BitDepth { get; set; } = 24;        // WAV: 16/24/32(float); AIFF: 16/24
    public int Mp3Bitrate { get; set; } = 320;     // kbps (CBR)
    public int FlacCompression { get; set; } = 5;  // 0..12 (ffmpeg)

    public string Extension => Format switch
    {
        ExportFormat.Wav => ".wav",
        ExportFormat.Aiff => ".aiff",
        ExportFormat.Mp3 => ".mp3",
        ExportFormat.Flac => ".flac",
        _ => ".wav"
    };

    public string Describe() => Format switch
    {
        ExportFormat.Wav => BitDepth == 32 ? "WAV 32-bit float" : $"WAV {BitDepth}-bit PCM",
        ExportFormat.Aiff => $"AIFF {(BitDepth >= 24 ? 24 : 16)}-bit PCM",
        ExportFormat.Mp3 => $"MP3 {Mp3Bitrate} kbps",
        ExportFormat.Flac => $"FLAC (level {FlacCompression})",
        _ => "WAV"
    };
}

/// <summary>Finds an ffmpeg executable: env var → next to the app → a 'ffmpeg' subfolder → PATH.</summary>
public static class FfmpegLocator
{
    public static string? Find()
    {
        var env = Environment.GetEnvironmentVariable("LEMMINGS_FFMPEG");
        if (!string.IsNullOrWhiteSpace(env) && File.Exists(env)) return env;

        string baseDir = AppContext.BaseDirectory;
        string[] candidates =
        {
            Path.Combine(baseDir, "ffmpeg.exe"),
            Path.Combine(baseDir, "ffmpeg", "ffmpeg.exe"),
            Path.Combine(baseDir, "ffmpeg", "bin", "ffmpeg.exe"),
        };
        foreach (var c in candidates) if (File.Exists(c)) return c;

        // Fall back to PATH via `where`.
        try
        {
            var psi = new System.Diagnostics.ProcessStartInfo
            {
                FileName = "where",
                Arguments = "ffmpeg",
                RedirectStandardOutput = true,
                UseShellExecute = false,
                CreateNoWindow = true
            };
            using var p = System.Diagnostics.Process.Start(psi);
            if (p != null)
            {
                string outp = p.StandardOutput.ReadToEnd();
                p.WaitForExit(1500);
                var first = outp.Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
                                .FirstOrDefault(l => l.EndsWith("ffmpeg.exe", StringComparison.OrdinalIgnoreCase));
                if (first != null && File.Exists(first)) return first;
            }
        }
        catch { /* ignore */ }
        return null;
    }
}

/// <summary>Streams an in-memory interleaved float buffer as an ISampleProvider.</summary>
public sealed class FloatBufferSampleProvider : ISampleProvider
{
    private readonly float[] _buffer;
    private readonly Action<float, float>? _meterCallback;
    public long Position { get; set; }
    public WaveFormat WaveFormat { get; }

    public FloatBufferSampleProvider(float[] interleaved, int sampleRate, int channels, Action<float, float>? meterCallback = null)
    {
        _buffer = interleaved;
        _meterCallback = meterCallback;
        WaveFormat = WaveFormat.CreateIeeeFloatWaveFormat(sampleRate, channels);
    }

    public int Read(float[] buffer, int offset, int count)
    {
        long remaining = _buffer.Length - Position;
        if (remaining <= 0) return 0;
        int n = (int)Math.Min(count, remaining);
        Array.Copy(_buffer, Position, buffer, offset, n);
        if (_meterCallback != null && n > 0)
        {
            float peak = 0f; double sum = 0;
            for (int i = 0; i < n; i++) { float v = buffer[offset + i]; float a = Math.Abs(v); if (a > peak) peak = a; sum += v * v; }
            _meterCallback(peak, (float)Math.Sqrt(sum / n));
        }
        Position += n;
        return n;
    }
}
