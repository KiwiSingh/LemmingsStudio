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
    private readonly ComboBox modelBox = new() { DropDownStyle = ComboBoxStyle.DropDownList, Width = 240 };
    private readonly TextBox prompt = new() { Multiline = true, ScrollBars = ScrollBars.Vertical, Dock = DockStyle.Fill, Text = "Suggest 4 track names for a synthwave project." };
    private readonly TextBox response = new() { Multiline = true, ReadOnly = true, ScrollBars = ScrollBars.Vertical, Dock = DockStyle.Fill, Font = new Font("Segoe UI", 9.5f) };

    public Action<string>? Log;

    public AIPanel()
    {
        Dock = DockStyle.Fill;
        assistant = new AIAssistant(client);
        soundAgent = new SoundAgent(client);

        var bar = new FlowLayoutPanel { Dock = DockStyle.Top, Height = 40, Padding = new Padding(6, 6, 6, 0) };
        var check = new Button { Text = "Check Server", Width = 100 };
        var install = new Button { Text = "Install Ollama", Width = 110 };
        var refresh = new Button { Text = "Refresh Models", Width = 110 };
        var pull = new Button { Text = "Pull Recommended", Width = 130 };
        bar.Controls.Add(new Label { Text = "Model:", AutoSize = true, Padding = new Padding(0, 6, 0, 0) });
        bar.Controls.Add(modelBox);
        bar.Controls.Add(check);
        bar.Controls.Add(install);
        bar.Controls.Add(refresh);
        bar.Controls.Add(pull);

        var split = new SplitContainer { Dock = DockStyle.Fill, Orientation = Orientation.Horizontal, SplitterDistance = 120 };
        var promptPanel = new Panel { Dock = DockStyle.Fill };
        promptPanel.Controls.Add(prompt);
        promptPanel.Controls.Add(new Label { Dock = DockStyle.Top, Text = "Prompt", Height = 18 });
        var genBar = new FlowLayoutPanel { Dock = DockStyle.Bottom, Height = 36 };
        var generate = new Button { Text = "Generate", Width = 120 };
        var agent = new Button { Text = "Run Agent ⚡", Width = 130 };
        var design = new Button { Text = "Design Sound 🎛", Width = 140 };
        genBar.Controls.Add(generate);
        genBar.Controls.Add(agent);
        genBar.Controls.Add(design);
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
        generate.Click += async (_, _) => await Generate();
        agent.Click += async (_, _) => await RunAgent();
        design.Click += async (_, _) => await RunSoundDesign();
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
        foreach (var m in models) modelBox.Items.Add(m);
        if (modelBox.Items.Count > 0) modelBox.SelectedIndex = 0;
        status.Text = models.Count > 0
            ? $"Installed models: {models.Count}"
            : $"No models installed. Try “Pull Recommended” ({OllamaClient.RecommendedModel()}).";
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

    private async Task Generate()
    {
        if (modelBox.SelectedItem is not string model)
        {
            status.Text = "Pick a model first (Check Server → Refresh Models).";
            return;
        }
        response.Text = "Generating…";
        try
        {
            string answer = await client.GenerateAsync(model,
                "You are a helpful music-production assistant inside a DAW.", prompt.Text);
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
