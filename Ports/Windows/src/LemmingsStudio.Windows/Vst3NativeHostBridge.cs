using System.Collections.Concurrent;
using System.Diagnostics;
using System.Text.Json;

namespace LemmingsStudio.Windows;

public sealed record Vst3MidiRenderEvent(int Frame, string Type, int Channel, int Note = 0, int Velocity = 0, int Controller = 0);
public sealed record Vst3AutomationEvent(int Frame, string ParameterKey, double Value);
public sealed record Vst3BusInfo(int Index, string Name, int Channels, bool Enabled, bool Main);
public sealed record Vst3ProgramInfo(int Index, string Name);
public sealed record Vst3HostInfo(int LatencySamples, int InputChannels, int OutputChannels, string Layout = "", bool SupportsEditor = false, bool HasCustomEditor = false, bool SidechainCapable = false, IReadOnlyList<Vst3BusInfo>? InputBuses = null, IReadOnlyList<Vst3BusInfo>? OutputBuses = null);

/// <summary>
/// App-side IPC bridge for the out-of-process native Windows VST3 helper.
/// JSONL commands are used for control/MIDI/editor operations. buildfix231 also
/// adds synchronous PCM requests for offline/playback rendering:
///   renderMidi   -> returns interleaved float32 PCM as base64
///   processAudio -> accepts/returns interleaved float32 PCM as base64
/// </summary>
public sealed class Vst3NativeHostBridge : IDisposable
{
    public static Vst3NativeHostBridge Shared { get; } = new();

    private readonly object gate = new();
    private readonly ConcurrentDictionary<string, TaskCompletionSource<JsonElement>> pending = new();
    private Process? process;
    private StreamWriter? stdin;
    private string? lastError;
    private readonly HashSet<Guid> hydratedSlots = new();

    public event Action<string>? Log;

    public bool IsAvailable => File.Exists(ResolveHostPath());
    public bool IsRunning => process is { HasExited: false };
    public string HostPath => ResolveHostPath();
    public string LastError => lastError ?? "";

    public string StatusText
    {
        get
        {
            if (IsRunning) return "Native VST3 host: running";
            if (IsAvailable) return "Native VST3 host: installed, not started";
            return "Native VST3 host: helper not bundled yet";
        }
    }

    public bool EnsureStarted(IWin32Window? owner = null)
    {
        lock (gate)
        {
            if (IsRunning) return true;
            var host = ResolveHostPath();
            if (!File.Exists(host))
            {
                lastError = "LemmingsVst3Host.exe was not found beside the app. Native VST3 processing/editor embedding is unavailable in this build.";
                Log?.Invoke(lastError);
                return false;
            }
            try
            {
                process = new Process
                {
                    StartInfo = new ProcessStartInfo
                    {
                        FileName = host,
                        WorkingDirectory = AppContext.BaseDirectory,
                        UseShellExecute = false,
                        RedirectStandardInput = true,
                        RedirectStandardOutput = true,
                        RedirectStandardError = true,
                        CreateNoWindow = true
                    },
                    EnableRaisingEvents = true
                };
                process.OutputDataReceived += (_, e) => { if (!string.IsNullOrWhiteSpace(e.Data)) HandleHostLine(e.Data); };
                process.ErrorDataReceived += (_, e) => { if (!string.IsNullOrWhiteSpace(e.Data)) Log?.Invoke("VST3 host err: " + e.Data); };
                process.Exited += (_, _) =>
                {
                    Log?.Invoke("Native VST3 host exited.");
                    foreach (var kv in pending)
                        kv.Value.TrySetException(new IOException("Native VST3 host exited."));
                    pending.Clear();
                };
                process.Start();
                process.BeginOutputReadLine();
                process.BeginErrorReadLine();
                stdin = process.StandardInput;
                Send(new { op = "ping" });
                Log?.Invoke("Native VST3 host started: " + host);
                return true;
            }
            catch (Exception ex)
            {
                lastError = ex.Message;
                Log?.Invoke("Native VST3 host failed to start: " + ex.Message);
                return false;
            }
        }
    }

