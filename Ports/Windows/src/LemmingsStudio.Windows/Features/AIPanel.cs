namespace LemmingsStudio.Windows.Features;

/// <summary>Local-AI panel: checks the Ollama server, lists/pulls models, and generates text.</summary>
public sealed class AIPanel : UserControl
{
    private readonly OllamaClient client = new();
    private readonly AIAssistant assistant;
    private readonly SoundAgent soundAgent;
    public StudioProject? Project { get; set; }
    public Action? OnProjectChanged;
    private readonly Label status = new() { Dock = DockStyle.Top, Height = 26, Padding = new Padding(6, 5, 6, 0), Text = "Ollama: not checked" };
    private readonly ComboBox modelBox = new() { DropDownStyle = ComboBoxStyle.DropDownList, Width = 210 };
    private readonly ComboBox chatModelBox = new() { DropDownStyle = ComboBoxStyle.DropDownList, Width = 210 };
    public Func<ProjectClip?>? SelectedClipProvider { get; set; }
    private readonly TextBox prompt = new() { Multiline = true, ScrollBars = ScrollBars.Vertical, Dock = DockStyle.Fill, Text = "Suggest 4 track names for a synthwave project." };
    private readonly TextBox response = new() { Multiline = true, ReadOnly = true, ScrollBars = ScrollBars.Vertical, Dock = DockStyle.Fill, Font = new Font("Segoe UI", 9.5f) };

    public Action<string>? Log;

    public AIPanel()
    {
        Dock = DockStyle.Fill;
        assistant = new AIAssistant(client);
        soundAgent = new SoundAgent(client);

        var bar = new FlowLayoutPanel { Dock = DockStyle.Top, Height = 72, Padding = new Padding(6, 6, 6, 0), WrapContents = true };
        var check = new Button { Text = "Check Server", Width = 100 };
        var install = new Button { Text = "Install Ollama", Width = 110 };
        var refresh = new Button { Text = "Refresh Models", Width = 110 };
        var pull = new Button { Text = "Pull Agent Model", Width = 125 };
        var pullChat = new Button { Text = "Pull Chat Model", Width = 120 };
        bar.Controls.Add(new Label { Text = "Agent model:", AutoSize = true, Padding = new Padding(0, 6, 0, 0) });
        bar.Controls.Add(modelBox);
        bar.Controls.Add(new Label { Text = "Chat model:", AutoSize = true, Padding = new Padding(8, 6, 0, 0) });
        bar.Controls.Add(chatModelBox);
        bar.Controls.Add(check);
        bar.Controls.Add(install);
        bar.Controls.Add(refresh);
        bar.Controls.Add(pull);
        bar.Controls.Add(pullChat);

        var split = new SplitContainer { Dock = DockStyle.Fill, Orientation = Orientation.Horizontal, SplitterDistance = 120 };
        var promptPanel = new Panel { Dock = DockStyle.Fill };
        promptPanel.Controls.Add(prompt);
        promptPanel.Controls.Add(new Label { Dock = DockStyle.Top, Text = "Prompt", Height = 18 });
        var genBar = new FlowLayoutPanel { Dock = DockStyle.Bottom, Height = 36 };
        var generate = new Button { Text = "Generate", Width = 120 };
        var agent = new Button { Text = "Run Agent ⚡", Width = 130 };
        var design = new Button { Text = "Design Sound 🎛", Width = 140 };
        var signature = new Button { Text = "Replicate Signature", Width = 145 };
        genBar.Controls.Add(generate);
        genBar.Controls.Add(agent);
        genBar.Controls.Add(design);
        genBar.Controls.Add(signature);
        promptPanel.Controls.Add(genBar);

        var responsePanel = new Panel { Dock = DockStyle.Fill };
        responsePanel.Controls.Add(response);
        responsePanel.Controls.Add(new Label { Dock = DockStyle.Top, Text = "Response", Height = 18 });

        split.Panel1.Controls.Add(promptPanel);
        split.Panel2.Controls.Add(responsePanel);

        Controls.Add(split);
        Controls.Add(bar);
        Controls.Add(status);

        check.Click += async (_, _) => await CheckServer();
        install.Click += async (_, _) => await InstallOllama();
        refresh.Click += async (_, _) => await RefreshModels();
        pull.Click += async (_, _) => await PullRecommended();
        pullChat.Click += async (_, _) => await PullChatModel();
        generate.Click += async (_, _) => await Generate();
        agent.Click += async (_, _) => await RunAgent();
        design.Click += async (_, _) => await RunSoundDesign();
        signature.Click += async (_, _) => await ReplicateSonicSignature();
    }

