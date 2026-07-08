namespace LemmingsStudio.Windows;

public sealed class ProjectHealthReport
{
    public List<string> MissingMedia { get; } = new();
    public List<(DeviceSlot Slot, string Path)> MissingPlugins { get; } = new();
    public bool HasIssues => MissingMedia.Count > 0 || MissingPlugins.Count > 0;

    public string Summary()
    {
        var lines = new List<string>();
        if (MissingMedia.Count > 0)
        {
            lines.Add($"Missing media: {MissingMedia.Count}");
            lines.AddRange(MissingMedia.Take(20).Select(p => "  • " + p));
            if (MissingMedia.Count > 20) lines.Add($"  …and {MissingMedia.Count - 20} more");
        }
        if (MissingPlugins.Count > 0)
        {
            lines.Add($"Missing VST3 plug-ins: {MissingPlugins.Count}");
            lines.AddRange(MissingPlugins.Take(20).Select(x => $"  • {x.Slot.Name}: {x.Path}"));
            if (MissingPlugins.Count > 20) lines.Add($"  …and {MissingPlugins.Count - 20} more");
        }
        return lines.Count == 0 ? "Project health check passed." : string.Join(Environment.NewLine, lines);
    }
}

public static class ProjectHealthService
{
    public static ProjectHealthReport Audit(StudioProject project)
    {
        var report = new ProjectHealthReport();
        foreach (var track in project.Tracks)
        {
            foreach (var clip in track.Clips.Where(c => c.Type == ClipType.Audio && !string.IsNullOrWhiteSpace(c.SourcePath)))
                if (!File.Exists(clip.SourcePath!)) report.MissingMedia.Add(clip.SourcePath!);
            foreach (var layer in track.SequencerLayers.Where(l => !string.IsNullOrWhiteSpace(l.SourcePath)))
                if (!File.Exists(layer.SourcePath!)) report.MissingMedia.Add(layer.SourcePath!);
            foreach (var slot in track.Devices.Where(d => d.IsVst3 && !string.IsNullOrWhiteSpace(d.PluginPath)))
                if (!File.Exists(slot.PluginPath!)) { slot.NativeHostStatus = "Missing plug-in file"; slot.Enabled = false; report.MissingPlugins.Add((slot, slot.PluginPath!)); }
        }
        foreach (var bus in project.ReturnBuses)
            foreach (var slot in bus.Devices.Where(d => d.IsVst3 && !string.IsNullOrWhiteSpace(d.PluginPath)))
                if (!File.Exists(slot.PluginPath!)) { slot.NativeHostStatus = "Missing plug-in file"; slot.Enabled = false; report.MissingPlugins.Add((slot, slot.PluginPath!)); }

        report.MissingMedia.Sort(StringComparer.OrdinalIgnoreCase);
        var distinct = report.MissingMedia.Distinct(StringComparer.OrdinalIgnoreCase).ToList();
        report.MissingMedia.Clear(); report.MissingMedia.AddRange(distinct);
        return report;
    }

    public static int RelinkMissingMedia(StudioProject project, string root)
    {
        var index = Directory.EnumerateFiles(root, "*", SearchOption.AllDirectories)
            .GroupBy(Path.GetFileName, StringComparer.OrdinalIgnoreCase)
            .ToDictionary(g => g.Key, g => g.First(), StringComparer.OrdinalIgnoreCase);
        var count = 0;
        foreach (var track in project.Tracks)
        {
            foreach (var clip in track.Clips.Where(c => c.Type == ClipType.Audio && !string.IsNullOrWhiteSpace(c.SourcePath) && !File.Exists(c.SourcePath)))
                if (index.TryGetValue(Path.GetFileName(clip.SourcePath!), out var replacement)) { clip.SourcePath = replacement; count++; }
            foreach (var layer in track.SequencerLayers.Where(l => !string.IsNullOrWhiteSpace(l.SourcePath) && !File.Exists(l.SourcePath)))
                if (index.TryGetValue(Path.GetFileName(layer.SourcePath!), out var replacement)) { layer.SourcePath = replacement; count++; }
        }
        return count;
    }
}
