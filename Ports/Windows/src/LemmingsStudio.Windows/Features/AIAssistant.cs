using System.Text.Json;
using LemmingsStudio.Windows;

namespace LemmingsStudio.Windows.Features;

// ---- Typed agent operations (built from LLM JSON or the deterministic fallback) ----
public abstract record AgentOp;
public sealed record SetTempoOp(double Bpm) : AgentOp;
public sealed record AddNotesOp(string Track, int Clip, List<AgentNote> Notes) : AgentOp;
public sealed record SetClipLengthOp(string Track, int Clip, double Length) : AgentOp;
public sealed record ClearClipOp(string Track, int Clip) : AgentOp;
public sealed record TransposeOp(string Track, int Clip, int Semitones) : AgentOp;
public sealed record QuantizeOp(string Track, int Clip, double Grid) : AgentOp;
public sealed record HumanizeOp(string Track, int Clip, double Amount) : AgentOp;
public sealed record AddDeviceOp(string Track, string Device) : AgentOp;
public sealed record SetParamOp(string Track, string Node, string Param, double Value) : AgentOp;
public sealed record SetAutomationOp(string Track, string Node, string Param, List<AgentPoint> Points) : AgentOp;
public sealed record SetDrumGrooveOp(string Track, string Genre) : AgentOp;
public sealed record AgentNote(int Pitch, double Start, double Length, double Vel);
public sealed record AgentPoint(double Beat, double Value);

public sealed class AssistantResult
{
    public string Text { get; init; } = "";
    public List<AgentOp> Ops { get; init; } = new();
    public List<string> Log { get; init; } = new();
}

/// <summary>
/// Windows port of the macOS AI producer: turns a natural-language request into a plan of
/// project operations via Ollama (JSON ops), with a deterministic chord/bass/melody fallback
/// when the model doesn't return clean JSON.
/// </summary>
public sealed class AIAssistant
{
    private readonly OllamaClient _client;
    public AIAssistant(OllamaClient client) { _client = client; }

    public const string SystemPrompt = """
You are the AI producer inside LemmingsStudio, a DAW. You edit the project by emitting a plan
of operations. Reply with ONLY JSON, no prose:
{"summary": string, "ops": [ <op>, ... ]}

Supported ops (time unit is beats; pitch is a MIDI number; vel is 0..1):
- {"op":"add_notes","track":"<name>","clip":0,"notes":[{"pitch":48,"start":0,"length":0.5,"vel":0.9}]}
- {"op":"set_clip_length","track":"<name>","clip":0,"length":16}
- {"op":"clear_clip","track":"<name>","clip":0}
- {"op":"transpose","track":"<name>","clip":0,"semitones":-12}
- {"op":"quantize","track":"<name>","clip":0,"grid":0.25}
- {"op":"humanize","track":"<name>","clip":0,"amount":0.02}
- {"op":"add_device","track":"<name>","device":"Reverb|Delay|Auto Filter|EQ Three|Compressor|Utility|Saturator|Bit Crusher"}
- {"op":"set_param","track":"<name>","node":"instrument|<deviceIndex>","param":"Cutoff","value":0.4}
- {"op":"set_automation","track":"<name>","node":"instrument","param":"Cutoff","points":[{"beat":0,"value":0.2},{"beat":8,"value":0.9}]}
- {"op":"set_drum_groove","track":"<name>","genre":"Lo-Fi|Tech House|Slap House|EDM|Breakbeat"}
- {"op":"set_tempo","bpm":126}

Make tasteful, musical choices and keep notes in sensible ranges. For requests like
"create 4 bars of bass chords on the Bassline track", emit concrete MIDI note arrays and use
set_clip_length + clear_clip + add_notes. Resolve track names from PROJECT STATE.
""";

    public async Task<AssistantResult> RunAsync(string prompt, StudioProject project, string model, CancellationToken token = default)
    {
        string user = "PROJECT STATE:\n" + ProjectSummary(project) + "\n\nREQUEST:\n" + prompt;
        string text;
        try { text = await _client.GenerateAsync(model, SystemPrompt, user, token); }
        catch (Exception ex) { return new AssistantResult { Text = "AI request failed: " + ex.Message }; }

        if (TryParsePlan(text, out var summary, out var ops) && ops.Count > 0)
            return new AssistantResult { Text = summary, Ops = ops };

        var fallback = NaturalLanguageFallback(prompt, project, text);
        if (fallback != null) return fallback;

        return new AssistantResult { Text = string.IsNullOrWhiteSpace(text) ? "Couldn't parse the assistant's plan." : text };
    }