    public bool TryLoad(DeviceSlot slot, IWin32Window? owner = null)
    {
        var ok = LoadBare(slot, owner);
        if (ok && hydratedSlots.Add(slot.Id))
        {
            if (!string.IsNullOrWhiteSpace(slot.PluginStateBase64)) RestoreState(slot);
            if (slot.Vst3Parameters.Count == 0) RefreshParameters(slot);
            ApplyStoredParameters(slot);
            RefreshInfo(slot);
        }
        return ok;
    }

    private bool LoadBare(DeviceSlot slot, IWin32Window? owner = null)
    {
        if (!slot.IsVst3 || string.IsNullOrWhiteSpace(slot.PluginPath)) return false;
        if (!EnsureStarted(owner)) return false;
        slot.NativeHostEnabled = true;
        slot.NativeHostStatus = "Loaded/requested";
        return Send(new { op = "load", slotId = slot.Id.ToString(), path = slot.PluginPath, name = slot.Name });
    }

    public bool TryOpenEditor(DeviceSlot slot, IWin32Window? owner = null)
    {
        if (!slot.IsVst3 || string.IsNullOrWhiteSpace(slot.PluginPath)) return false;
        if (!TryLoad(slot, owner)) return false;
        var hwnd = owner is Control c ? c.Handle.ToInt64() : 0L;
        return Send(new { op = "openEditor", slotId = slot.Id.ToString(), parentHwnd = hwnd });
    }

    public bool SendNoteOn(DeviceSlot slot, int channel, int note, int velocity)
    {
        if (!slot.IsVst3 || !EnsureStarted()) return false;
        TryLoad(slot);
        return Send(new { op = "noteOn", slotId = slot.Id.ToString(), channel, note, velocity });
    }

    public bool SendNoteOff(DeviceSlot slot, int channel, int note)
    {
        if (!slot.IsVst3 || !EnsureStarted()) return false;
        return Send(new { op = "noteOff", slotId = slot.Id.ToString(), channel, note });
    }

    public bool SendControlChange(DeviceSlot slot, int channel, int controller, int value)
    {
        if (!slot.IsVst3 || !EnsureStarted()) return false;
        TryLoad(slot);
        return Send(new { op = "cc", slotId = slot.Id.ToString(), channel, controller, value });
    }

    public bool SendPitchBend(DeviceSlot slot, int channel, int value14Bit)
    {
        if (!slot.IsVst3 || !EnsureStarted()) return false;
        TryLoad(slot);
        return Send(new { op = "pitch", slotId = slot.Id.ToString(), channel, value = Math.Clamp(value14Bit, 0, 16383) });
    }

    public void Panic(DeviceSlot? slot = null)
    {
        if (!EnsureStarted()) return;
        if (slot != null) Send(new { op = "panic", slotId = slot.Id.ToString() });
        else Send(new { op = "panic" });
    }


    public Vst3HostInfo? RefreshInfo(DeviceSlot slot, int timeoutMs = 10000)
    {
        if (!slot.IsVst3 || !LoadBare(slot)) return null;
        var id = Guid.NewGuid().ToString("N");
        var response = SendRequest(new { op = "getInfo", id, slotId = slot.Id.ToString() }, id, timeoutMs);
        if (response == null) return null;
        try
        {
            var root = response.Value;
            var inputBuses = ReadBusInfos(root, "inputBuses");
            var outputBuses = ReadBusInfos(root, "outputBuses");
            var info = new Vst3HostInfo(
                root.TryGetProperty("latencySamples", out var l) ? l.GetInt32() : 0,
                root.TryGetProperty("inputChannels", out var i) ? i.GetInt32() : 0,
                root.TryGetProperty("outputChannels", out var o) ? o.GetInt32() : 2,
                root.TryGetProperty("layout", out var layout) ? layout.GetString() ?? "" : "",
                root.TryGetProperty("supportsEditor", out var ed) && ed.GetBoolean(),
                root.TryGetProperty("hasCustomEditor", out var custom) && custom.GetBoolean(),
                root.TryGetProperty("sidechainCapable", out var sc) && sc.GetBoolean(),
                inputBuses,
                outputBuses);
            slot.PluginLatencySamples = Math.Max(0, info.LatencySamples);
            slot.PluginInputChannels = Math.Max(0, info.InputChannels);
            slot.PluginOutputChannels = Math.Max(0, info.OutputChannels);
            slot.PluginBusLayout = info.Layout;
            slot.PluginSupportsEditor = info.SupportsEditor;
            slot.PluginHasCustomEditor = info.HasCustomEditor;
            if (info.SidechainCapable)
                slot.NativeHostStatus = string.IsNullOrWhiteSpace(slot.NativeHostStatus) ? "Sidechain-capable VST3 loaded" : slot.NativeHostStatus + " • sidechain-capable";
            return info;
        }
        catch (Exception ex)
        {
            lastError = ex.Message;
            Log?.Invoke("Native VST3 info decode failed: " + ex.Message);
            return null;
        }
    }

