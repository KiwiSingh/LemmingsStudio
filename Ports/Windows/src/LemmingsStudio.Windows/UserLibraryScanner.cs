namespace LemmingsStudio.Windows;

public sealed record UserLibraryItem(string Name, string Path, string Kind, long Size, DateTime ModifiedUtc);

public sealed class UserLibraryScanner
{
    public event Action<IReadOnlyList<UserLibraryItem>, string>? BatchReady;
    public event Action<string>? Status;

    private static readonly string[] AudioExtensions = { ".wav", ".mp3", ".flac", ".aif", ".aiff", ".m4a", ".ogg" };
    private static readonly string[] MidiExtensions = { ".mid", ".midi" };

    public Task ScanAsync(string root, CancellationToken token = default)
    {
        return Task.Run(() =>
        {
            var batch = new List<UserLibraryItem>(64);
            int seen = 0;
            foreach (var file in EnumerateSafe(root))
            {
                token.ThrowIfCancellationRequested();
                var ext = Path.GetExtension(file).ToLowerInvariant();
                if (!AudioExtensions.Contains(ext) && !MidiExtensions.Contains(ext)) continue;
                var info = new FileInfo(file);
                var kind = MidiExtensions.Contains(ext) ? "MIDI" : ClassifyAudio(file, info.Length);
                batch.Add(new UserLibraryItem(Path.GetFileName(file), file, kind, info.Length, info.LastWriteTimeUtc));
                seen++;
                if (batch.Count >= 48)
                {
                    BatchReady?.Invoke(batch.ToArray(), $"Scanning… {seen} files found");
                    batch.Clear();
                }
            }
            if (batch.Count > 0) BatchReady?.Invoke(batch.ToArray(), $"Scanning… {seen} files found");
            Status?.Invoke($"User Library ready — {seen} files indexed");
        }, token);
    }

    private static IEnumerable<string> EnumerateSafe(string root)
    {
        var pending = new Stack<string>();
        if (Directory.Exists(root)) pending.Push(root);
        while (pending.Count > 0)
        {
            var dir = pending.Pop();
            string[] children;
            try { children = Directory.GetDirectories(dir); } catch { children = Array.Empty<string>(); }
            foreach (var child in children) pending.Push(child);
            string[] files;
            try { files = Directory.GetFiles(dir); } catch { files = Array.Empty<string>(); }
            foreach (var f in files) yield return f;
        }
    }

    private static string ClassifyAudio(string path, long size)
    {
        var s = (Path.GetFileNameWithoutExtension(path) + " " + Path.GetDirectoryName(path)).ToLowerInvariant();
        if (s.Contains("loop") || s.Contains("bpm") || s.Contains("groove") || s.Contains("riff") || s.Contains("phrase") || s.Contains("bhangra")) return "Loop";
        if (s.Contains("kick") || s.Contains("snare") || s.Contains("clap") || s.Contains("hat") || s.Contains("oneshot") || s.Contains("one-shot") || s.Contains("stab")) return "One-shot";
        return size > 512_000 ? "Loop" : "One-shot";
    }
}
