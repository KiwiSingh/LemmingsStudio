namespace LemmingsStudio.Windows;

/// <summary>Small modal dialog to choose export format, bit depth and quality.</summary>
public sealed class ExportDialog : Form
{
    private readonly ComboBox formatBox = new() { DropDownStyle = ComboBoxStyle.DropDownList, Left = 130, Top = 16, Width = 200 };
    private readonly ComboBox depthBox = new() { DropDownStyle = ComboBoxStyle.DropDownList, Left = 130, Top = 52, Width = 200 };
    private readonly ComboBox qualityBox = new() { DropDownStyle = ComboBoxStyle.DropDownList, Left = 130, Top = 88, Width = 200 };
    private readonly Label qualityLabel = new() { Text = "Quality", Left = 16, Top = 91, Width = 110 };
    private readonly Label note = new() { Left = 16, Top = 122, Width = 320, Height = 34, ForeColor = Color.DimGray, Font = new Font("Segoe UI", 8f) };

    public ExportSettings Result { get; private set; } = new();

    public ExportDialog(ExportSettings initial)
    {
        Text = "Export Audio";
        FormBorderStyle = FormBorderStyle.FixedDialog;
        StartPosition = FormStartPosition.CenterParent;
        MaximizeBox = false;
        MinimizeBox = false;
        ClientSize = new Size(350, 210);

        Controls.Add(new Label { Text = "Format", Left = 16, Top = 19, Width = 110 });
        Controls.Add(new Label { Text = "Bit depth", Left = 16, Top = 55, Width = 110 });
        Controls.Add(qualityLabel);
        Controls.Add(formatBox);
        Controls.Add(depthBox);
        Controls.Add(qualityBox);
        Controls.Add(note);

        formatBox.Items.AddRange(new object[] { "WAV", "AIFF", "MP3", "FLAC" });
        formatBox.SelectedIndexChanged += (_, _) => OnFormatChanged();
        formatBox.SelectedIndex = initial.Format switch
        {
            ExportFormat.Aiff => 1,
            ExportFormat.Mp3 => 2,
            ExportFormat.Flac => 3,
            _ => 0
        };
        OnFormatChanged();
        SelectInitial(initial);

        var ok = new Button { Text = "Export", Left = 174, Top = 172, Width = 80, DialogResult = DialogResult.OK };
        var cancel = new Button { Text = "Cancel", Left = 262, Top = 172, Width = 80, DialogResult = DialogResult.Cancel };
        ok.Click += (_, _) => BuildResult();
        Controls.Add(ok);
        Controls.Add(cancel);
        AcceptButton = ok;
        CancelButton = cancel;
    }

    private ExportFormat CurrentFormat => formatBox.SelectedIndex switch
    {
        1 => ExportFormat.Aiff,
        2 => ExportFormat.Mp3,
        3 => ExportFormat.Flac,
        _ => ExportFormat.Wav
    };

    private void OnFormatChanged()
    {
        depthBox.Items.Clear();
        qualityBox.Items.Clear();
        switch (CurrentFormat)
        {
            case ExportFormat.Wav:
                depthBox.Items.AddRange(new object[] { "16-bit PCM", "24-bit PCM", "32-bit float" });
                depthBox.SelectedIndex = 1;
                depthBox.Enabled = true;
                qualityLabel.Visible = qualityBox.Visible = false;
                note.Text = "WAV is lossless and needs no extra tools. 24-bit is the mixing/mastering standard; 32-bit float keeps full headroom.";
                break;
            case ExportFormat.Aiff:
                depthBox.Items.AddRange(new object[] { "16-bit PCM", "24-bit PCM" });
                depthBox.SelectedIndex = 1;
                depthBox.Enabled = true;
                qualityLabel.Visible = qualityBox.Visible = false;
                note.Text = "AIFF is lossless PCM (Apple-friendly). No extra tools needed.";
                break;
            case ExportFormat.Mp3:
                depthBox.Items.Add("n/a (compressed)");
                depthBox.SelectedIndex = 0;
                depthBox.Enabled = false;
                qualityLabel.Text = "Bitrate";
                qualityBox.Items.AddRange(new object[] { "128 kbps", "192 kbps", "256 kbps", "320 kbps" });
                qualityBox.SelectedIndex = 3;
                qualityLabel.Visible = qualityBox.Visible = true;
                note.Text = "MP3 is encoded with the bundled ffmpeg (libmp3lame).";
                break;
            case ExportFormat.Flac:
                depthBox.Items.Add("24-bit (lossless)");
                depthBox.SelectedIndex = 0;
                depthBox.Enabled = false;
                qualityLabel.Text = "Compression";
                qualityBox.Items.AddRange(new object[] { "0 (fast)", "5 (default)", "8", "12 (smallest)" });
                qualityBox.SelectedIndex = 1;
                qualityLabel.Visible = qualityBox.Visible = true;
                note.Text = "FLAC is lossless and encoded with the bundled ffmpeg.";
                break;
        }
    }

    private void SelectInitial(ExportSettings initial)
    {
        if (CurrentFormat == ExportFormat.Wav)
            depthBox.SelectedIndex = initial.BitDepth switch { 16 => 0, 32 => 2, _ => 1 };
        else if (CurrentFormat == ExportFormat.Aiff)
            depthBox.SelectedIndex = initial.BitDepth <= 16 ? 0 : 1;
    }

    private void BuildResult()
    {
        var s = new ExportSettings { Format = CurrentFormat };
        switch (CurrentFormat)
        {
            case ExportFormat.Wav:
                s.BitDepth = depthBox.SelectedIndex switch { 0 => 16, 2 => 32, _ => 24 };
                break;
            case ExportFormat.Aiff:
                s.BitDepth = depthBox.SelectedIndex == 0 ? 16 : 24;
                break;
            case ExportFormat.Mp3:
                s.Mp3Bitrate = new[] { 128, 192, 256, 320 }[Math.Max(0, qualityBox.SelectedIndex)];
                break;
            case ExportFormat.Flac:
                s.FlacCompression = new[] { 0, 5, 8, 12 }[Math.Max(0, qualityBox.SelectedIndex)];
                break;
        }
        Result = s;
    }

    /// <summary>Show the dialog; returns chosen settings, or null if cancelled.</summary>
    public static ExportSettings? Choose(IWin32Window owner, ExportSettings initial)
    {
        using var dlg = new ExportDialog(initial);
        return dlg.ShowDialog(owner) == DialogResult.OK ? dlg.Result : null;
    }
}