    public bool RefreshParameters(DeviceSlot slot, int timeoutMs = 15000)
    {
        if (!slot.IsVst3 || !LoadBare(slot)) return false;
        var id = Guid.NewGuid().ToString("N");
        var response = SendRequest(new { op = "getParameters", id, slotId = slot.Id.ToString() }, id, timeoutMs);
        if (response == null) return false;
        try
        {
            var root = response.Value;
            if (!root.TryGetProperty("parameters", out var arr) || arr.ValueKind != JsonValueKind.Array) return false;
            slot.Vst3Parameters.Clear();
            foreach (var item in arr.EnumerateArray())
            {
                var idx = item.TryGetProperty("index", out var ix) ? ix.GetInt32() : slot.Vst3Parameters.Count;
                var pid = item.TryGetProperty("paramId", out var idEl) ? idEl.GetString() ?? "" : "";
                var name = item.TryGetProperty("name", out var nameEl) ? nameEl.GetString() ?? $"Param {idx}" : $"Param {idx}";
                var key = string.IsNullOrWhiteSpace(pid) ? $"#{idx}" : pid;
                var normalized = item.TryGetProperty("value", out var valEl) ? valEl.GetDouble() : 0.0;
                var display = item.TryGetProperty("text", out var textEl) ? textEl.GetString() ?? "" : "";
                var automatable = !item.TryGetProperty("automatable", out var autoEl) || autoEl.GetBoolean();
                var info = new Vst3ParameterInfo { Id = key, Name = name, Index = idx, NormalizedValue = Math.Clamp(normalized, 0.0, 1.0), DisplayValue = display, Automatable = automatable };
                slot.Vst3Parameters.Add(info);
                var label = Vst3ParamKey(info);
                if (!slot.Parameters.ContainsKey(label)) slot.Parameters[label] = info.NormalizedValue;
                else slot.Parameters[label] = Math.Clamp(slot.Parameters[label], 0.0, 1.0);
            }
            RefreshInfo(slot, timeoutMs: 5000);
            return true;
        }
        catch (Exception ex)
        {
            lastError = ex.Message;
            Log?.Invoke("Native VST3 parameter decode failed: " + ex.Message);
            return false;
        }
    }

    public bool SetParameter(DeviceSlot slot, string parameterKey, double normalized, int timeoutMs = 5000)
    {
        if (!slot.IsVst3 || !LoadBare(slot)) return false;
        var id = Guid.NewGuid().ToString("N");
        var parsed = ParseVst3ParamKey(slot, parameterKey);
        var response = SendRequest(new
        {
            op = "setParameter",
            id,
            slotId = slot.Id.ToString(),
            paramId = parsed.id,
            index = parsed.index,
            value = Math.Clamp(normalized, 0.0, 1.0)
        }, id, timeoutMs);
        if (response == null) return false;
        slot.Parameters[parameterKey] = Math.Clamp(normalized, 0.0, 1.0);
        var match = slot.Vst3Parameters.FirstOrDefault(p => Vst3ParamKey(p) == parameterKey);
        if (match != null) match.NormalizedValue = Math.Clamp(normalized, 0.0, 1.0);
        SaveState(slot);
        return true;
    }

    public string? SaveState(DeviceSlot slot, int timeoutMs = 10000)
    {
        if (!slot.IsVst3 || !LoadBare(slot)) return null;
        var id = Guid.NewGuid().ToString("N");
        var response = SendRequest(new { op = "getState", id, slotId = slot.Id.ToString() }, id, timeoutMs);
        if (response == null) return null;
        try
        {
            var root = response.Value;
            if (root.TryGetProperty("state", out var stateEl))
            {
                slot.PluginStateBase64 = stateEl.GetString();
                return slot.PluginStateBase64;
            }
        }
        catch (Exception ex) { Log?.Invoke("Native VST3 state save decode failed: " + ex.Message); }
        return null;
    }