    // ---- JSON plan parsing ----
    private static bool TryParsePlan(string text, out string summary, out List<AgentOp> ops)
    {
        summary = "Done."; ops = new();
        string? json = ExtractJson(text);
        if (json == null) return false;
        try
        {
            using var doc = JsonDocument.Parse(json);
            var root = doc.RootElement;
            if (root.TryGetProperty("summary", out var s) && s.ValueKind == JsonValueKind.String)
                summary = s.GetString() ?? "Done.";
            if (!root.TryGetProperty("ops", out var opsEl) || opsEl.ValueKind != JsonValueKind.Array)
                return false;
            foreach (var op in opsEl.EnumerateArray())
            {
                var parsed = ParseOp(op);
                if (parsed != null) ops.Add(parsed);
            }
            return true;
        }
        catch { return false; }
    }

    private static AgentOp? ParseOp(JsonElement op)
    {
        if (op.ValueKind != JsonValueKind.Object || !op.TryGetProperty("op", out var kindEl)) return null;
        string kind = kindEl.GetString() ?? "";
        string track = Str(op, "track");
        int clip = (int)Num(op, "clip", 0);
        switch (kind)
        {
            case "set_tempo": return new SetTempoOp(Num(op, "bpm", 120));
            case "set_clip_length": return new SetClipLengthOp(track, clip, Num(op, "length", 4));
            case "clear_clip": return new ClearClipOp(track, clip);
            case "transpose": return new TransposeOp(track, clip, (int)Num(op, "semitones", 0));
            case "quantize": return new QuantizeOp(track, clip, Num(op, "grid", 0.25));
            case "humanize": return new HumanizeOp(track, clip, Num(op, "amount", 0.02));
            case "add_device": return new AddDeviceOp(track, Str(op, "device"));
            case "set_param": return new SetParamOp(track, Str(op, "node", "instrument"), Str(op, "param"), Num(op, "value", 0));
            case "set_drum_groove": return new SetDrumGrooveOp(track, Str(op, "genre"));
            case "set_automation":
                var points = new List<AgentPoint>();
                if (op.TryGetProperty("points", out var pts) && pts.ValueKind == JsonValueKind.Array)
                    foreach (var p in pts.EnumerateArray())
                        points.Add(new AgentPoint(Num(p, "beat", 0), Num(p, "value", 0)));
                return new SetAutomationOp(track, Str(op, "node", "instrument"), Str(op, "param", "Cutoff"), points);
            case "add_notes":
                var notes = new List<AgentNote>();
                if (op.TryGetProperty("notes", out var arr) && arr.ValueKind == JsonValueKind.Array)
                    foreach (var n in arr.EnumerateArray())
                        notes.Add(new AgentNote((int)Num(n, "pitch", 60), Num(n, "start", 0), Num(n, "length", 0.5), Num(n, "vel", 0.9)));
                return new AddNotesOp(track, clip, notes);
            default: return null;
        }
    }

    private static string? ExtractJson(string text)
    {
        if (string.IsNullOrWhiteSpace(text)) return null;
        text = text.Replace("```json", "").Replace("```", "");
        int open = text.IndexOf('{'), close = text.LastIndexOf('}');
        return (open >= 0 && close > open) ? text.Substring(open, close - open + 1) : null;
    }

    private static double Num(JsonElement o, string key, double dflt)
    {
        if (!o.TryGetProperty(key, out var v)) return dflt;
        return v.ValueKind switch
        {
            JsonValueKind.Number => v.GetDouble(),
            JsonValueKind.String => double.TryParse(v.GetString(), out var d) ? d : dflt,
            _ => dflt
        };
    }

    private static string Str(JsonElement o, string key, string dflt = "")
        => o.TryGetProperty(key, out var v) && v.ValueKind == JsonValueKind.String ? v.GetString() ?? dflt : dflt;

    // ---- Deterministic fallback (chords / bass / melody) ----
    private const int BeatsPerBar = 4;

