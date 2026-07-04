using System.Net.Http;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;

namespace LemmingsStudio.Windows.Features;

/// <summary>
/// Windows port of the macOS Ollama integration: talks to a local Ollama daemon over its
/// REST API (http://127.0.0.1:11434) to list installed models, pull a model with progress,
/// and generate text. Mirrors the Mac client's behaviour, including stripping &lt;think&gt;
/// reasoning blocks that some models emit (which otherwise look like an empty answer).
/// </summary>
public sealed class OllamaClient
{
    private readonly HttpClient _http;
    public Uri Host { get; }

    public OllamaClient(string host = "http://127.0.0.1:11434")
    {
        Host = new Uri(host);
        // Windows hardening:
        //  • UseProxy=false — a configured system/corporate proxy otherwise intercepts
        //    even 127.0.0.1 calls and makes the local daemon look unreachable.
        //  • We hit 127.0.0.1 (not "localhost") so Windows can't resolve to IPv6 ::1
        //    first while Ollama is bound to IPv4 only (a classic localhost stall).
        var handler = new HttpClientHandler { UseProxy = false, Proxy = null };
        _http = new HttpClient(handler) { BaseAddress = Host, Timeout = TimeSpan.FromMinutes(10) };
    }

    /// <summary>
    /// Auto-install Ollama on Windows, mirroring the macOS bootstrap. Tries winget first
    /// (`Ollama.Ollama`, the clean noob path), then falls back to downloading and running the
    /// official OllamaSetup.exe. The Windows installer starts the server itself, so we then
    /// just wait for the REST port to answer. Returns true once Ollama is reachable.
    /// </summary>
    public async Task<bool> InstallAsync(Action<string> log, CancellationToken token = default)
    {
        if (await IsServerRunningAsync()) { log("Ollama is already running."); return true; }
        log("Installing Ollama…");

        // 1) winget — handles download, install and PATH; per-user, usually no admin prompt.
        try
        {
            int code = await RunAsync("winget",
                "install --id Ollama.Ollama -e --silent --accept-package-agreements --accept-source-agreements",
                log, token);
            if (code == 0) log("winget install finished.");
            else log($"winget exited {code}; will try a direct download next.");
        }
        catch (Exception ex) { log("winget not available (" + ex.Message + "); trying direct download."); }

        if (await WaitForServerAsync(20, log)) return true;

        // 2) Fallback: download the official installer and run it. Uses a separate HttpClient
        //    WITH the system proxy (the opposite of our localhost client) for the external URL.
        try
        {
            const string url = "https://ollama.com/download/OllamaSetup.exe";
            string tmp = Path.Combine(Path.GetTempPath(), "OllamaSetup.exe");
            log("Downloading the Ollama installer (large, please wait)…");
            using (var dl = new HttpClient { Timeout = TimeSpan.FromMinutes(30) })
            using (var resp = await dl.GetAsync(url, HttpCompletionOption.ResponseHeadersRead, token))
            {
                resp.EnsureSuccessStatusCode();
                await using var fs = File.Create(tmp);
                await resp.Content.CopyToAsync(fs, token);
            }
            log("Running the installer (silent)…");
            var psi = new System.Diagnostics.ProcessStartInfo
            {
                FileName = tmp,
                Arguments = "/VERYSILENT /NORESTART /SUPPRESSMSGBOXES",
                UseShellExecute = true
            };
            var p = System.Diagnostics.Process.Start(psi);
            if (p != null) await p.WaitForExitAsync(token);
        }
        catch (Exception ex)
        {
            log("Direct-download install failed: " + ex.Message);
            log("Please install manually from https://ollama.com/download .");
            return false;
        }

        return await WaitForServerAsync(30, log);
    }

    private async Task<bool> WaitForServerAsync(int tries, Action<string> log)
    {
        for (int i = 0; i < tries; i++)
        {
            if (await IsServerRunningAsync()) { log("Ollama server is up."); return true; }
            if (i == 3) await EnsureServerAsync(log); // nudge it if installed but not started
            await Task.Delay(1000);
        }
        return false;
    }

