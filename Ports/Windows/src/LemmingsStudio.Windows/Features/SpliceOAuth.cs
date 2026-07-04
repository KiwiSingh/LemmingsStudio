using System.Net;
using System.Net.Http;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace LemmingsStudio.Windows.Features;

/// <summary>
/// Splice MCP OAuth, ported from the macOS flow: discovers the authorization server metadata,
/// dynamically registers LemmingsStudio as a public client (PKCE, token_endpoint_auth_method
/// "none"), opens the system browser for the user to log in, catches the redirect on a loopback
/// socket (RFC 8252), exchanges the code for tokens, and persists them. No admin/URL-ACL needed.
/// </summary>
public sealed class SpliceOAuth
{
    public const string AuthorizationServer = "https://mcp.splice.com";
    private const string MetadataUrl = "https://mcp.splice.com/.well-known/oauth-authorization-server";
    private static readonly string TokenFile =
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "LemmingsStudio", "splice_oauth.json");

    private readonly HttpClient _http = new();

    public sealed class Tokens
    {
        public string AccessToken { get; set; } = "";
        public string RefreshToken { get; set; } = "";
        public string ClientId { get; set; } = "";
        public string TokenEndpoint { get; set; } = "";
    }

    public static Tokens? LoadSaved()
    {
        try { return File.Exists(TokenFile) ? JsonSerializer.Deserialize<Tokens>(File.ReadAllText(TokenFile)) : null; }
        catch { return null; }
    }

    private static void Save(Tokens t)
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(TokenFile)!);
            File.WriteAllText(TokenFile, JsonSerializer.Serialize(t));
        }
        catch { /* best effort */ }
    }

    /// <summary>Run the full browser login. Returns an access token, or throws with a clear message.</summary>
    public async Task<Tokens> AuthorizeAsync(Action<string> log, CancellationToken token = default)
    {
        log("Discovering Splice authorization server…");
        var meta = await GetJsonAsync(MetadataUrl, token);
        string authEndpoint = Str(meta, "authorization_endpoint");
        string tokenEndpoint = Str(meta, "token_endpoint");
        string regEndpoint = Str(meta, "registration_endpoint");
        if (authEndpoint.Length == 0 || tokenEndpoint.Length == 0)
            throw new InvalidOperationException("Splice authorization server metadata was incomplete.");

        // Loopback listener (RFC 8252). Bind to an ephemeral port and keep it for the redirect.
        var listener = new TcpListener(IPAddress.Loopback, 0);
        listener.Start();
        int port = ((IPEndPoint)listener.LocalEndpoint).Port;
        string redirectUri = $"http://127.0.0.1:{port}/splice-oauth";

        // Reuse a previously registered client if present.
        var saved = LoadSaved();
        string clientId = saved?.ClientId ?? "";
        if (clientId.Length == 0)
        {
            log("Registering LemmingsStudio as a Splice OAuth client…");
            clientId = await RegisterClientAsync(regEndpoint, redirectUri, token);
        }

        // PKCE.
        string verifier = Base64Url(RandomBytes(32));
        string challenge = Base64Url(SHA256.HashData(Encoding.ASCII.GetBytes(verifier)));
        string state = Base64Url(RandomBytes(16));

        var authUrl = $"{authEndpoint}?response_type=code&client_id={Uri.EscapeDataString(clientId)}" +
                      $"&redirect_uri={Uri.EscapeDataString(redirectUri)}&state={state}" +
                      $"&code_challenge={challenge}&code_challenge_method=S256";

        log("Opening your browser to sign in to Splice…");
        OpenBrowser(authUrl);

        // Wait for the redirect.
        string code = await WaitForCodeAsync(listener, state, token);
        log("Exchanging authorization code for a token…");

        var tokens = await ExchangeCodeAsync(tokenEndpoint, clientId, redirectUri, code, verifier, token);
        tokens.ClientId = clientId;
        tokens.TokenEndpoint = tokenEndpoint;
        Save(tokens);
        log("Splice connected.");
        return tokens;
    }

    /// <summary>Refresh an expired access token, if we have a refresh token.</summary>
    public async Task<Tokens?> RefreshAsync(Tokens existing, CancellationToken token = default)
    {
        if (string.IsNullOrEmpty(existing.RefreshToken) || string.IsNullOrEmpty(existing.TokenEndpoint)) return null;
        var form = new Dictionary<string, string>
        {
            ["grant_type"] = "refresh_token",
            ["refresh_token"] = existing.RefreshToken,
            ["client_id"] = existing.ClientId
        };
        try
        {
            using var resp = await _http.PostAsync(existing.TokenEndpoint, new FormUrlEncodedContent(form), token);
            if (!resp.IsSuccessStatusCode) return null;
            var t = ParseTokenResponse(await resp.Content.ReadAsStringAsync(token));
            t.ClientId = existing.ClientId;
            t.TokenEndpoint = existing.TokenEndpoint;
            if (string.IsNullOrEmpty(t.RefreshToken)) t.RefreshToken = existing.RefreshToken;
            Save(t);
            return t;
        }
        catch { return null; }
    }

    private async Task<string> RegisterClientAsync(string regEndpoint, string redirectUri, CancellationToken token)
    {
        if (string.IsNullOrEmpty(regEndpoint))
            throw new InvalidOperationException("Splice did not advertise a registration endpoint.");
        var body = new
        {
            client_name = "LemmingsStudio",
            redirect_uris = new[] { redirectUri },
            grant_types = new[] { "authorization_code", "refresh_token" },
            response_types = new[] { "code" },
            token_endpoint_auth_method = "none"
        };
        using var content = new StringContent(JsonSerializer.Serialize(body), Encoding.UTF8, "application/json");
        using var resp = await _http.PostAsync(regEndpoint, content, token);
        string text = await resp.Content.ReadAsStringAsync(token);
        if (!resp.IsSuccessStatusCode)
            throw new InvalidOperationException($"Dynamic client registration HTTP {(int)resp.StatusCode}: {text}");
        using var doc = JsonDocument.Parse(text);
        if (doc.RootElement.TryGetProperty("client_id", out var cid) && cid.GetString() is { Length: > 0 } id)
            return id;
        throw new InvalidOperationException("Registration did not return a client_id.");
    }

    private async Task<Tokens> ExchangeCodeAsync(string tokenEndpoint, string clientId, string redirectUri, string code, string verifier, CancellationToken token)
    {
        var form = new Dictionary<string, string>
        {
            ["grant_type"] = "authorization_code",
            ["code"] = code,
            ["redirect_uri"] = redirectUri,
            ["client_id"] = clientId,
            ["code_verifier"] = verifier
        };
        using var resp = await _http.PostAsync(tokenEndpoint, new FormUrlEncodedContent(form), token);
        string text = await resp.Content.ReadAsStringAsync(token);
        if (!resp.IsSuccessStatusCode)
            throw new InvalidOperationException($"Token exchange HTTP {(int)resp.StatusCode}: {text}");
        return ParseTokenResponse(text);
    }

    private static Tokens ParseTokenResponse(string json)
    {
        using var doc = JsonDocument.Parse(json);
        var r = doc.RootElement;
        return new Tokens
        {
            AccessToken = r.TryGetProperty("access_token", out var a) ? a.GetString() ?? "" : "",
            RefreshToken = r.TryGetProperty("refresh_token", out var rf) ? rf.GetString() ?? "" : ""
        };
    }

    private static async Task<string> WaitForCodeAsync(TcpListener listener, string expectedState, CancellationToken token)
    {
        using var reg = token.Register(listener.Stop);
        try
        {
            using var client = await listener.AcceptTcpClientAsync(token);
            using var stream = client.GetStream();
            var buffer = new byte[8192];
            int read = await stream.ReadAsync(buffer, token);
            string request = Encoding.ASCII.GetString(buffer, 0, read);

            // First line: GET /splice-oauth?code=...&state=... HTTP/1.1
            string firstLine = request.Split('\n')[0];
            string path = firstLine.Split(' ').Length > 1 ? firstLine.Split(' ')[1] : "";
            var query = path.Contains('?') ? path[(path.IndexOf('?') + 1)..] : "";
            var pairs = ParseQuery(query);
            pairs.TryGetValue("code", out var code);
            pairs.TryGetValue("state", out var state);
            pairs.TryGetValue("error", out var error);

            string page = error != null
                ? "Splice login failed: " + WebUtility.HtmlEncode(error)
                : "Splice is connected. You can close this tab and return to LemmingsStudio.";
            byte[] respBytes = Encoding.UTF8.GetBytes(
                "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nConnection: close\r\n\r\n" +
                "<html><body style='font-family:sans-serif;padding:40px'>" + page + "</body></html>");
            await stream.WriteAsync(respBytes, token);
            await stream.FlushAsync(token);

            if (error != null) throw new InvalidOperationException("Splice login returned: " + error);
            if (string.IsNullOrEmpty(code)) throw new InvalidOperationException("No authorization code was returned.");
            if (state != expectedState) throw new InvalidOperationException("OAuth state mismatch (possible interference).");
            return code;
        }
        finally { listener.Stop(); }
    }

    private static Dictionary<string, string> ParseQuery(string query)
    {
        var result = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (var pair in query.Split('&', StringSplitOptions.RemoveEmptyEntries))
        {
            int eq = pair.IndexOf('=');
            if (eq < 0) { result[Uri.UnescapeDataString(pair)] = ""; continue; }
            string k = Uri.UnescapeDataString(pair[..eq]);
            string v = Uri.UnescapeDataString(pair[(eq + 1)..]);
            result[k] = v;
        }
        return result;
    }

    private async Task<JsonElement> GetJsonAsync(string url, CancellationToken token)
    {
        using var resp = await _http.GetAsync(url, token);
        resp.EnsureSuccessStatusCode();
        using var doc = JsonDocument.Parse(await resp.Content.ReadAsStringAsync(token));
        return doc.RootElement.Clone();
    }

    private static string Str(JsonElement o, string key)
        => o.TryGetProperty(key, out var v) && v.ValueKind == JsonValueKind.String ? v.GetString() ?? "" : "";

    private static byte[] RandomBytes(int n) { var b = new byte[n]; RandomNumberGenerator.Fill(b); return b; }
    private static string Base64Url(byte[] data) => Convert.ToBase64String(data).TrimEnd('=').Replace('+', '-').Replace('/', '_');

    private static void OpenBrowser(string url)
    {
        try { System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(url) { UseShellExecute = true }); }
        catch { /* user can copy the URL from the log if needed */ }
    }
}