    private static AssistantResult? NaturalLanguageFallback(string prompt, StudioProject project, string modelText)
    {
        string source = (prompt + "\n" + modelText).ToLowerInvariant();
        bool wantsNotes = source.Contains("bar") || source.Contains("chord") || source.Contains("notes")
            || source.Contains("bassline") || source.Contains("melody") || source.Contains("riff") || source.Contains("progression");
        if (!wantsNotes) return null;

        string trackName = ResolveRequestedTrackName(prompt, project);
        int bars = Math.Max(1, Math.Min(32, ParseBarCount(prompt) ?? ParseBarCount(modelText) ?? 4));
        double beatLength = bars * BeatsPerBar;
        bool wantsBass = source.Contains("bass") || trackName.ToLowerInvariant().Contains("bass");
        bool wantsChords = source.Contains("chord") || source.Contains("progression");

        var key = KeyInfo.Parse(project.Key);
        List<AgentNote> notes;
        string kind;
        bool parsedFromProse = false;
        var parsed = ParseExplicitMidiNotes(prompt + "\n" + modelText);
        if (parsed.Count > 0) { notes = parsed; kind = wantsBass ? "bassline" : "MIDI phrase"; parsedFromProse = true; }
        else if (wantsChords) { notes = GenerateChordNotes(bars, key, wantsBass); kind = wantsBass ? "bass chords" : "chords"; }
        else if (wantsBass) { notes = GenerateBassLineNotes(bars, key); kind = "bassline"; }
        else { notes = GenerateSimpleMelodyNotes(bars, key); kind = "MIDI phrase"; }
        if (notes.Count == 0) return null;

        // If we parsed explicit notes, size the clip to fit them.
        if (parsedFromProse)
        {
            double maxBeat = 0;
            foreach (var n in notes) maxBeat = Math.Max(maxBeat, n.Start + n.Length);
            beatLength = Math.Max(beatLength, Math.Ceiling(maxBeat));
        }

        var ops = new List<AgentOp>
        {
            new SetClipLengthOp(trackName, 0, beatLength),
            new ClearClipOp(trackName, 0),
            new AddNotesOp(trackName, 0, notes)
        };
        string sourceLabel = parsedFromProse
            ? "parsed from the model's note grid/prose"
            : "deterministic fallback — the model didn't return JSON ops";
        return new AssistantResult
        {
            Text = $"Created {bars} bars of {kind} on {trackName} ({sourceLabel}).",
            Ops = ops,
            Log = { parsedFromProse
                ? "Parsed explicit note names from the model's prose/grid and converted them to MIDI."
                : "Used the built-in note generator because the model did not return parseable JSON ops." }
        };
    }

    private static List<AgentNote> GenerateChordNotes(int bars, KeyInfo key, bool bassVoicing)
    {
        int[] progression = key.IsMinor ? new[] { 0, 8, 3, 10 } : new[] { 0, 7, 9, 5 };
        var notes = new List<AgentNote>();
        for (int bar = 0; bar < bars; bar++)
        {
            int off = progression[bar % progression.Length];
            int rootPC = (key.Root + off + 120) % 12;
            int root = NearestMidi(rootPC, bassVoicing ? 36 : 48, bassVoicing ? 47 : 60);
            double start = bar * BeatsPerBar;
            double len = Math.Max(0.5, BeatsPerBar - 0.125);
            int third = ChordThird(off, key);
            int[] chord = bassVoicing
                ? new[] { root, root + 7, root + 12, root + third + 12 }
                : new[] { root, root + third, root + 7, root + 12 };
            for (int i = 0; i < chord.Length; i++)
                notes.Add(new AgentNote(Math.Clamp(chord[i], 0, 127), start, len, i == 0 ? 0.92 : 0.78));
        }
        return notes;
    }

    private static List<AgentNote> GenerateBassLineNotes(int bars, KeyInfo key)
    {
        int[] progression = key.IsMinor ? new[] { 0, 8, 3, 10 } : new[] { 0, 7, 9, 5 };
        var notes = new List<AgentNote>();
        for (int bar = 0; bar < bars; bar++)
        {
            int rootPC = (key.Root + progression[bar % progression.Length] + 120) % 12;
            int root = NearestMidi(rootPC, 36, 47);
            double barStart = bar * BeatsPerBar;
            for (int step = 0; step < 4; step++)
                notes.Add(new AgentNote(step == 3 ? root + 7 : root, barStart + step, 0.75, step == 0 ? 0.95 : 0.82));
        }
        return notes;
    }

