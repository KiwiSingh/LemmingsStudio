using System.Net.Http;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace LemmingsStudio.Windows.Features;

/// <summary>A Splice catalog sample parsed from the MCP describe_a_sound result.</summary>
public sealed class SpliceSample
{
    public string Name { get; set; } = "";
    public int? Bpm { get; set; }
    public string Key { get; set; } = "";
    public double? DurationSeconds { get; set; }
    public string Type { get; set; } = "";   // loop | oneshot
    public string Pack { get; set; } = "";
    public string Tags { get; set; } = "";
    public string Link { get; set; } = "";
    public string AssetUuid { get; set; } = "";

    public string Display => $"{Name}  ·  {(Bpm.HasValue ? Bpm + " BPM" : "—")}  ·  {(string.IsNullOrEmpty(Key) ? "" : "Key " + Key)}  ·  {Pack}";
}

/// <summary>
/// Minimal MCP client over streamable HTTP (JSON-RPC 2.0), ported from the macOS
/// MCPHTTPClient. Talks to the Splice MCP endpoint: initialize → tools/list → tools/call.
/// Handles both application/json and text/event-stream responses and the Mcp-Session-Id
/// handshake. A 401/403 surfaces as <see cref="SpliceAuthException"/> carrying the auth URL.
/// </summary>
public sealed class McpHttpClient
{
    private readonly HttpClient _http = new();
    private readonly string _endpoint;
    private string _bearer;
    private int _nextId = 1;
    private bool _initialized;
    private string? _sessionId;

    public const string ProtocolVersion = "2025-03-26";

    public McpHttpClient(string endpoint, string bearer = "")
    {
        _endpoint = endpoint;
        _bearer = bearer;
    }

    public void SetBearer(string token) { _bearer = token; _initialized = false; _sessionId = null; }

    public async Task InitializeIfNeededAsync(CancellationToken token = default)
    {
        if (_initialized) return;
        await RequestAsync("initialize", new
        {
            protocolVersion = ProtocolVersion,
            capabilities = new { tools = new { } },
            clientInfo = new { name = "LemmingsStudio", version = "1.0" }
        }, token);
        try { await NotifyAsync("notifications/initialized", token); } catch { /* best effort */ }
        _initialized = true;
    }

    public async Task<List<string>> ListToolsAsync(CancellationToken token = default)
    {
        await InitializeIfNeededAsync(token);
        var result = await RequestAsync("tools/list", new { }, token);
        var names = new List<string>();
        if (result.TryGetProperty("tools", out var tools) && tools.ValueKind == JsonValueKind.Array)
            foreach (var t in tools.EnumerateArray())
                if (t.TryGetProperty("name", out var n) && n.GetString() is { } s) names.Add(s);
        return names;
    }

    /// <summary>Call a tool; returns the concatenated text from the result's content blocks.</summary>
    public async Task<string> CallToolTextAsync(string name, object arguments, CancellationToken token = default)
    {
        await InitializeIfNeededAsync(token);
        var result = await RequestAsync("tools/call", new { name, arguments }, token);
        var sb = new StringBuilder();
        if (result.TryGetProperty("content", out var content) && content.ValueKind == JsonValueKind.Array)
            foreach (var block in content.EnumerateArray())
                if (block.TryGetProperty("type", out var ty) && ty.GetString() == "text"
                    && block.TryGetProperty("text", out var tx))
                    sb.AppendLine(tx.GetString());
        return sb.ToString();
    }

    private async Task NotifyAsync(string method, CancellationToken token)
    {
        var envelope = new Dictionary<string, object> { ["jsonrpc"] = "2.0", ["method"] = method };
        await PostAsync(envelope, token);
    }

    private async Task<JsonElement> RequestAsync(string method, object @params, CancellationToken token)
    {
        var envelope = new Dictionary<string, object>
        {
            ["jsonrpc"] = "2.0",
            ["id"] = _nextId++,
            ["method"] = method,
            ["params"] = @params
        };
        var root = await PostAsync(envelope, token);
        if (root.TryGetProperty("error", out var error))
        {
            string msg = error.TryGetProperty("message", out var m) ? m.GetString() ?? "MCP error" : "MCP error";
            throw new InvalidOperationException("Splice MCP error: " + msg);
        }
        return root.TryGetProperty("result", out var result) ? result.Clone() : root.Clone();
    }

    private async Task<JsonElement> PostAsync(Dictionary<string, object> envelope, CancellationToken token)
    {
        using var req = new HttpRequestMessage(HttpMethod.Post, _endpoint);
        req.Content = new StringContent(JsonSerializer.Serialize(envelope), Encoding.UTF8, "application/json");
        req.Headers.Accept.ParseAdd("application/json");
        req.Headers.Accept.ParseAdd("text/event-stream");
        req.Headers.TryAddWithoutValidation("MCP-Protocol-Version", ProtocolVersion);
        if (_sessionId != null) req.Headers.TryAddWithoutValidation("Mcp-Session-Id", _sessionId);
        if (!string.IsNullOrEmpty(_bearer)) req.Headers.Authorization = new AuthenticationHeaderValue("Bearer", _bearer);

        using var resp = await _http.SendAsync(req, token);
        if (resp.Headers.TryGetValues("Mcp-Session-Id", out var sids))
            _sessionId = System.Linq.Enumerable.FirstOrDefault(sids);

        string body = await resp.Content.ReadAsStringAsync(token);
        if ((int)resp.StatusCode is 401 or 403)
            throw new SpliceAuthException("Splice MCP needs you to sign in. Click “Connect Splice” to log in through your browser.", SpliceOAuth.AuthorizationServer);
        if (!resp.IsSuccessStatusCode)
            throw new InvalidOperationException($"Splice MCP HTTP {(int)resp.StatusCode}: {body}");

        return ParseEnvelope(body);
    }