    private (Track track, DeviceSlot dev)? FindInstrument(string prompt)
    {
        if (Project == null) return null;
        bool IsInstrument(DeviceSlot d) =>
            d.Name.Contains("Synth", StringComparison.OrdinalIgnoreCase) ||
            d.Name.Contains("Oscillatron", StringComparison.OrdinalIgnoreCase) ||
            d.Name.Contains("LemmingBass", StringComparison.OrdinalIgnoreCase);

        // Prefer a track named in the prompt.
        foreach (var t in Project.Tracks)
            if (prompt.Contains(t.Name, StringComparison.OrdinalIgnoreCase))
                foreach (var d in t.Devices)
                    if (IsInstrument(d)) return (t, d);
        // Otherwise the first instrument device anywhere.
        foreach (var t in Project.Tracks)
            foreach (var d in t.Devices)
                if (IsInstrument(d)) return (t, d);
        return null;
    }

    private async Task RunSoundDesign()
    {
        if (Project == null) { status.Text = "No project loaded."; return; }
        if (modelBox.SelectedItem is not string model)
        {
            status.Text = "Pick a model first (Check Server → Refresh Models).";
            return;
        }
        var target = FindInstrument(prompt.Text);
        if (target == null) { status.Text = "No instrument device found. Add Oscillatron/LemmingBass/Synth to a track first."; return; }

        response.Text = "Designing patch…";
        try
        {
            var d = await soundAgent.DesignAsync(prompt.Text, target.Value.dev, model);
            string changed = string.Join(", ", d.Params.Keys);
            response.Text = $"\"{d.PresetName}\" → {target.Value.track.Name} / {target.Value.dev.Name}\r\n\r\n{d.Notes}\r\n\r\nParams: {changed}";
            status.Text = $"Applied patch \"{d.PresetName}\".";
            OnProjectChanged?.Invoke();
        }
        catch (Exception ex)
        {
            response.Text = "";
            status.Text = "Sound design failed: " + ex.Message;
        }
    }

    private async Task RunAgent()
    {
        if (Project == null) { status.Text = "No project loaded."; return; }
        if (modelBox.SelectedItem is not string model)
        {
            status.Text = "Pick a model first (Check Server → Refresh Models).";
            return;
        }
        response.Text = "Planning…";
        try
        {
            var result = await assistant.RunAsync(prompt.Text, Project, model);
            if (result.Ops.Count == 0)
            {
                response.Text = result.Text;
                status.Text = "No actionable plan.";
                return;
            }
            var log = AssistantExecutor.Apply(result.Ops, Project);
            response.Text = result.Text + "\r\n\r\n— Applied —\r\n" + string.Join("\r\n", log);
            status.Text = $"Applied {result.Ops.Count} op(s).";
            OnProjectChanged?.Invoke();
        }
        catch (Exception ex)
        {
            response.Text = "";
            status.Text = "Agent failed: " + ex.Message;
        }
    }