    private static List<AgentNote> GenerateSimpleMelodyNotes(int bars, KeyInfo key)
    {
        int[] scale = key.Intervals;
        int[] pattern = { 0, 2, 4, 2, 5, 4, 2, 1 };
        int totalSteps = bars * BeatsPerBar * 2;
        var notes = new List<AgentNote>();
        for (int i = 0; i < totalSteps; i++)
        {
            int pc = (key.Root + scale[pattern[i % pattern.Length] % scale.Length]) % 12;
            int pitch = NearestMidi(pc, 60, 76);
            notes.Add(new AgentNote(pitch, i * 0.5, 0.45, 0.78));
        }
        return notes;
    }

    private static int NearestMidi(int pc, int low, int high)
    {
        int normalized = ((pc % 12) + 12) % 12;
        for (int n = low; n <= high; n++)
            if ((((n % 12) + 12) % 12) == normalized) return n;
        return Math.Clamp(low + (((normalized - low) % 12 + 12) % 12), 0, 127);
    }

    private static int ChordThird(int offset, KeyInfo key)
    {
        var set = new HashSet<int>(key.Intervals);
        int majorThird = (((offset + 4) % 12) + 12) % 12;
        int minorThird = (((offset + 3) % 12) + 12) % 12;
        if (set.Contains(majorThird)) return 4;
        if (set.Contains(minorThird)) return 3;
        return key.IsMinor ? 3 : 4;
    }

    private static string ResolveRequestedTrackName(string prompt, StudioProject project)
    {
        foreach (var t in project.Tracks)
            if (prompt.Contains(t.Name, StringComparison.OrdinalIgnoreCase)) return t.Name;
        return project.Tracks.Count > 0 ? project.Tracks[0].Name : "Track 1";
    }

    private static int? ParseBarCount(string text)
    {
        var m = System.Text.RegularExpressions.Regex.Match(text.ToLowerInvariant(), @"(\d+)\s*bar");
        return m.Success && int.TryParse(m.Groups[1].Value, out var n) ? n : (int?)null;
    }

    // ---- Prose / grid note parser (e.g. "Bar 1: C2 - - - | E2 - G2 -") ----
    private static readonly System.Text.RegularExpressions.Regex BarNumRe =
        new(@"\bbar\s*(\d+)\b", System.Text.RegularExpressions.RegexOptions.IgnoreCase);
    private static readonly System.Text.RegularExpressions.Regex BarLabelRe =
        new(@"\bbar\s*\d+\b", System.Text.RegularExpressions.RegexOptions.IgnoreCase);
    private static readonly System.Text.RegularExpressions.Regex PitchRe =
        new(@"^([A-Ga-g])([#b]?)(-?\d{1,2})$");

    private static List<AgentNote> ParseExplicitMidiNotes(string text)
    {
        var lines = text.Replace("\r", "\n").Split('\n');
        var parsedBars = new List<(int bar, List<string> cells)>();
        foreach (var raw in lines)
        {
            string line = raw.Trim();
            if (line.Length == 0) continue;
            var bm = BarNumRe.Match(line);
            if (!bm.Success || !int.TryParse(bm.Groups[1].Value, out int barNumber)) continue;
            var cells = ExtractGridCells(line);
            if (cells.Exists(IsNoteToken) && !parsedBars.Exists(b => b.bar == barNumber))
                parsedBars.Add((barNumber, cells));
        }
        if (parsedBars.Count == 0) return new List<AgentNote>();
        parsedBars.Sort((a, b) => a.bar.CompareTo(b.bar));

        var notes = new List<AgentNote>();
        foreach (var (bar, cells) in parsedBars)
        {
            int barIndex = Math.Max(0, bar - 1);
            double step = (double)BeatsPerBar / Math.Max(1, cells.Count);
            double barStart = barIndex * BeatsPerBar;
            int? activePitch = null; double activeStart = 0; double activeVel = 0.78;

            void CloseActive(double beat)
            {
                if (activePitch is int p)
                {
                    double length = Math.Max(step, beat - activeStart);
                    notes.Add(new AgentNote(Math.Clamp(p, 0, 127), activeStart, length, activeVel));
                    activePitch = null;
                }
            }

            for (int ci = 0; ci < cells.Count; ci++)
            {
                double beat = barStart + ci * step;
                string token = CleanToken(cells[ci]);
                int? pitch = MidiPitch(token);
                if (pitch != null)
                {
                    CloseActive(beat);
                    activePitch = pitch; activeStart = beat;
                    activeVel = (ci % Math.Max(1, cells.Count)) == 0 ? 0.92 : (ci % 4 == 0 ? 0.84 : 0.74);
                }
                else if (IsHardRestToken(token)) CloseActive(beat);
                // otherwise a hold ("-"): extend the active note (do nothing)
            }
            CloseActive(barStart + BeatsPerBar);
        }
        notes.Sort((a, b) => a.Start == b.Start ? a.Pitch.CompareTo(b.Pitch) : a.Start.CompareTo(b.Start));
        return notes;
    }