    /// <summary>Accepts a plain JSON body or a text/event-stream body (uses the last data: line).</summary>
    private static JsonElement ParseEnvelope(string body)
    {
        body = body.Trim();
        if (body.StartsWith("{"))
            return JsonDocument.Parse(body).RootElement.Clone();

        // SSE: find the last "data:" line containing JSON.
        string? lastData = null;
        foreach (var line in body.Split('\n'))
        {
            var l = line.Trim();
            if (l.StartsWith("data:")) lastData = l[5..].Trim();
        }
        if (lastData != null && lastData.StartsWith("{"))
            return JsonDocument.Parse(lastData).RootElement.Clone();
        throw new InvalidOperationException("Could not parse MCP response: " + body);
    }
}

public sealed class SpliceAuthException : Exception
{
    public string AuthUrl { get; }
    public SpliceAuthException(string message, string authUrl) : base(message) { AuthUrl = authUrl; }
}

/// <summary>High-level Splice operations on top of the MCP transport.</summary>
public sealed class SpliceClient
{
    public const string Endpoint = "https://mcp.splice.com/mcp";
    private readonly McpHttpClient _mcp;

    public SpliceClient(string bearer = "") { _mcp = new McpHttpClient(Endpoint, bearer); }
    public void SetBearer(string token) => _mcp.SetBearer(token);

    public Task<List<string>> ConnectAsync(CancellationToken token = default) => _mcp.ListToolsAsync(token);

    public async Task<List<SpliceSample>> SearchAsync(string query, string? type, int? bpmMin, int? bpmMax, CancellationToken token = default)
    {
        var args = new Dictionary<string, object> { ["query"] = query };
        if (!string.IsNullOrEmpty(type)) args["type"] = type!;
        if (bpmMin.HasValue) args["bpm_min"] = bpmMin.Value;
        if (bpmMax.HasValue) args["bpm_max"] = bpmMax.Value;
        string text = await _mcp.CallToolTextAsync("describe_a_sound", args, token);
        return ParseSamples(text);
    }

    /// <summary>Returns the presigned download URL for an asset (spends a credit on first download).</summary>
    public async Task<string?> GetDownloadUrlAsync(string assetUuid, CancellationToken token = default)
    {
        string text = await _mcp.CallToolTextAsync("download_asset", new { asset_uuid = assetUuid }, token);
        var m = Regex.Match(text, @"https?://[^\s""'<>]+");
        return m.Success ? m.Value : null;
    }

    // ---- Parse the describe_a_sound markdown listing ----
    private static readonly Regex BlockRe = new(@"###\s*\d+\.\s*(?<name>.+)", RegexOptions.Compiled);

    public static List<SpliceSample> ParseSamples(string text)
    {
        var samples = new List<SpliceSample>();
        if (string.IsNullOrWhiteSpace(text)) return samples;
        // Split into blocks at each "### N." header.
        var parts = Regex.Split(text, @"(?=^###\s*\d+\.)", RegexOptions.Multiline);
        foreach (var block in parts)
        {
            var head = BlockRe.Match(block);
            if (!head.Success) continue;
            var s = new SpliceSample { Name = head.Groups["name"].Value.Trim() };

            var bpm = Regex.Match(block, @"BPM:\s*(\d+)");
            if (bpm.Success && int.TryParse(bpm.Groups[1].Value, out var b)) s.Bpm = b;
            var key = Regex.Match(block, @"Key:\s*([^\|\r\n]+)");
            if (key.Success) s.Key = key.Groups[1].Value.Trim();
            var dur = Regex.Match(block, @"Duration:\s*([\d.]+)s");
            if (dur.Success && double.TryParse(dur.Groups[1].Value, out var d)) s.DurationSeconds = d;
            var ty = Regex.Match(block, @"Type:\s*(\w+)");
            if (ty.Success) s.Type = ty.Groups[1].Value.Trim();
            var pack = Regex.Match(block, @"\*\*Pack:\*\*\s*([^\r\n]+)");
            if (pack.Success) s.Pack = pack.Groups[1].Value.Trim();
            var tags = Regex.Match(block, @"\*\*Tags:\*\*\s*([^\r\n]+)");
            if (tags.Success) s.Tags = tags.Groups[1].Value.Trim();
            var link = Regex.Match(block, @"\*\*Link:\*\*\s*(\S+)");
            if (link.Success) s.Link = link.Groups[1].Value.Trim();
            var uuid = Regex.Match(block, @"\*\*Asset UUID:\*\*\s*([0-9a-fA-F-]{36})");
            if (uuid.Success) s.AssetUuid = uuid.Groups[1].Value.Trim();

            if (!string.IsNullOrEmpty(s.Name)) samples.Add(s);
        }
        return samples;
    }
}