    private static async Task<int> RunAsync(string file, string args, Action<string> log, CancellationToken token)
    {
        var psi = new System.Diagnostics.ProcessStartInfo
        {
            FileName = file,
            Arguments = args,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true
        };
        using var p = System.Diagnostics.Process.Start(psi)
            ?? throw new InvalidOperationException($"Could not start {file}.");
        var outTask = p.StandardOutput.ReadToEndAsync(token);
        var errTask = p.StandardError.ReadToEndAsync(token);
        await p.WaitForExitAsync(token);
        string o = await outTask, e = await errTask;
        if (!string.IsNullOrWhiteSpace(o)) log(o.Trim());
        if (!string.IsNullOrWhiteSpace(e)) log(e.Trim());
        return p.ExitCode;
    }

    /// <summary>True if an Ollama server answers on the host.</summary>
    public async Task<bool> IsServerRunningAsync()
    {
        try
        {
            using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(3));
            using var resp = await _http.GetAsync("api/tags", cts.Token);
            return resp.IsSuccessStatusCode;
        }
        catch { return false; }
    }

    /// <summary>
    /// Best-effort: if the server isn't up, try to launch it. On Windows, `ollama`
    /// is on PATH after the standard installer; we start `ollama serve` detached and
    /// poll briefly. Returns true if the server is reachable afterward.
    /// </summary>
    public async Task<bool> EnsureServerAsync(Action<string>? log = null)
    {
        if (await IsServerRunningAsync()) return true;
        try
        {
            var psi = new System.Diagnostics.ProcessStartInfo
            {
                FileName = "ollama",
                Arguments = "serve",
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true
            };
            System.Diagnostics.Process.Start(psi);
            log?.Invoke("Started 'ollama serve'…");
        }
        catch (Exception ex)
        {
            log?.Invoke("Couldn't launch ollama (is it installed and on PATH?): " + ex.Message);
            return false;
        }
        for (int i = 0; i < 10; i++)
        {
            await Task.Delay(600);
            if (await IsServerRunningAsync()) return true;
        }
        return false;
    }

    /// <summary>Installed model tags (e.g. "llama3.1:8b").</summary>
    public async Task<List<string>> ListModelsAsync()
    {
        var result = new List<string>();
        try
        {
            using var resp = await _http.GetAsync("api/tags");
            resp.EnsureSuccessStatusCode();
            using var doc = JsonDocument.Parse(await resp.Content.ReadAsStringAsync());
            if (doc.RootElement.TryGetProperty("models", out var models))
                foreach (var m in models.EnumerateArray())
                    if (m.TryGetProperty("name", out var name) && name.GetString() is { } s)
                        result.Add(s);
        }
        catch { /* return what we have */ }
        return result;
    }

    /// <summary>Download a model, reporting NDJSON progress lines from /api/pull.</summary>
    public async Task PullAsync(string tag, Action<string> onProgress, CancellationToken token = default)
    {
        var body = new StringContent(JsonSerializer.Serialize(new { model = tag, stream = true }), Encoding.UTF8, "application/json");
        using var req = new HttpRequestMessage(HttpMethod.Post, "api/pull") { Content = body };
        using var resp = await _http.SendAsync(req, HttpCompletionOption.ResponseHeadersRead, token);
        resp.EnsureSuccessStatusCode();
        using var stream = await resp.Content.ReadAsStreamAsync(token);
        using var reader = new StreamReader(stream);
        string? line;
        while ((line = await reader.ReadLineAsync(token)) != null)
        {
            if (string.IsNullOrWhiteSpace(line)) continue;
            try
            {
                using var doc = JsonDocument.Parse(line);
                var root = doc.RootElement;
                string status = root.TryGetProperty("status", out var st) ? st.GetString() ?? "" : "";
                if (root.TryGetProperty("completed", out var comp) && root.TryGetProperty("total", out var tot)
                    && tot.GetInt64() > 0)
                {
                    double pct = 100.0 * comp.GetInt64() / tot.GetInt64();
                    onProgress($"{status} {pct:0}%");
                }
                else if (!string.IsNullOrEmpty(status))
                {
                    onProgress(status);
                }
            }
            catch { onProgress(line); }
        }
    }

    /// <summary>Generate a completion. Strips &lt;think&gt; blocks; retries once via /api/chat.</summary>
    public async Task<string> GenerateAsync(string model, string system, string prompt, CancellationToken token = default)
    {
        string text = await PostGenerate(model, system, prompt, token);
        text = StripThink(text);
        if (string.IsNullOrWhiteSpace(text))
        {
            // Some reasoning models only emit <think>…</think> on the first pass; nudge once.
            text = StripThink(await PostGenerate(model, system,
                prompt + "\n\nProvide your final answer directly, with no <think> blocks.", token));
        }
        if (string.IsNullOrWhiteSpace(text))
            text = await PostChat(model, system, prompt, token);
        return text.Trim();
    }

    private async Task<string> PostGenerate(string model, string system, string prompt, CancellationToken token)
    {
        var payload = new { model = model.Trim(), system, prompt, stream = false };
        var body = new StringContent(JsonSerializer.Serialize(payload), Encoding.UTF8, "application/json");
        using var resp = await _http.PostAsync("api/generate", body, token);
        if (!resp.IsSuccessStatusCode)
            throw new InvalidOperationException($"Ollama /api/generate failed ({(int)resp.StatusCode}). Is the model '{model}' installed?");
        using var doc = JsonDocument.Parse(await resp.Content.ReadAsStringAsync(token));
        return doc.RootElement.TryGetProperty("response", out var r) ? r.GetString() ?? "" : "";
    }

    private async Task<string> PostChat(string model, string system, string prompt, CancellationToken token)
    {
        var payload = new
        {
            model = model.Trim(),
            messages = new object[]
            {
                new { role = "system", content = system },
                new { role = "user", content = prompt }
            },
            stream = false
        };
        var body = new StringContent(JsonSerializer.Serialize(payload), Encoding.UTF8, "application/json");
        using var resp = await _http.PostAsync("api/chat", body, token);
        if (!resp.IsSuccessStatusCode) return "";
        using var doc = JsonDocument.Parse(await resp.Content.ReadAsStringAsync(token));
        return doc.RootElement.TryGetProperty("message", out var msg) && msg.TryGetProperty("content", out var c)
            ? StripThink(c.GetString() ?? "") : "";
    }

    private static string StripThink(string s)
    {
        if (string.IsNullOrEmpty(s)) return s;
        int open;
        while ((open = s.IndexOf("<think>", StringComparison.OrdinalIgnoreCase)) >= 0)
        {
            int close = s.IndexOf("</think>", open, StringComparison.OrdinalIgnoreCase);
            if (close < 0) { s = s[..open]; break; }
            s = s.Remove(open, close - open + "</think>".Length);
        }
        return s.Trim();
    }

    /// <summary>Pick a sensible default model for the machine's RAM (advisory only).</summary>
    public static string RecommendedModel()
    {
        ulong ram = TotalPhysicalMemoryBytes();
        double gb = ram / 1024.0 / 1024.0 / 1024.0;
        if (gb <= 0) return "llama3.2:3b";
        if (gb < 9) return "gemma2:2b";
        if (gb < 18) return "llama3.2:3b";
        return "llama3.1:8b";
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct MEMORYSTATUSEX
    {
        public uint dwLength;
        public uint dwMemoryLoad;
        public ulong ullTotalPhys;
        public ulong ullAvailPhys;
        public ulong ullTotalPageFile;
        public ulong ullAvailPageFile;
        public ulong ullTotalVirtual;
        public ulong ullAvailVirtual;
        public ulong ullAvailExtendedVirtual;
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GlobalMemoryStatusEx(ref MEMORYSTATUSEX lpBuffer);

    private static ulong TotalPhysicalMemoryBytes()
    {
        try
        {
            var s = new MEMORYSTATUSEX { dwLength = (uint)Marshal.SizeOf<MEMORYSTATUSEX>() };
            return GlobalMemoryStatusEx(ref s) ? s.ullTotalPhys : 0;
        }
        catch { return 0; }
    }
}
