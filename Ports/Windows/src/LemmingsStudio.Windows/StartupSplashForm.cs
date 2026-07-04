using System.Drawing.Drawing2D;

namespace LemmingsStudio.Windows;

internal sealed class StartupSplashForm : Form
{
    private readonly PictureBox picture = new();
    private readonly System.Windows.Forms.Timer timer = new();
    private readonly string[] preSplashFrames;
    private readonly int preSplashFps;
    private int frameIndex;
    private bool showingLemmings;
    private DateTime lemmingsShownAt;
    private Image? currentFrame;
    private readonly StartupAudio startupAudio = new();

    public StartupSplashForm()
    {
        preSplashFps = ResolvePreSplashFrameRate();
        preSplashFrames = FindPreSplashFrames(preSplashFps);

        StartPosition = FormStartPosition.CenterScreen;
        FormBorderStyle = FormBorderStyle.None;
        ShowInTaskbar = false;
        TopMost = true;
        BackColor = Color.Black;
        ClientSize = new Size(360, 640);
        DoubleBuffered = true;

        picture.Dock = DockStyle.Fill;
        picture.BackColor = Color.Black;
        picture.SizeMode = PictureBoxSizeMode.Zoom;
        Controls.Add(picture);

        timer.Interval = Math.Clamp((int)Math.Round(1000.0 / Math.Max(1, preSplashFps)), 4, 100);
        timer.Tick += (_, _) => Advance();
    }

    protected override void OnShown(EventArgs e)
    {
        base.OnShown(e);
        startupAudio.PlayOnce();
        if (preSplashFrames.Length > 0)
        {
            ShowFrame(preSplashFrames[0]);
            frameIndex = 1;
            timer.Start();
        }
        else
        {
            ShowLemmingsSplash();
            timer.Start();
        }
    }

    private static int ResolvePreSplashFrameRate()
    {
        var assets = Path.Combine(AppContext.BaseDirectory, "Assets");
        var supported = Directory.Exists(assets)
            ? Directory.GetDirectories(assets, "PreSplashFrames_*")
                .Select(Path.GetFileName)
                .Select(name => int.TryParse(name?.Replace("PreSplashFrames_", ""), out var fps) ? fps : 0)
                .Where(fps => fps > 0)
                .Append(60)
            : new[] { 60 };
        var detected = DisplayRefreshRateDetector.DetectPrimaryRefreshRate(60);
        return DisplayRefreshRateDetector.NearestSupported(detected, supported, 60);
    }

    private static string[] FindPreSplashFrames(int fps)
    {
        var assets = Path.Combine(AppContext.BaseDirectory, "Assets");
        var candidates = new[]
        {
            Path.Combine(assets, $"PreSplashFrames_{fps}"),
            Path.Combine(assets, "PreSplashFrames_60"),
            Path.Combine(assets, "PreSplashFrames")
        };
        foreach (var dir in candidates)
        {
            if (!Directory.Exists(dir)) continue;
            var frames = Directory.GetFiles(dir, "frame_*.jpg").OrderBy(p => p, StringComparer.OrdinalIgnoreCase).ToArray();
            if (frames.Length > 0) return frames;
        }
        return Array.Empty<string>();
    }

    private void Advance()
    {
        if (!showingLemmings)
        {
            if (frameIndex < preSplashFrames.Length)
            {
                ShowFrame(preSplashFrames[frameIndex++]);
                return;
            }
            ShowLemmingsSplash();
            return;
        }

        if ((DateTime.UtcNow - lemmingsShownAt).TotalMilliseconds >= 1550)
        {
            timer.Stop();
            Close();
        }
    }

    private void ShowFrame(string path)
    {
        try
        {
            using var loaded = Image.FromFile(path);
            var next = new Bitmap(loaded);
            var old = currentFrame;
            currentFrame = next;
            picture.Image = next;
            old?.Dispose();
        }
        catch
        {
            ShowLemmingsSplash();
        }
    }

    private void ShowLemmingsSplash()
    {
        showingLemmings = true;
        lemmingsShownAt = DateTime.UtcNow;
        timer.Interval = 50;

        var panel = new SplashPanel
        {
            Dock = DockStyle.Fill,
            BackColor = Color.FromArgb(12, 14, 23)
        };
        Controls.Clear();
        Controls.Add(panel);

        var old = currentFrame;
        currentFrame = null;
        old?.Dispose();
        picture.Image = null;
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            timer.Dispose();
            currentFrame?.Dispose();
            startupAudio.Dispose();
            picture.Dispose();
        }
        base.Dispose(disposing);
    }

    private sealed class SplashPanel : Panel
    {
        private readonly Image? logo;
        private readonly Font titleFont = new("Segoe UI Variable Display", 24f, FontStyle.Bold, GraphicsUnit.Point);
        private readonly Font statusFont = new("Segoe UI", 9f, FontStyle.Regular, GraphicsUnit.Point);
        private readonly Font legalFont = new("Segoe UI", 8f, FontStyle.Regular, GraphicsUnit.Point);

        public SplashPanel()
        {
            DoubleBuffered = true;
            var path = Path.Combine(AppContext.BaseDirectory, "Assets", "LemmingsSplash.png");
            if (File.Exists(path))
            {
                try { logo = Image.FromFile(path); } catch { logo = null; }
            }
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            base.OnPaint(e);
            var g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.InterpolationMode = InterpolationMode.HighQualityBicubic;
            g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.ClearTypeGridFit;

            using var bg = new LinearGradientBrush(ClientRectangle, Color.FromArgb(20, 22, 35), Color.FromArgb(5, 7, 12), 90f);
            g.FillRectangle(bg, ClientRectangle);

            if (logo is not null)
            {
                var size = Math.Min(300, Math.Min(ClientSize.Width - 48, ClientSize.Height - 230));
                var rect = new Rectangle((ClientSize.Width - size) / 2, 76, size, size);
                using var glow = new SolidBrush(Color.FromArgb(32, 0, 220, 255));
                g.FillEllipse(glow, rect.X + 28, rect.Y + 32, rect.Width - 56, rect.Height - 42);
                g.DrawImage(logo, rect);
            }

            DrawCentered(g, "LemmingsStudio", titleFont, Brushes.White, 402);
            using var secondary = new SolidBrush(Color.FromArgb(185, 220, 225, 235));
            DrawCentered(g, "loading the chaos engine…", statusFont, secondary, 444);
            using var legal = new SolidBrush(Color.FromArgb(150, 220, 225, 235));
            DrawCentered(g, "© MagmaVance LLC. All rights reserved.", legalFont, legal, ClientSize.Height - 42);
        }

        private void DrawCentered(Graphics g, string text, Font font, Brush brush, int y)
        {
            var size = g.MeasureString(text, font);
            g.DrawString(text, font, brush, (ClientSize.Width - size.Width) / 2f, y);
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing)
            {
                logo?.Dispose();
                titleFont.Dispose();
                statusFont.Dispose();
                legalFont.Dispose();
            }
            base.Dispose(disposing);
        }
    }
}
