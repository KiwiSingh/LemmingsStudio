using NAudio.Wave;

namespace LemmingsStudio.Windows;

/// <summary>
/// Plays the same branded startup sting used by the macOS build.
/// Uses NAudio instead of System.Media so the 24-bit/48 kHz WAV exported by the
/// Mac resources plays correctly on Windows too.
/// </summary>
internal sealed class StartupAudio : IDisposable
{
    private WaveOutEvent? output;
    private AudioFileReader? reader;

    public void PlayOnce()
    {
        try
        {
            string? path = FindStartupSound();
            if (path == null) return;
            reader = new AudioFileReader(path) { Volume = 0.85f };
            output = new WaveOutEvent { DesiredLatency = 90 };
            output.Init(reader);
            output.Play();
        }
        catch
        {
            Dispose(); // Startup audio should never block app launch.
        }
    }

    private static string? FindStartupSound()
    {
        var baseDir = AppContext.BaseDirectory;
        string[] candidates =
        {
            Path.Combine(baseDir, "Assets", "LemmingsStartup.wav"),
            Path.Combine(baseDir, "Assets", "startup.wav"),
            Path.Combine(baseDir, "LemmingsStartup.wav"),
            Path.Combine(baseDir, "startup.wav"),
        };
        return candidates.FirstOrDefault(File.Exists);
    }

    public void Dispose()
    {
        try { output?.Stop(); } catch { }
        output?.Dispose();
        reader?.Dispose();
        output = null;
        reader = null;
    }
}