    public bool RestoreState(DeviceSlot slot, int timeoutMs = 10000)
    {
        if (!slot.IsVst3 || string.IsNullOrWhiteSpace(slot.PluginStateBase64) || !LoadBare(slot)) return false;
        var id = Guid.NewGuid().ToString("N");
        var response = SendRequest(new { op = "setState", id, slotId = slot.Id.ToString(), state = slot.PluginStateBase64 }, id, timeoutMs);
        return response != null;
    }

    public bool ApplyStoredParameters(DeviceSlot slot)
    {
        if (!slot.IsVst3 || !LoadBare(slot)) return false;
        var ok = true;
        foreach (var kv in slot.Parameters.Where(kv => kv.Key.StartsWith("VST3:", StringComparison.OrdinalIgnoreCase)).ToList())
            ok &= SetParameter(slot, kv.Key, kv.Value);
        return ok;
    }

    public static string Vst3ParamKey(Vst3ParameterInfo info) => $"VST3:{(string.IsNullOrWhiteSpace(info.Id) ? "#" + info.Index : info.Id)}:{info.Name}";

    private static (string id, int index) ParseVst3ParamKey(DeviceSlot slot, string parameterKey)
    {
        var raw = parameterKey;
        if (raw.StartsWith("VST3:", StringComparison.OrdinalIgnoreCase))
        {
            raw = raw.Substring(5);
            var colon = raw.IndexOf(':');
            if (colon >= 0) raw = raw.Substring(0, colon);
        }
        if (raw.StartsWith("#") && int.TryParse(raw.Substring(1), out var idx)) return ("", idx);
        var match = slot.Vst3Parameters.FirstOrDefault(p => string.Equals(p.Id, raw, StringComparison.Ordinal) || string.Equals(Vst3ParamKey(p), parameterKey, StringComparison.Ordinal));
        return match != null ? (match.Id.StartsWith("#") ? "" : match.Id, match.Index) : (raw, -1);
    }

    public float[]? RenderMidi(DeviceSlot slot, IReadOnlyList<Vst3MidiRenderEvent> events, int frames, int sampleRate, int channels = 2, int blockSize = 512, int timeoutMs = 60000, IReadOnlyList<Vst3AutomationEvent>? automation = null)
    {
        if (!slot.IsVst3 || frames <= 0 || !TryLoad(slot)) return null;
        var id = Guid.NewGuid().ToString("N");
        var response = SendRequest(new
        {
            op = "renderMidi",
            id,
            slotId = slot.Id.ToString(),
            sampleRate,
            channels,
            frames,
            blockSize,
            responseMode = frames * channels > 262144 ? "file" : "inline",
            events = events.Select(e => new { frame = e.Frame, type = e.Type, channel = e.Channel, note = e.Note, velocity = e.Velocity, controller = e.Controller }).ToArray(),
            automation = BuildAutomationPayload(slot, automation)
        }, id, timeoutMs);
        return DecodePcmResponse(response, frames, channels);
    }

    public float[]? ProcessAudio(DeviceSlot slot, float[] stereo, int sampleRate, int channels = 2, int blockSize = 512, int timeoutMs = 60000, IReadOnlyList<Vst3AutomationEvent>? automation = null)
    {
        if (!slot.IsVst3 || stereo.Length == 0 || !TryLoad(slot)) return null;
        var frames = stereo.Length / Math.Max(1, channels);
        var id = Guid.NewGuid().ToString("N");
        var useFile = stereo.Length > 262144;
        string? pcmFile = null;
        object request;
        if (useFile)
        {
            pcmFile = WriteTempPcmFile(stereo);
            request = new
            {
                op = "processAudio", id, slotId = slot.Id.ToString(), sampleRate, channels, frames, blockSize,
                pcmFile, responseMode = "file", automation = BuildAutomationPayload(slot, automation)
            };
        }
        else
        {
            request = new
            {
                op = "processAudio", id, slotId = slot.Id.ToString(), sampleRate, channels, frames, blockSize,
                pcm = EncodeFloatArray(stereo), responseMode = "inline", automation = BuildAutomationPayload(slot, automation)
            };
        }
        try
        {
            var response = SendRequest(request, id, timeoutMs);
            return DecodePcmResponse(response, frames, channels);
        }
        finally
        {
            if (!string.IsNullOrWhiteSpace(pcmFile)) try { File.Delete(pcmFile); } catch { }
        }
    }

