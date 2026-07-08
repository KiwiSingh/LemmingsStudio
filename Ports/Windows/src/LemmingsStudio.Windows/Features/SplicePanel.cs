using System.Net.Http;
using NAudio.Wave;
using LemmingsStudio.Windows;

namespace LemmingsStudio.Windows.Features;

/// <summary>Local-first Splice browser with MCP search, explicit credit spending, cache, audition and drag/drop.</summary>
public sealed class SplicePanel : UserControl
{
    private readonly SpliceClient client = new();
    private readonly SpliceOAuth oauth = new();
    private readonly HttpClient downloader = new();
    private readonly string cacheDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments), "LemmingsStudio", "SpliceSamples");

    private readonly TextBox queryBox = new() { Width = 240 };
    private readonly ComboBox typeBox = new() { DropDownStyle = ComboBoxStyle.DropDownList, Width = 90 };
    private readonly NumericUpDown bpmMin = new() { Width = 60, Minimum = 0, Maximum = 300 };
    private readonly NumericUpDown bpmMax = new() { Width = 60, Minimum = 0, Maximum = 300 };
    private readonly CheckBox fetchOnDrop = new() { Text = "Fetch on Drop", AutoSize = true, Checked = true, Padding = new Padding(8, 5, 0, 0) };
    private readonly CheckBox tempoFit = new() { Text = "Tempo-fit loops", AutoSize = true, Checked = true, Padding = new Padding(8, 5, 0, 0) };
    private readonly TabControl sourceTabs = new() { Dock = DockStyle.Fill };
    private readonly ListView results = CreateList();
    private readonly ListView cache = CreateList();
    private readonly Label status = new() { Dock = DockStyle.Bottom, Height = 26, Padding = new Padding(6, 4, 6, 0), Text = "Local cache ready. Connect to Splice to search the catalog." };

    private List<SpliceSample> current = new();
    private WaveOutEvent? previewOut;
    private AudioFileReader? previewReader;

    public StudioProject? Project { get; set; }
    public Action? OnProjectChanged { get; set; }
    public Action<string>? Log { get; set; }
    public bool TempoFitEnabled => tempoFit.Checked;

    public SplicePanel()
    {
        Dock = DockStyle.Fill;
        Directory.CreateDirectory(cacheDir);
        SpliceDropBroker.Resolver = ResolveForDropAsync;

        var bar = new FlowLayoutPanel { Dock = DockStyle.Top, Height = 42, Padding = new Padding(6, 6, 0, 0), AutoScroll = true };
        var connect = new Button { Text = "Connect Splice", Width = 116 };
        var search = new Button { Text = "Search", Width = 72 };
        var refreshCache = new Button { Text = "Refresh Cache", Width = 102 };
        typeBox.Items.AddRange(new object[] { "any", "loop", "oneshot" });
        typeBox.SelectedIndex = 1;
        bar.Controls.Add(connect);
        bar.Controls.Add(new Label { Text = "Find:", AutoSize = true, Padding = new Padding(8, 6, 0, 0) });
        bar.Controls.Add(queryBox); bar.Controls.Add(typeBox);
        bar.Controls.Add(new Label { Text = "BPM", AutoSize = true, Padding = new Padding(8, 6, 0, 0) });
        bar.Controls.Add(bpmMin); bar.Controls.Add(new Label { Text = "–", AutoSize = true, Padding = new Padding(2, 6, 0, 0) }); bar.Controls.Add(bpmMax);
        bar.Controls.Add(search); bar.Controls.Add(refreshCache); bar.Controls.Add(fetchOnDrop); bar.Controls.Add(tempoFit);

        sourceTabs.TabPages.Add(new TabPage("Splice Search") { Controls = { results } });
        sourceTabs.TabPages.Add(new TabPage("Local Cache") { Controls = { cache } });

        var actions = new FlowLayoutPanel { Dock = DockStyle.Bottom, Height = 38, Padding = new Padding(6, 4, 0, 0) };
        var preview = new Button { Text = "▶ Audition", Width = 96 };
        var stopPreview = new Button { Text = "■ Stop", Width = 72 };
        var add = new Button { Text = "Add to Arrangement", Width = 150 };
        var addSeq = new Button { Text = "Send to Sequencer", Width = 140 };
        var openPage = new Button { Text = "Open Sample Page", Width = 135 };
        var openFolder = new Button { Text = "Open Cache Folder", Width = 132 };
        actions.Controls.AddRange(new Control[] { preview, stopPreview, add, addSeq, openPage, openFolder });

        Controls.Add(sourceTabs); Controls.Add(actions); Controls.Add(bar); Controls.Add(status);

        connect.Click += async (_, _) => await Connect();
        search.Click += async (_, _) => await Search();
        refreshCache.Click += (_, _) => RefreshCache();
        queryBox.KeyDown += async (_, e) => { if (e.KeyCode == Keys.Enter) { e.SuppressKeyPress = true; await Search(); } };
        add.Click += async (_, _) => await AddSelectedToArrangement();
        addSeq.Click += async (_, _) => await AddSelectedToSequencer();
        preview.Click += async (_, _) => await AuditionSelected();
        stopPreview.Click += (_, _) => StopPreview();
        openPage.Click += (_, _) => OpenSelectedPage();
        openFolder.Click += (_, _) => System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(cacheDir) { UseShellExecute = true });
        results.ItemDrag += OnResultItemDrag;
        cache.ItemDrag += OnCacheItemDrag;
        results.DoubleClick += async (_, _) => await AuditionSelected();
        cache.DoubleClick += async (_, _) => await AuditionSelected();

        var saved = SpliceOAuth.LoadSaved();
        if (saved != null && !string.IsNullOrEmpty(saved.AccessToken))
        {
            client.SetBearer(saved.AccessToken);
            status.Text = "Splice token loaded. Search or use the local cache.";
        }
        RefreshCache();
    }

    private static ListView CreateList()
    {
        var v = new ListView { Dock = DockStyle.Fill, View = View.Details, FullRowSelect = true, MultiSelect = false };
        v.Columns.Add("Name", 240); v.Columns.Add("BPM", 55); v.Columns.Add("Key", 55); v.Columns.Add("Pack / Path", 210); v.Columns.Add("Tags", 280);
        return v;
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
        catch (Exception ex) { status.Text = "Connect failed: " + ex.Message; }
    }

    private async Task Search()
    {
        string q = queryBox.Text.Trim();
        if (q.Length == 0) { status.Text = "Type something to search for."; return; }
        status.Text = "Searching Splice…"; results.Items.Clear();
        try
        {
            string? type = typeBox.SelectedItem as string; if (type == "any") type = null;
            int? min = bpmMin.Value > 0 ? (int)bpmMin.Value : null;
            int? max = bpmMax.Value > 0 ? (int)bpmMax.Value : null;
            current = await client.SearchAsync(q, type, min, max);
            foreach (var s in current) results.Items.Add(ItemFor(s));
            status.Text = current.Count > 0 ? $"{current.Count} results. Drag a cached result, or use Fetch on Drop for remote results." : "No results.";
        }
        catch (SpliceAuthException ax) { status.Text = ax.Message + " (click Connect Splice)"; }
        catch (Exception ex) { status.Text = "Search failed: " + ex.Message; }
    }

    private static ListViewItem ItemFor(SpliceSample s)
    {
        var item = new ListViewItem(s.Name); item.SubItems.Add(s.Bpm?.ToString() ?? ""); item.SubItems.Add(s.Key); item.SubItems.Add(s.Pack); item.SubItems.Add(s.Tags); return item;
    }

    private SpliceSample? SelectedRemote => sourceTabs.SelectedIndex == 0 && results.SelectedIndices.Count > 0 && results.SelectedIndices[0] < current.Count ? current[results.SelectedIndices[0]] : null;
    private string? SelectedCachePath => sourceTabs.SelectedIndex == 1 && cache.SelectedItems.Count > 0 ? cache.SelectedItems[0].Tag as string : null;

    private void RefreshCache()
    {
        Directory.CreateDirectory(cacheDir); cache.Items.Clear();
        foreach (var file in Directory.EnumerateFiles(cacheDir).Where(IsAudioFile).OrderByDescending(File.GetLastWriteTimeUtc))
        {
            var item = new ListViewItem(Path.GetFileNameWithoutExtension(file)); item.SubItems.Add(GuessBpm(file)?.ToString() ?? ""); item.SubItems.Add(""); item.SubItems.Add(file); item.SubItems.Add("cached"); item.Tag = file; cache.Items.Add(item);
        }
        status.Text = $"Local cache: {cache.Items.Count} audio file(s).";
    }

    private static bool IsAudioFile(string p) => new[] { ".wav", ".aiff", ".aif", ".mp3", ".flac", ".ogg", ".m4a" }.Contains(Path.GetExtension(p).ToLowerInvariant());

    private async Task<SpliceDropAsset?> ResolveForDropAsync(SpliceSample s)
    {
        try
        {
            string dest = CachedPathFor(s);
            if (!File.Exists(dest))
            {
                status.Text = $"Fetch on Drop: requesting {s.Name}…";
                var url = await client.GetDownloadUrlAsync(s.AssetUuid);
                if (string.IsNullOrEmpty(url)) throw new InvalidOperationException("Splice did not return a download URL.");
                using var resp = await downloader.GetAsync(url, HttpCompletionOption.ResponseHeadersRead); resp.EnsureSuccessStatusCode();
                await using var fs = File.Create(dest); await resp.Content.CopyToAsync(fs);
                RefreshCache();
                Log?.Invoke($"Splice Fetch on Drop cached: {Path.GetFileName(dest)}");
            }
            return new SpliceDropAsset { Name = s.Name, FilePath = dest, Bpm = s.Bpm, DurationSeconds = s.DurationSeconds, Key = s.Key, Type = s.Type };
        }
        catch (Exception ex) { status.Text = "Fetch failed: " + ex.Message; Log?.Invoke(status.Text); return null; }
    }

    private async Task<SpliceDropAsset?> ResolveSelectionAsync(bool confirmCredit)
    {
        var local = SelectedCachePath;
        if (local != null) return new SpliceDropAsset { Name = Path.GetFileNameWithoutExtension(local), FilePath = local, Bpm = GuessBpm(local) };
        var s = SelectedRemote; if (s == null) { status.Text = "Select a sample first."; return null; }
        if (string.IsNullOrEmpty(s.AssetUuid)) { status.Text = "This result has no asset UUID to download."; return null; }
        var dest = CachedPathFor(s);
        if (!File.Exists(dest) && confirmCredit)
        {
            var ok = MessageBox.Show(this, $"Download \"{s.Name}\" from Splice?\n\nThe first download may spend one Splice credit; cached re-use does not.", "Download from Splice", MessageBoxButtons.YesNo, MessageBoxIcon.Question);
            if (ok != DialogResult.Yes) return null;
        }
        return await ResolveForDropAsync(s);
    }

    private async Task AuditionSelected()
    {
        var asset = await ResolveSelectionAsync(confirmCredit: true); if (asset == null) return;
        try
        {
            StopPreview(); previewReader = new AudioFileReader(asset.FilePath); previewOut = new WaveOutEvent(); previewOut.Init(previewReader); previewOut.Play();
            status.Text = $"Auditioning {asset.Name}";
        }
        catch (Exception ex) { status.Text = "Audition failed: " + ex.Message; StopPreview(); }
    }

    private void StopPreview() { try { previewOut?.Stop(); previewOut?.Dispose(); previewReader?.Dispose(); } catch { } previewOut = null; previewReader = null; }

    private async Task AddSelectedToArrangement()
    {
        if (Project == null) { status.Text = "No project loaded."; return; }
        var a = await ResolveSelectionAsync(confirmCredit: true); if (a == null) return;
        var track = Track.Audio(a.Name); track.Clips.Add(BuildClip(a, 0)); Project.Tracks.Add(track);
        status.Text = $"Added {a.Name} to Arrangement."; OnProjectChanged?.Invoke();
    }

    private async Task AddSelectedToSequencer()
    {
        if (Project == null) { status.Text = "No project loaded."; return; }
        var a = await ResolveSelectionAsync(confirmCredit: true); if (a == null) return;
        var track = Project.Tracks.FirstOrDefault(t => t.UseStepSequencer) ?? Track.Instrument("Splice Sequencer");
        if (!Project.Tracks.Contains(track)) { track.UseStepSequencer = true; track.Devices.Clear(); track.Devices.Add(DeviceSlot.Stock("Drum Machine")); Project.Tracks.Add(track); }
        var layer = track.SequencerLayers.FirstOrDefault(l => string.IsNullOrEmpty(l.SourcePath)) ?? new SequencerLayer { Name = a.Name, Note = 60 + track.SequencerLayers.Count };
        layer.Name = a.Name; layer.SourcePath = a.FilePath;
        if (!track.SequencerLayers.Contains(layer)) track.SequencerLayers.Add(layer);
        status.Text = $"Loaded {a.Name} into sequencer lane {layer.Name}."; OnProjectChanged?.Invoke();
    }

    public ProjectClip BuildClip(SpliceDropAsset a, double startBeat)
    {
        double sourceBpm = a.Bpm is > 0 ? a.Bpm.Value : Project?.Tempo ?? 128;
        double naturalBeats = a.DurationSeconds is > 0 ? Math.Max(0.25, a.DurationSeconds.Value * sourceBpm / 60.0) : 4;
        return new ProjectClip { Type = ClipType.Audio, Name = a.Name, SourcePath = a.FilePath, StartBeat = startBeat, LengthBeats = naturalBeats, SourceTempo = sourceBpm, WarpEnabled = TempoFitEnabled && string.Equals(a.Type, "loop", StringComparison.OrdinalIgnoreCase) };
    }

    private void OnResultItemDrag(object? sender, ItemDragEventArgs e)
    {
        var s = SelectedRemote; if (s == null) return;
        var dest = CachedPathFor(s);
        if (File.Exists(dest)) { results.DoDragDrop(new DataObject(DataFormats.FileDrop, new[] { dest }), DragDropEffects.Copy); return; }
        if (!fetchOnDrop.Checked) { status.Text = "Sample is not cached. Enable Fetch on Drop or use Add/Audition first."; return; }
        var data = new DataObject(); data.SetData(SpliceDropBroker.DataFormat, s); results.DoDragDrop(data, DragDropEffects.Copy);
    }

    private void OnCacheItemDrag(object? sender, ItemDragEventArgs e)
    {
        var path = SelectedCachePath; if (path != null) cache.DoDragDrop(new DataObject(DataFormats.FileDrop, new[] { path }), DragDropEffects.Copy);
    }

    private void OpenSelectedPage()
    {
        var s = SelectedRemote; if (s == null || string.IsNullOrEmpty(s.Link)) { status.Text = "Select a Splice search result first."; return; }
        try { System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(s.Link) { UseShellExecute = true }); } catch (Exception ex) { status.Text = "Couldn't open page: " + ex.Message; }
    }

    private string CachedPathFor(SpliceSample s) => Path.Combine(cacheDir, SanitizeFileName((s.Name.Length > 0 ? s.Name : s.AssetUuid) + ".wav"));
    private static string SanitizeFileName(string name) { foreach (var c in Path.GetInvalidFileNameChars()) name = name.Replace(c, '_'); return name; }
    private static int? GuessBpm(string path)
    {
        var m = System.Text.RegularExpressions.Regex.Match(Path.GetFileNameWithoutExtension(path), @"(?<!\d)([6-9]\d|1\d\d|2[0-4]\d)(?:\s?bpm)?(?!\d)", System.Text.RegularExpressions.RegexOptions.IgnoreCase);
        return m.Success && int.TryParse(m.Groups[1].Value, out var bpm) ? bpm : null;
    }
}