    private async Task ReplicateSonicSignature()
    {
        if (Project == null) { status.Text = "No project loaded."; return; }
        var clip = SelectedClipProvider?.Invoke();
        if (clip == null || clip.Type != ClipType.Audio)
        {
            status.Text = "Select an audio clip in Arrangement first.";
            return;
        }
        if (modelBox.SelectedItem is not string model)
        {
            status.Text = "Pick an agent model first.";
            return;
        }

        var choice = MessageBox.Show(this,
            "Replicate the selected clip with the stock analog instrument?\n\nChoose No to target a third-party/VST3 instrument such as Serum.",
            "Replicate Sonic Signature", MessageBoxButtons.YesNoCancel, MessageBoxIcon.Question);
        if (choice == DialogResult.Cancel) return;

        DeviceSlot? target;
        Track? targetTrack;
        if (choice == DialogResult.Yes)
        {
            targetTrack = Project.Tracks.FirstOrDefault(t => t.Type == TrackType.Instrument) ?? Track.Instrument("Signature Replica");
            if (!Project.Tracks.Contains(targetTrack)) Project.Tracks.Add(targetTrack);
            target = targetTrack.Devices.FirstOrDefault(d => d.Kind == DeviceKind.Stock);
            if (target == null) { target = DeviceSlot.Stock("Oscillatron"); targetTrack.Devices.Insert(0, target); }
        }
        else
        {
            var candidates = Project.Tracks
                .SelectMany(t => t.Devices.Select(d => (Track: t, Device: d)))
                .Where(x => x.Device.Kind != DeviceKind.Stock || x.Device.IsVst3)
                .ToList();
            if (candidates.Count == 0)
            {
                status.Text = "No third-party/VST3 instrument target is loaded. Add Serum or another instrument in Devices first.";
                return;
            }
            using var picker = new Form { Text = "Choose third-party target", Width = 440, Height = 150, StartPosition = FormStartPosition.CenterParent };
            var combo = new ComboBox { Dock = DockStyle.Top, DropDownStyle = ComboBoxStyle.DropDownList };
            foreach (var c in candidates) combo.Items.Add($"{c.Track.Name} / {c.Device.Name}");
            combo.SelectedIndex = 0;
            var ok = new Button { Text = "Use Target", Dock = DockStyle.Bottom, DialogResult = DialogResult.OK };
            picker.Controls.Add(combo); picker.Controls.Add(ok); picker.AcceptButton = ok;
            if (picker.ShowDialog(this) != DialogResult.OK) return;
            var selected = candidates[combo.SelectedIndex]; targetTrack = selected.Track; target = selected.Device;
        }

        string source = clip.SourcePath ?? clip.Name;
        string request = $"Replicate the sonic signature of the reference audio clip '{clip.Name}' ({source}) on {target.Name}. " +
            $"Source tempo metadata: {clip.SourceTempo:0.#} BPM; clip length: {clip.LengthBeats:0.##} beats. " +
            "Recreate timbre, envelope, brightness, harmonic density, transient shape, stereo character, movement and FX character. " +
            "Set every host-accessible parameter directly. For any important knob, mode, wavetable, routing switch, modulation assignment or FX setting that is not exposed by the host, do not pretend it was changed: put exact manual completion steps in Notes with control name/path, direction or approximate value/range, and listening goal.";

        response.Text = $"Analysing {clip.Name} → {target.Name}…";
        try
        {
            var design = await soundAgent.DesignAsync(request, target, model);
            response.Text = $"{design.PresetName} → {targetTrack.Name} / {target.Name}\r\n\r\n{design.Notes}\r\n\r\nApplied accessible params: {string.Join(", ", design.Params.Keys)}";
            status.Text = "Sonic-signature replication complete; check Notes for manual inaccessible-knob steps.";
            OnProjectChanged?.Invoke();
        }
        catch (Exception ex) { response.Text = ""; status.Text = "Signature replication failed: " + ex.Message; }
    }

    private async Task InstallOllama()
    {
        status.Text = "Installing Ollama…";
        bool ok = await client.InstallAsync(m => BeginInvoke((Action)(() => { Log?.Invoke(m); status.Text = m; })));
        status.Text = ok
            ? $"Ollama installed & running  •  recommended model: {OllamaClient.RecommendedModel()}"
            : "Ollama install didn't complete. Install manually from ollama.com, then Check Server.";
        if (ok) await RefreshModels();
    }