    public IReadOnlyList<Vst3ProgramInfo> GetPrograms(DeviceSlot slot, int timeoutMs = 10000)
    {
        if (!slot.IsVst3 || !LoadBare(slot)) return Array.Empty<Vst3ProgramInfo>();
        var id = Guid.NewGuid().ToString("N");
        var response = SendRequest(new { op = "getPrograms", id, slotId = slot.Id.ToString() }, id, timeoutMs);
        if (response == null) return Array.Empty<Vst3ProgramInfo>();
        var list = new List<Vst3ProgramInfo>();
        if (response.Value.TryGetProperty("programs", out var arr) && arr.ValueKind == JsonValueKind.Array)
            foreach (var p in arr.EnumerateArray())
                list.Add(new Vst3ProgramInfo(p.TryGetProperty("index", out var ix) ? ix.GetInt32() : list.Count, p.TryGetProperty("name", out var nm) ? nm.GetString() ?? $"Program {list.Count + 1}" : $"Program {list.Count + 1}"));
        return list;
    }

    public bool SetProgram(DeviceSlot slot, int index, int timeoutMs = 10000)
    {
        if (!slot.IsVst3 || !LoadBare(slot)) return false;
        var id = Guid.NewGuid().ToString("N");
        var response = SendRequest(new { op = "setProgram", id, slotId = slot.Id.ToString(), index }, id, timeoutMs);
        if (response != null) slot.PluginProgramIndex = index;
        return response != null;
    }

    private static IReadOnlyList<Vst3BusInfo> ReadBusInfos(JsonElement root, string propertyName)
    {
        var list = new List<Vst3BusInfo>();
        if (root.TryGetProperty(propertyName, out var arr) && arr.ValueKind == JsonValueKind.Array)
        {
            foreach (var item in arr.EnumerateArray())
            {
                list.Add(new Vst3BusInfo(
                    item.TryGetProperty("index", out var ix) ? ix.GetInt32() : list.Count,
                    item.TryGetProperty("name", out var nm) ? nm.GetString() ?? $"Bus {list.Count + 1}" : $"Bus {list.Count + 1}",
                    item.TryGetProperty("channels", out var ch) ? ch.GetInt32() : 0,
                    !item.TryGetProperty("enabled", out var en) || en.GetBoolean(),
                    item.TryGetProperty("main", out var main) && main.GetBoolean()));
            }
        }
        return list;
    }

    private object[] BuildAutomationPayload(DeviceSlot slot, IReadOnlyList<Vst3AutomationEvent>? automation)
    {
        if (automation == null || automation.Count == 0) return Array.Empty<object>();
        return automation.Select(a =>
        {
            var parsed = ParseVst3ParamKey(slot, a.ParameterKey);
            return new { frame = Math.Max(0, a.Frame), paramId = parsed.id, index = parsed.index, value = Math.Clamp(a.Value, 0.0, 1.0) };
        }).ToArray<object>();
    }

    private static string WriteTempPcmFile(float[] data)
    {
        var path = Path.Combine(Path.GetTempPath(), "LemmingsStudioVst3_" + Guid.NewGuid().ToString("N") + ".f32");
        var bytes = new byte[data.Length * sizeof(float)];
        Buffer.BlockCopy(data, 0, bytes, 0, bytes.Length);
        File.WriteAllBytes(path, bytes);
        return path;
    }