    private static List<string> ExtractGridCells(string line)
    {
        string working = line.Replace("**", "").Replace("`", "")
            .Replace("—", "-").Replace("–", "-").Replace("♯", "#").Replace("♭", "b");
        var cells = new List<string>();
        if (working.Contains('|'))
        {
            foreach (var chunk in working.Split('|'))
                cells.AddRange(TokenizeFragment(BarLabelRe.Replace(chunk, " ")));
        }
        else
        {
            int colon = working.IndexOf(':');
            working = colon >= 0 ? working[(colon + 1)..] : BarLabelRe.Replace(working, " ");
            cells.AddRange(TokenizeFragment(working));
        }
        return cells.FindAll(c => IsNoteToken(c) || IsHoldToken(c) || IsHardRestToken(c));
    }

    private static List<string> TokenizeFragment(string text)
    {
        foreach (var ch in new[] { ',', ';', '[', ']', '(', ')' }) text = text.Replace(ch, ' ');
        var outp = new List<string>();
        foreach (var t in text.Split(new[] { ' ', '\t', '\n' }, StringSplitOptions.RemoveEmptyEntries))
        {
            string c = CleanToken(t);
            if (c.Length > 0) outp.Add(c);
        }
        return outp;
    }

    private static string CleanToken(string t)
    {
        t = t.Replace("♯", "#").Replace("♭", "b").Replace("–", "-").Replace("—", "-");
        int start = 0, end = t.Length;
        while (start < end && !Keep(t[start])) start++;
        while (end > start && !Keep(t[end - 1])) end--;
        return t.Substring(start, end - start).Trim();
        static bool Keep(char c) => char.IsLetterOrDigit(c) || c == '#' || c == 'b' || c == '-';
    }

    private static bool IsNoteToken(string t) => MidiPitch(CleanToken(t)) != null;
    private static bool IsHoldToken(string t) { var c = CleanToken(t).ToLowerInvariant(); return c is "-" or "_" or "~" or ""; }
    private static bool IsHardRestToken(string t) { var c = CleanToken(t).ToLowerInvariant(); return c is "r" or "rest" or "silence" or "0"; }

    private static int? MidiPitch(string token)
    {
        var m = PitchRe.Match(CleanToken(token));
        if (!m.Success || !int.TryParse(m.Groups[3].Value, out int octave)) return null;
        var bases = new Dictionary<string, int> { ["C"] = 0, ["D"] = 2, ["E"] = 4, ["F"] = 5, ["G"] = 7, ["A"] = 9, ["B"] = 11 };
        int semitone = bases[m.Groups[1].Value.ToUpperInvariant()];
        if (m.Groups[2].Value == "#") semitone += 1;
        if (m.Groups[2].Value == "b") semitone -= 1;
        return Math.Clamp((octave + 1) * 12 + (((semitone % 12) + 12) % 12), 0, 127);
    }

    private static string ProjectSummary(StudioProject p)
    {
        var lines = new List<string> { $"Tempo: {p.Tempo:0} BPM, Key: {p.Key}" };
        for (int i = 0; i < p.Tracks.Count; i++)
        {
            var t = p.Tracks[i];
            string devs = t.Devices.Count > 0 ? string.Join(", ", t.Devices.ConvertAll(d => d.Name)) : "no devices";
            lines.Add($"  Track \"{t.Name}\" — {t.Clips.Count} clip(s), devices: {devs}");
        }
        return string.Join("\n", lines);
    }
}

