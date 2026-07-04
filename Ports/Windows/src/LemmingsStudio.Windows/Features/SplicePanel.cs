using System.Net.Http;
using LemmingsStudio.Windows;

namespace LemmingsStudio.Windows.Features;

/// <summary>Splice sample browser powered by the Splice MCP server (search + download into the project).</summary>
public sealed class SplicePanel : UserControl
{
    private readonly SpliceClient client = new();
    private readonly SpliceOAuth oauth = new();
    private readonly HttpClient downloader = new();

    private readonly TextBox queryBox = new() { Width = 260 };
    private readonly ComboBox typeBox = new() { DropDownStyle = ComboBoxStyle.DropDownList, Width = 90 };
    private readonly NumericUpDown bpmMin = new() { Width = 60, Minimum = 0, Maximum = 300, Value = 0 };
    private readonly NumericUpDown bpmMax = new() { Width = 60, Minimum = 0, Maximum = 300, Value = 0 };
    private readonly ListView results = new() { Dock = DockStyle.Fill, View = View.Details, FullRowSelect = true, MultiSelect = false };
    private readonly Label status = new() { Dock = DockStyle.Bottom, Height = 24, Padding = new Padding(6, 4, 6, 0), Text = "Not connected to Splice." };

    private List<SpliceSample> current = new();

    public StudioProject? Project { get; set; }
    public Action? OnProjectChanged { get; set; }
    public Action<string>? Log { get; set; }

    public SplicePanel()
    {
        Dock = DockStyle.Fill;

        var bar = new FlowLayoutPanel { Dock = DockStyle.Top, Height = 40, Padding = new Padding(6, 6, 0, 0) };
        var connect = new Button { Text = "Connect Splice", Width = 120 };
        var search = new Button { Text = "Search", Width = 80 };
        typeBox.Items.AddRange(new object[] { "any", "loop", "oneshot" });
        typeBox.SelectedIndex = 1;
        bar.Controls.Add(connect);
        bar.Controls.Add(new Label { Text = "Find:", AutoSize = true, Padding = new Padding(8, 6, 0, 0) });
        bar.Controls.Add(queryBox);
        bar.Controls.Add(typeBox);
        bar.Controls.Add(new Label { Text = "BPM", AutoSize = true, Padding = new Padding(8, 6, 0, 0) });
        bar.Controls.Add(bpmMin);
        bar.Controls.Add(new Label { Text = "–", AutoSize = true, Padding = new Padding(2, 6, 0, 0) });
        bar.Controls.Add(bpmMax);
        bar.Controls.Add(search);

        results.Columns.Add("Name", 220);
        results.Columns.Add("BPM", 55);
        results.Columns.Add("Key", 50);
        results.Columns.Add("Pack", 150);
        results.Columns.Add("Tags", 240);

        var actions = new FlowLayoutPanel { Dock = DockStyle.Bottom, Height = 36, Padding = new Padding(6, 4, 0, 0) };
        var add = new Button { Text = "Add to Project (uses a credit)", Width = 200 };
        var openPage = new Button { Text = "Open Sample Page", Width = 140 };
        actions.Controls.Add(add);
        actions.Controls.Add(openPage);

        Controls.Add(results);
        Controls.Add(actions);
        Controls.Add(bar);
        Controls.Add(status);

        connect.Click += async (_, _) => await Connect();
        search.Click += async (_, _) => await Search();
        queryBox.KeyDown += async (_, e) => { if (e.KeyCode == Keys.Enter) { e.SuppressKeyPress = true; await Search(); } };
        add.Click += async (_, _) => await AddSelected();
        openPage.Click += (_, _) => OpenSelectedPage();

        // Reuse a saved token if we have one.
        var saved = SpliceOAuth.LoadSaved();
        if (saved != null && !string.IsNullOrEmpty(saved.AccessToken))
        {
            client.SetBearer(saved.AccessToken);
            status.Text = "Splice token loaded. Search away (Connect again if searches fail).";
        }
    }

    private async Task Connect()
    {
        try
        {
            status.Text = "Connecting to Splice…";
            var tokens = await oauth.AuthorizeAsync(m => BeginInvoke((Action)(() => { status.Text = m; Log?.Invoke(m); })));
            client.SetBearer(tokens.AccessToken);
            var tools = await client.ConnectAsync();
            status.Text = $"Connected to Splice. Tools: {string.Join(", ", tools)}";
        }
        catch (Exception ex)
        {
            status.Text = "Connect failed: " + ex.Message;
        }
    }

