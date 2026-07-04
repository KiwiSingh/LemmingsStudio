using System.Text.Json;
using LemmingsStudio.Windows;

namespace LemmingsStudio.Windows.Features;

public sealed class SoundDesign
{
    public string PresetName { get; set; } = "Patch";
    public Dictionary<string, double> Params { get; set; } = new();
    public string Notes { get; set; } = "";
}

/// <summary>
/// Windows port (in spirit) of the macOS SoundAgent: turns a text description into concrete
/// synth parameter values and applies them to an instrument DeviceSlot. The Mac version drives
/// AU/Serum targets in Hz/seconds; the Windows instruments expose normalized 0..1 controls
/// (Cutoff, Drive, Detune, Sub, Resonance, Punch, Wave), so the same descriptive vocabulary is
/// mapped into that space. Always runs the deterministic keyword heuristic as a baseline, then
/// lets the LLM override — so even offline / garbage responses still yield a musical patch.
/// </summary>
public sealed class SoundAgent
{
    private readonly OllamaClient _client;
    public SoundAgent(OllamaClient client) { _client = client; }

    public async Task<SoundDesign> DesignAsync(string description, DeviceSlot target, string model, CancellationToken token = default)
    {
        // Deterministic baseline first (this is the offline path and the safety net).
        var design = new SoundDesign
        {
            PresetName = DerivePresetName(null, description),
            Params = LocalHeuristic(description, target),
            Notes = "Heuristic patch from your description."
        };

        try
        {
            string paramList = string.Join(", ", target.Parameters.Keys);
            string system =
                $"You are a synthesis sound-designer driving the LemmingsStudio instrument \"{target.Name}\". " +
                "Translate the FULL request into concrete parameter values. Use ONLY these normalized " +
                $"0..1 control names: {paramList}. Reply with ONLY JSON: " +
                "{\"presetName\": string, \"notes\": string, \"params\": {\"<name>\": number, ...}}. " +
                "presetName should be a short patch name like \"80s Synthwave Pluck\", not the prompt text.";

            string text = await _client.GenerateAsync(model, system, description, token);
            if (TryParse(text, target, out var name, out var notes, out var modelParams))
            {
                if (!string.IsNullOrWhiteSpace(name)) design.PresetName = DerivePresetName(name, description);
                if (!string.IsNullOrWhiteSpace(notes)) design.Notes = notes!;
                foreach (var (k, v) in modelParams) design.Params[k] = v; // model overrides baseline
            }
        }
        catch { /* keep the heuristic baseline */ }

        // Apply to the device.
        foreach (var (k, v) in design.Params) target.Parameters[k] = Math.Clamp(v, 0.0, 1.0);
        return design;
    }

    // ---- LLM JSON parsing (only keys the target actually exposes, case-insensitive) ----
    private static bool TryParse(string text, DeviceSlot target, out string? name, out string? notes, out Dictionary<string, double> outParams)
    {
        name = null; notes = null; outParams = new();
        string? json = ExtractJson(text);
        if (json == null) return false;
        try
        {
            using var doc = JsonDocument.Parse(json);
            var root = doc.RootElement;
            if (root.TryGetProperty("presetName", out var n) && n.ValueKind == JsonValueKind.String) name = n.GetString();
            if (root.TryGetProperty("notes", out var no) && no.ValueKind == JsonValueKind.String) notes = no.GetString();
            if (root.TryGetProperty("params", out var p) && p.ValueKind == JsonValueKind.Object)
            {
                foreach (var prop in p.EnumerateObject())
                {
                    // match to an existing device parameter, case-insensitively
                    foreach (var key in target.Parameters.Keys)
                        if (key.Equals(prop.Name, StringComparison.OrdinalIgnoreCase))
                        {
                            double val = prop.Value.ValueKind switch
                            {
                                JsonValueKind.Number => prop.Value.GetDouble(),
                                JsonValueKind.String => double.TryParse(prop.Value.GetString(), out var d) ? d : double.NaN,
                                _ => double.NaN
                            };
                            if (!double.IsNaN(val)) outParams[key] = Math.Clamp(val, 0.0, 1.0);
                            break;
                        }
                }
            }
            return true;
        }
        catch { return false; }
    }