    private async Task CheckServer()
    {
        status.Text = "Ollama: checking…";
        bool up = await client.IsServerRunningAsync();
        if (!up)
        {
            status.Text = "Ollama: not running — trying to start it…";
            up = await client.EnsureServerAsync(m => BeginInvoke((Action)(() => Log?.Invoke(m))));
        }
        if (!up)
        {
            var choice = MessageBox.Show(this,
                "Ollama isn't installed or running. Install it automatically now?\n\n" +
                "This uses winget (or downloads the official installer) and may take a few minutes.",
                "Install Ollama", MessageBoxButtons.YesNo, MessageBoxIcon.Question);
            if (choice == DialogResult.Yes) { await InstallOllama(); return; }
        }
        status.Text = up
            ? $"Ollama: running at {client.Host}  •  recommended model: {OllamaClient.RecommendedModel()}"
            : $"Ollama: not reachable at {client.Host}. Install from ollama.com (it auto-starts on Windows), then Check Server again.";
        if (up) await RefreshModels();
    }

    private async Task RefreshModels()
    {
        var models = await client.ListModelsAsync();
        modelBox.Items.Clear();
        chatModelBox.Items.Clear();
        foreach (var m in models) { modelBox.Items.Add(m); chatModelBox.Items.Add(m); }
        if (modelBox.Items.Count > 0) modelBox.SelectedIndex = 0;
        if (chatModelBox.Items.Count > 0)
        {
            string recommendedChat = OllamaClient.RecommendedChatModel();
            int match = models.FindIndex(m => m.StartsWith(recommendedChat, StringComparison.OrdinalIgnoreCase));
            chatModelBox.SelectedIndex = match >= 0 ? match : 0;
        }
        status.Text = models.Count > 0
            ? $"Installed models: {models.Count}  •  chat recommendation: {OllamaClient.RecommendedChatModel()}"
            : $"No models installed. Pull agent ({OllamaClient.RecommendedModel()}) or chat ({OllamaClient.RecommendedChatModel()}) model.";
    }

    private async Task PullRecommended()
    {
        string tag = OllamaClient.RecommendedModel();
        Log?.Invoke($"Pulling Ollama model {tag}…");
        try
        {
            await client.PullAsync(tag, p => BeginInvoke((Action)(() => status.Text = $"Pulling {tag}: {p}")));
            status.Text = $"Pulled {tag}.";
            await RefreshModels();
        }
        catch (Exception ex)
        {
            status.Text = "Pull failed: " + ex.Message;
        }
    }

    private async Task PullChatModel()
    {
        string tag = OllamaClient.RecommendedChatModel();
        Log?.Invoke($"Pulling Ollama chat model {tag}…");
        try
        {
            await client.PullAsync(tag, p => BeginInvoke((Action)(() => status.Text = $"Pulling {tag}: {p}")));
            status.Text = $"Pulled chat model {tag}.";
            await RefreshModels();
        }
        catch (Exception ex) { status.Text = "Chat model pull failed: " + ex.Message; }
    }

    private async Task Generate()
    {
        if (chatModelBox.SelectedItem is not string model)
        {
            status.Text = "Pick or pull a chat model first.";
            return;
        }
        response.Text = "Thinking…";
        try
        {
            string answer = await client.GenerateAsync(model,
                "You are the conversational music-production assistant inside LemmingsStudio. Give practical, technically grounded help with theory, synthesis, MIDI, recording, arrangement, mixing, mastering, acoustics, plugins, loudness and troubleshooting. Prefer actionable settings, ranges, signal-chain order and listening tests over vague advice. Do not emit project-edit JSON unless explicitly asked to edit the project.", prompt.Text);
            response.Text = string.IsNullOrWhiteSpace(answer) ? "(no answer returned)" : answer;
            status.Text = "Done.";
        }
        catch (Exception ex)
        {
            response.Text = "";
            status.Text = "Generate failed: " + ex.Message;
        }
    }
}