/// <summary>Parses a key string like "C minor" / "A# major" into root pitch-class + scale.</summary>
public readonly struct KeyInfo
{
    public int Root { get; }
    public bool IsMinor { get; }
    public int[] Intervals { get; }

    private KeyInfo(int root, bool isMinor)
    {
        Root = root; IsMinor = isMinor;
        Intervals = isMinor ? new[] { 0, 2, 3, 5, 7, 8, 10 } : new[] { 0, 2, 4, 5, 7, 9, 11 };
    }

    public static KeyInfo Parse(string? key)
    {
        if (string.IsNullOrWhiteSpace(key)) return new KeyInfo(0, true);
        key = key.Trim();
        int root = 0;
        var names = new (string n, int pc)[]
        {
            ("C#", 1), ("Db", 1), ("D#", 3), ("Eb", 3), ("F#", 6), ("Gb", 6),
            ("G#", 8), ("Ab", 8), ("A#", 10), ("Bb", 10),
            ("C", 0), ("D", 2), ("E", 4), ("F", 5), ("G", 7), ("A", 9), ("B", 11)
        };
        foreach (var (n, pc) in names)
            if (key.StartsWith(n, StringComparison.OrdinalIgnoreCase)) { root = pc; break; }
        bool isMinor = key.ToLowerInvariant().Contains("min");
        return new KeyInfo(root, isMinor);
    }
}