    private JsonElement? SendRequest(object message, string id, int timeoutMs)
    {
        var tcs = new TaskCompletionSource<JsonElement>(TaskCreationOptions.RunContinuationsAsynchronously);
        pending[id] = tcs;
        if (!Send(message))
        {
            pending.TryRemove(id, out _);
            return null;
        }
        try
        {
            if (!tcs.Task.Wait(timeoutMs))
            {
                pending.TryRemove(id, out _);
                lastError = "Native VST3 host request timed out.";
                Log?.Invoke(lastError);
                return null;
            }
            return tcs.Task.Result;
        }
        catch (Exception ex)
        {
            pending.TryRemove(id, out _);
            lastError = ex.InnerException?.Message ?? ex.Message;
            Log?.Invoke("Native VST3 request failed: " + lastError);
            return null;
        }
    }

    private void HandleHostLine(string line)
    {
        try
        {
            using var doc = JsonDocument.Parse(line);
            var root = doc.RootElement.Clone();
            if (root.TryGetProperty("id", out var idEl))
            {
                var id = idEl.GetString();
                if (!string.IsNullOrWhiteSpace(id) && pending.TryRemove(id!, out var tcs))
                {
                    if (root.TryGetProperty("kind", out var kindEl) && string.Equals(kindEl.GetString(), "error", StringComparison.OrdinalIgnoreCase))
                        tcs.TrySetException(new InvalidOperationException(root.TryGetProperty("message", out var msg) ? msg.GetString() : "Native VST3 host error"));
                    else
                        tcs.TrySetResult(root);
                    return;
                }
            }
        }
        catch { }
        Log?.Invoke("VST3 host: " + line);
    }

    private static string EncodeFloatArray(float[] data)
    {
        var bytes = new byte[data.Length * sizeof(float)];
        Buffer.BlockCopy(data, 0, bytes, 0, bytes.Length);
        return Convert.ToBase64String(bytes);
    }

    private float[]? DecodePcmResponse(JsonElement? response, int requestedFrames, int requestedChannels)
    {
        if (response == null) return null;
        try
        {
            var root = response.Value;
            byte[] bytes;
            if (root.TryGetProperty("pcmFile", out var pcmFileEl))
            {
                var path = pcmFileEl.GetString() ?? "";
                if (string.IsNullOrWhiteSpace(path) || !File.Exists(path)) return null;
                bytes = File.ReadAllBytes(path);
                try { File.Delete(path); } catch { }
            }
            else
            {
                if (!root.TryGetProperty("pcm", out var pcmEl)) return null;
                bytes = Convert.FromBase64String(pcmEl.GetString() ?? "");
            }
            var floats = new float[bytes.Length / sizeof(float)];
            Buffer.BlockCopy(bytes, 0, floats, 0, floats.Length * sizeof(float));
            var frames = root.TryGetProperty("frames", out var fEl) ? fEl.GetInt32() : requestedFrames;
            var channels = root.TryGetProperty("channels", out var cEl) ? cEl.GetInt32() : requestedChannels;
            var expected = Math.Max(0, frames * channels);
            if (expected > 0 && floats.Length != expected)
                Log?.Invoke($"Native VST3 PCM length mismatch: got {floats.Length} floats, expected {expected}.");
            return floats;
        }
        catch (Exception ex)
        {
            lastError = ex.Message;
            Log?.Invoke("Native VST3 PCM decode failed: " + ex.Message);
            return null;
        }
    }

    private bool Send(object message)
    {
        lock (gate)
        {
            if (stdin == null || process == null || process.HasExited) return false;
            try
            {
                stdin.WriteLine(JsonSerializer.Serialize(message));
                stdin.Flush();
                return true;
            }
            catch (Exception ex)
            {
                lastError = ex.Message;
                Log?.Invoke("Native VST3 host IPC failed: " + ex.Message);
                return false;
            }
        }
    }

    private static string ResolveHostPath()
    {
        var env = Environment.GetEnvironmentVariable("LEMMINGS_VST3_NATIVE_HOST");
        if (!string.IsNullOrWhiteSpace(env)) return env;
        return Path.Combine(AppContext.BaseDirectory, "LemmingsVst3Host.exe");
    }

    public void Dispose()
    {
        lock (gate)
        {
            try { Send(new { op = "quit" }); } catch { }
            try { stdin?.Dispose(); } catch { }
            try { if (process is { HasExited: false }) process.Kill(entireProcessTree: true); } catch { }
            process?.Dispose();
            process = null; stdin = null;
        }
    }
}