    private static string? ExtractJson(string text)
    {
        if (string.IsNullOrWhiteSpace(text)) return null;
        text = text.Replace("```json", "").Replace("```", "");
        int open = text.IndexOf('{'), close = text.LastIndexOf('}');
        return open >= 0 && close > open ? text.Substring(open, close - open + 1) : null;
    }

    // ---- Deterministic keyword heuristic, mapped into normalized 0..1 controls ----
    private static Dictionary<string, double> LocalHeuristic(string description, DeviceSlot target)
    {
        string p = description.ToLowerInvariant();
        bool Has(params string[] w) => Array.Exists(w, x => p.Contains(x));

        // Start from the device's current values so we only nudge what the words imply.
        var r = new Dictionary<string, double>(target.Parameters, StringComparer.OrdinalIgnoreCase);
        void Set(string key, double v) { if (r.ContainsKey(key)) r[key] = Math.Clamp(v, 0, 1); }

        // Brightness / filter
        if (Has("bright", "open", "airy", "sparkle", "buzzy")) Set("Cutoff", 0.85);
        if (Has("dark", "muffled", "dull", "lofi", "lo-fi")) Set("Cutoff", 0.25);
        if (Has("warm", "soft", "mellow", "round", "analog")) { Set("Cutoff", 0.5); Set("Drive", 0.15); }
        if (Has("clean", "pure", "sine", "flute")) { Set("Cutoff", 0.6); Set("Drive", 0.0); }

        // Sound families
        if (Has("pluck", "stab", "percussive", "pizzicato", "marimba")) { Set("Cutoff", 0.5); Set("Punch", 0.6); }
        if (Has("lead", "screaming", "solo", "hook", "melody")) { Set("Cutoff", 0.72); Set("Drive", 0.2); }
        if (Has("supersaw", "super saw", "festival", "trance", "big saw")) { Set("Detune", 0.82); Set("Cutoff", 0.75); }
        if (Has("saw", "reese") && !Has("supersaw", "super saw")) { Set("Cutoff", 0.5); Set("Detune", 0.5); }
        if (Has("bass", "sub", "low", "808", "boomy")) { Set("Cutoff", 0.28); Set("Sub", 0.72); }
        if (Has("pad", "lush", "swell", "ambient", "string", "wash")) { Set("Cutoff", 0.55); Set("Detune", 0.4); }

        // Modifiers
        if (Has("aggressive", "harsh", "distorted", "dirty", "gritty")) Set("Drive", 0.55);
        if (Has("acid", "resonant", "squelch", "talky")) { Set("Resonance", 0.8); Set("Cutoff", 0.45); }
        if (Has("detuned", "fat", "wide", "unison", "super")) Set("Detune", 0.72);
        if (Has("80s", "'80s", "synthwave", "retrowave", "retro wave")) { Set("Detune", 0.45); Set("Cutoff", 0.6); }

        // Wave morph (LemmingBass sine→square blend)
        if (Has("square", "hollow", "reedy", "aggressive", "harsh")) Set("Wave", 0.7);
        if (Has("sine", "soft", "round", "warm")) Set("Wave", 0.2);

        return r;
    }

    private static string DerivePresetName(string? proposed, string description)
    {
        if (!string.IsNullOrWhiteSpace(proposed))
        {
            var s = proposed.Trim().Trim('"');
            return s.Length > 40 ? s[..40] : s;
        }
        // Generic descriptive name from a few keywords, not the raw prompt.
        string p = description.ToLowerInvariant();
        string family = p.Contains("bass") ? "Bass"
            : p.Contains("pad") ? "Pad"
            : p.Contains("lead") ? "Lead"
            : p.Contains("pluck") ? "Pluck"
            : p.Contains("key") ? "Keys" : "Patch";
        string vibe = p.Contains("80s") || p.Contains("synthwave") ? "Synthwave "
            : p.Contains("dark") ? "Dark "
            : p.Contains("bright") ? "Bright "
            : p.Contains("warm") ? "Warm " : "";
        return $"{vibe}{family}".Trim();
    }
}