/// <summary>Applies a plan of <see cref="AgentOp"/> to the project model. Returns a human log.</summary>
public static class AssistantExecutor
{
    public static List<string> Apply(IEnumerable<AgentOp> ops, StudioProject project)
    {
        var log = new List<string>();
        foreach (var op in ops)
        {
            switch (op)
            {
                case SetTempoOp t:
                    project.Tempo = t.Bpm; log.Add($"Tempo → {t.Bpm:0}"); break;

                case AddNotesOp a:
                {
                    var (track, clip) = ResolveClip(project, a.Track, a.Clip, create: true);
                    if (clip == null) { log.Add($"add_notes: track \"{a.Track}\" not found"); break; }
                    double farthest = 0;
                    foreach (var n in a.Notes)
                    {
                        int vel = Math.Clamp((int)Math.Round(n.Vel * 127), 1, 127);
                        clip.Notes.Add(new MidiNote(n.Start, n.Length, Math.Clamp(n.Pitch, 0, 127), vel));
                        farthest = Math.Max(farthest, n.Start + n.Length);
                    }
                    if (farthest > clip.LengthBeats) clip.LengthBeats = Math.Ceiling(farthest);
                    log.Add($"Added {a.Notes.Count} notes to {track!.Name}");
                    break;
                }

                case ClearClipOp c:
                {
                    var (_, clip) = ResolveClip(project, c.Track, c.Clip, create: false);
                    if (clip != null) { clip.Notes.Clear(); log.Add("Cleared clip"); }
                    break;
                }

                case SetClipLengthOp s:
                {
                    var (_, clip) = ResolveClip(project, s.Track, s.Clip, create: true);
                    if (clip != null) { clip.LengthBeats = Math.Max(0.25, s.Length); log.Add($"Clip length → {clip.LengthBeats:0.0} beats"); }
                    break;
                }

                case TransposeOp tr:
                {
                    var (_, clip) = ResolveClip(project, tr.Track, tr.Clip, create: false);
                    if (clip != null)
                    {
                        clip.Notes = clip.Notes.ConvertAll(n => n with { Note = Math.Clamp(n.Note + tr.Semitones, 0, 127) });
                        log.Add($"Transposed {tr.Semitones} st");
                    }
                    break;
                }

                case QuantizeOp q:
                {
                    var (_, clip) = ResolveClip(project, q.Track, q.Clip, create: false);
                    if (clip != null)
                    {
                        double g = q.Grid <= 0 ? 0.25 : q.Grid;
                        clip.Notes = clip.Notes.ConvertAll(n => n with { Beat = Math.Round(n.Beat / g) * g });
                        log.Add($"Quantized to {g}");
                    }
                    break;
                }

                case HumanizeOp h:
                {
                    var (_, clip) = ResolveClip(project, h.Track, h.Clip, create: false);
                    if (clip != null)
                    {
                        var rng = Random.Shared;
                        clip.Notes = clip.Notes.ConvertAll(n => n with
                        {
                            Beat = Math.Max(0, n.Beat + (rng.NextDouble() * 2 - 1) * h.Amount),
                            Velocity = Math.Clamp(n.Velocity + (int)Math.Round((rng.NextDouble() * 2 - 1) * 12), 1, 127)
                        });
                        log.Add("Humanized " + h.Track);
                    }
                    break;
                }

                case AddDeviceOp d:
                {
                    var track = FindTrack(project, d.Track);
                    if (track == null) { log.Add($"add_device: track \"{d.Track}\" not found"); break; }
                    track.Devices.Add(BuildDevice(d.Device));
                    log.Add($"Added {d.Device} to {track.Name}");
                    break;
                }

                case SetParamOp p:
                {
                    var track = FindTrack(project, p.Track);
                    if (track == null) { log.Add($"set_param: track \"{p.Track}\" not found"); break; }
                    DeviceSlot? dev = int.TryParse(p.Node, out var idx) && idx >= 0 && idx < track.Devices.Count
                        ? track.Devices[idx]
                        : track.Devices.Count > 0 ? track.Devices[0] : null;
                    if (dev != null) { dev.Parameters[p.Param] = p.Value; log.Add($"{track.Name}.{p.Param} = {p.Value:0.##}"); }
                    break;
                }

                case SetAutomationOp sa:
                {
                    var track = FindTrack(project, sa.Track);
                    if (track == null) { log.Add($"set_automation: track \"{sa.Track}\" not found"); break; }
                    DeviceSlot? dev = int.TryParse(sa.Node, out var ni) && ni >= 0 && ni < track.Devices.Count
                        ? track.Devices[ni]
                        : track.Devices.Count > 0 ? track.Devices[0] : null;
                    string? deviceId = dev?.Id.ToString();
                    var lane = track.Automation.Find(l => l.Kind == AutomationTargetKind.DeviceParameter
                        && l.DeviceId == deviceId
                        && string.Equals(l.ParameterId, sa.Param, StringComparison.OrdinalIgnoreCase));
                    if (lane == null)
                    {
                        lane = new AutomationLane
                        {
                            Name = $"{dev?.Name ?? "Device"} {sa.Param}",
                            Kind = AutomationTargetKind.DeviceParameter,
                            DeviceId = deviceId,
                            ParameterId = sa.Param,
                            Minimum = 0,
                            Maximum = 1
                        };
                        track.Automation.Add(lane);
                    }
                    lane.Points = sa.Points.ConvertAll(pt => new AutomationPoint(pt.Beat, pt.Value));
                    log.Add($"Automation: {track.Name}.{sa.Param} ({lane.Points.Count} pts)");
                    break;
                }

                case SetDrumGrooveOp dg:
                {
                    var (track, clip) = ResolveClip(project, dg.Track, 0, create: true);
                    if (clip == null) { log.Add($"set_drum_groove: track \"{dg.Track}\" not found"); break; }
                    var groove = DrumGroove.For(dg.Genre);
                    if (groove == null) { log.Add($"Unknown groove \"{dg.Genre}\""); break; }
                    clip.Notes.Clear();
                    clip.LengthBeats = 4;
                    foreach (var (note, steps) in groove)
                        for (int s = 0; s < steps.Length; s++)
                            if (steps[s] == 1)
                                clip.Notes.Add(new MidiNote(s * 0.25, 0.25, note, DrumGroove.VelocityFor(note)));
                    log.Add($"{track!.Name} groove → {dg.Genre} ({clip.Notes.Count} hits)");
                    break;
                }
            }
        }
        return log;
    }

    private static Track? FindTrack(StudioProject p, string name)
        => p.Tracks.Find(t => t.Name.Equals(name, StringComparison.OrdinalIgnoreCase))
           ?? p.Tracks.Find(t => t.Name.Contains(name, StringComparison.OrdinalIgnoreCase));

    private static (Track? track, ProjectClip? clip) ResolveClip(StudioProject p, string trackName, int index, bool create)
    {
        var track = FindTrack(p, trackName);
        if (track == null) return (null, null);
        if (index < 0) index = 0;
        while (create && track.Clips.Count <= index)
            track.Clips.Add(new ProjectClip { Type = ClipType.Midi, Name = $"Clip {track.Clips.Count + 1}", StartBeat = 0 });
        var clip = index < track.Clips.Count ? track.Clips[index] : null;
        return (track, clip);
    }

