using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace LemmingsStudio.Windows;

public sealed class ProjectRecoveryService
{
    private readonly object gate = new();
    private bool dirty;
    public string SessionId { get; } = Guid.NewGuid().ToString("N");
    public DateTime? LastAutosaveUtc { get; private set; }

    public void MarkDirty() => dirty = true;
    public void MarkClean() => dirty = false;
    public bool IsDirty => dirty;

    public string Autosave(StudioProject project, string? projectPath)
    {
        lock (gate)
        {
            AppPaths.EnsureFirstRunFolders();
            var key = StableKey(projectPath ?? project.Name);
            var path = Path.Combine(AppPaths.Autosaves, key + ".recovery.lemmingsproject");
            ProjectIO.SaveAtomic(path, project);
            var meta = new RecoveryMetadata
            {
                OriginalProjectPath = projectPath,
                ProjectName = project.Name,
                SavedUtc = DateTime.UtcNow,
                SessionId = SessionId
            };
            File.WriteAllText(path + ".meta.json", JsonSerializer.Serialize(meta, new JsonSerializerOptions { WriteIndented = true }));
            LastAutosaveUtc = meta.SavedUtc;
            dirty = false;
            return path;
        }
    }

    public void DeleteRecovery(string? projectPath, string projectName)
    {
        var key = StableKey(projectPath ?? projectName);
        var path = Path.Combine(AppPaths.Autosaves, key + ".recovery.lemmingsproject");
        TryDelete(path); TryDelete(path + ".meta.json");
    }

    public static RecoveryCandidate? FindNewestRecovery()
    {
        AppPaths.EnsureFirstRunFolders();
        var files = Directory.EnumerateFiles(AppPaths.Autosaves, "*.recovery.lemmingsproject")
            .Select(p => new FileInfo(p)).OrderByDescending(f => f.LastWriteTimeUtc);
        foreach (var file in files)
        {
            try
            {
                RecoveryMetadata? meta = null;
                var metaPath = file.FullName + ".meta.json";
                if (File.Exists(metaPath)) meta = JsonSerializer.Deserialize<RecoveryMetadata>(File.ReadAllText(metaPath));
                return new RecoveryCandidate(file.FullName, meta?.OriginalProjectPath, meta?.ProjectName ?? Path.GetFileNameWithoutExtension(file.Name), meta?.SavedUtc ?? file.LastWriteTimeUtc);
            }
            catch { }
        }
        return null;
    }

    private static string StableKey(string input)
    {
        var bytes = SHA256.HashData(Encoding.UTF8.GetBytes(input.ToUpperInvariant()));
        return Convert.ToHexString(bytes.AsSpan(0, 10)).ToLowerInvariant();
    }
    private static void TryDelete(string p) { try { if (File.Exists(p)) File.Delete(p); } catch { } }

    private sealed class RecoveryMetadata
    {
        public string? OriginalProjectPath { get; set; }
        public string ProjectName { get; set; } = "Untitled";
        public DateTime SavedUtc { get; set; }
        public string SessionId { get; set; } = "";
    }
}

public sealed record RecoveryCandidate(string RecoveryPath, string? OriginalProjectPath, string ProjectName, DateTime SavedUtc);