    private async Task Search()
    {
        string q = queryBox.Text.Trim();
        if (q.Length == 0) { status.Text = "Type something to search for."; return; }
        status.Text = "Searching Splice…";
        results.Items.Clear();
        try
        {
            string? type = typeBox.SelectedItem as string;
            if (type == "any") type = null;
            int? min = bpmMin.Value > 0 ? (int)bpmMin.Value : null;
            int? max = bpmMax.Value > 0 ? (int)bpmMax.Value : null;
            current = await client.SearchAsync(q, type, min, max);
            foreach (var s in current)
            {
                var item = new ListViewItem(s.Name);
                item.SubItems.Add(s.Bpm?.ToString() ?? "");
                item.SubItems.Add(s.Key);
                item.SubItems.Add(s.Pack);
                item.SubItems.Add(s.Tags);
                results.Items.Add(item);
            }
            status.Text = current.Count > 0 ? $"{current.Count} results." : "No results.";
        }
        catch (SpliceAuthException ax)
        {
            status.Text = ax.Message + " (click Connect Splice)";
        }
        catch (Exception ex)
        {
            status.Text = "Search failed: " + ex.Message;
        }
    }

    private SpliceSample? Selected =>
        results.SelectedIndices.Count > 0 && results.SelectedIndices[0] < current.Count
            ? current[results.SelectedIndices[0]] : null;

    private void OpenSelectedPage()
    {
        var s = Selected;
        if (s == null || string.IsNullOrEmpty(s.Link)) { status.Text = "Select a sample first."; return; }
        try { System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(s.Link) { UseShellExecute = true }); }
        catch (Exception ex) { status.Text = "Couldn't open page: " + ex.Message; }
    }

    private async Task AddSelected()
    {
        var s = Selected;
        if (s == null) { status.Text = "Select a sample first."; return; }
        if (Project == null) { status.Text = "No project loaded."; return; }
        if (string.IsNullOrEmpty(s.AssetUuid)) { status.Text = "This result has no asset UUID to download."; return; }

        var confirm = MessageBox.Show(this,
            $"Download \"{s.Name}\" from Splice and add it to the project?\n\n" +
            "The first download of a sample spends one Splice credit (re-downloads are free).",
            "Download from Splice", MessageBoxButtons.YesNo, MessageBoxIcon.Question);
        if (confirm != DialogResult.Yes) return;

        try
        {
            status.Text = $"Requesting download URL for {s.Name}…";
            string? url = await client.GetDownloadUrlAsync(s.AssetUuid);
            if (string.IsNullOrEmpty(url)) { status.Text = "Splice didn't return a download URL."; return; }

            string dir = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments), "LemmingsStudio", "SpliceSamples");
            Directory.CreateDirectory(dir);
            string fileName = SanitizeFileName(s.Name.Length > 0 ? s.Name : s.AssetUuid + ".wav");
            string dest = Path.Combine(dir, fileName);

            status.Text = $"Downloading {s.Name}…";
            using (var resp = await downloader.GetAsync(url, HttpCompletionOption.ResponseHeadersRead))
            {
                resp.EnsureSuccessStatusCode();
                await using var fs = File.Create(dest);
                await resp.Content.CopyToAsync(fs);
            }

            // Create an audio track + clip for the sample.
            double beats = (s.DurationSeconds.HasValue && s.Bpm.HasValue && s.Bpm > 0)
                ? Math.Max(1, s.DurationSeconds.Value * s.Bpm.Value / 60.0) : 4;
            var track = Track.Audio(s.Name.Length > 0 ? s.Name : "Splice Sample");
            track.Clips.Add(new ProjectClip
            {
                Type = ClipType.Audio,
                Name = s.Name,
                SourcePath = dest,
                StartBeat = 0,
                LengthBeats = beats,
                SourceTempo = s.Bpm ?? 128
            });
            Project.Tracks.Add(track);

            status.Text = $"Added \"{s.Name}\" to the project.";
            Log?.Invoke($"Splice: downloaded {fileName} → new track.");
            OnProjectChanged?.Invoke();
        }
        catch (SpliceAuthException ax) { status.Text = ax.Message + " (click Connect Splice)"; }
        catch (Exception ex) { status.Text = "Download failed: " + ex.Message; }
    }

    private static string SanitizeFileName(string name)
    {
        foreach (var c in Path.GetInvalidFileNameChars()) name = name.Replace(c, '_');
        return name.EndsWith(".wav", StringComparison.OrdinalIgnoreCase) ? name : name + ".wav";
    }
}