    private static DeviceSlot BuildDevice(string name)
    {
        // Normalise a couple of Mac aliases to the Windows catalog.
        if (name.Equals("EQ Eight", StringComparison.OrdinalIgnoreCase)) name = "EQ Three";
        Dictionary<string, double> defaults = name switch
        {
            "Auto Filter" => new() { ["Cutoff"] = 0.65, ["Resonance"] = 0.25, ["Drive"] = 0.10 },
            "Saturator" => new() { ["Drive"] = 0.35, ["Wet"] = 0.80 },
            "Bit Crusher" => new() { ["Bits"] = 0.40, ["Downsample"] = 0.30, ["Wet"] = 1.00 },
            "EQ Three" => new() { ["Low"] = 0.50, ["Mid"] = 0.50, ["High"] = 0.50, ["Gain"] = 0.50 },
            "Compressor" => new() { ["Threshold"] = 0.50, ["Ratio"] = 0.40, ["Attack"] = 0.20, ["Release"] = 0.40, ["Makeup"] = 0.30 },
            "Reverb" => new() { ["Size"] = 0.50, ["Decay"] = 0.50, ["Wet"] = 0.30 },
            "Delay" => new() { ["Time"] = 0.35, ["Feedback"] = 0.30, ["Wet"] = 0.30 },
            "Utility" => new() { ["Gain"] = 0.50, ["Width"] = 0.50, ["Pan"] = 0.50 },
            _ => new Dictionary<string, double>()
        };
        return new DeviceSlot { Name = name, Enabled = true, Parameters = defaults };
    }
}

/// <summary>16-step drum grooves ported from the Mac build, voiced to GM drum MIDI notes.</summary>
public static class DrumGroove
{
    private const int Kick = 36, Sub808 = 35, Snare = 38, Clap = 39, ClosedHat = 42, OpenHat = 46, Crash = 49;

    public static int VelocityFor(int note) => note switch
    {
        Kick or Snare or Sub808 => 112,
        Clap => 100,
        ClosedHat or OpenHat => 80,
        _ => 92
    };

    public static List<(int note, int[] steps)>? For(string genre)
    {
        switch (genre.Trim().ToLowerInvariant())
        {
            case "lo-fi":
            case "lofi":
                return new()
                {
                    (Kick,      new[] {1,0,0,0, 0,0,1,0, 0,0,1,0, 0,0,0,0}),
                    (Snare,     new[] {0,0,0,0, 1,0,0,0, 0,0,0,0, 1,0,0,1}),
                    (ClosedHat, new[] {1,0,1,1, 1,0,1,0, 1,0,1,1, 1,0,1,0}),
                };
            case "tech house":
                return new()
                {
                    (Kick,      new[] {1,0,0,0, 1,0,0,0, 1,0,0,0, 1,0,0,0}),
                    (Clap,      new[] {0,0,0,0, 1,0,0,0, 0,0,0,0, 1,0,0,0}),
                    (ClosedHat, new[] {0,0,1,0, 0,0,1,0, 0,0,1,0, 0,0,1,0}),
                    (OpenHat,   new[] {0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,1,0}),
                };
            case "slap house":
                return new()
                {
                    (Kick,      new[] {1,0,0,0, 1,0,0,0, 1,0,0,0, 1,0,0,0}),
                    (Sub808,    new[] {1,0,0,0, 0,0,1,0, 1,0,0,0, 0,0,1,0}),
                    (Clap,      new[] {0,0,0,0, 1,0,0,0, 0,0,0,0, 1,0,0,0}),
                    (OpenHat,   new[] {0,0,1,0, 0,0,1,0, 0,0,1,0, 0,0,1,0}),
                };
            case "edm":
                return new()
                {
                    (Kick,      new[] {1,0,0,0, 1,0,0,0, 1,0,0,0, 1,0,0,0}),
                    (Snare,     new[] {0,0,0,0, 1,0,0,0, 0,0,0,0, 1,0,0,0}),
                    (ClosedHat, new[] {1,1,1,1, 1,1,1,1, 1,1,1,1, 1,1,1,1}),
                    (Crash,     new[] {1,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0}),
                };
            case "breakbeat":
                return new()
                {
                    (Kick,      new[] {1,0,0,0, 0,0,1,0, 0,0,1,0, 0,0,0,0}),
                    (Snare,     new[] {0,0,0,0, 1,0,0,1, 0,1,0,0, 1,0,0,0}),
                    (ClosedHat, new[] {1,0,1,0, 1,0,1,0, 1,0,1,0, 1,0,1,1}),
                };
            default:
                return null;
        }
    }
}
