using System.Text.Json;
using NAudio.Wave;

namespace LemmingsStudio.Windows;

/// <summary>
/// buildfix241 render-edit workflow: Bounce, Consolidate, Freeze, Unfreeze and Flatten.
/// Rendered assets live under the project's Media/Renders folder (or a safe Documents
/// fallback for unsaved projects), so project JSON remains portable and reopen-safe.
/// </summary>
public static class BounceFreezeService
{
    private static readonly JsonSerializerOptions JsonOptions = new() { PropertyNameCaseInsensitive = true };

    public static ProjectClip BounceClip(StudioProject project, Track sourceTrack, ProjectClip sourceClip, AudioEngine engine, string? projectPath)
    {
        var track = Clone(sourceTrack);
        var clip = Clone(sourceClip);
        clip.StartBeat = 0;
        track.Clips = new List<ProjectClip> { clip };
        track.UseStepSequencer = false;
        track.Frozen = false;
        track.FrozenBackupJson = null;
        track.FrozenSourcePath = null;

        var renderProject = RenderProject(project, track);
        var pcm = engine.Render(renderProject);
        string path = NewRenderPath(project, projectPath, sourceClip.Name + " Bounce");
        WriteWav24(path, pcm);

        var bounced = new ProjectClip
        {
            Type = ClipType.Audio,
            Name = sourceClip.Name + " (Bounced)",
            SourcePath = path,
            StartBeat = sourceClip.StartBeat,
            LengthBeats = Math.Max(.25, PcmBeats(pcm, project.Tempo)),
            SourceTempo = project.Tempo,
            WarpEnabled = false
        };
        sourceTrack.Clips.Add(bounced);
        return bounced;
    }

    public static ProjectClip Consolidate(StudioProject project, Track sourceTrack, HashSet<Guid> selectedIds, AudioEngine engine, string? projectPath)
    {
        var selected = sourceTrack.Clips.Where(c => selectedIds.Contains(c.Id)).OrderBy(c => c.StartBeat).ToList();
        if (selected.Count == 0) throw new InvalidOperationException("No selected clips to consolidate.");
        double start = selected.Min(c => c.StartBeat);
        double end = selected.Max(c => c.StartBeat + c.LengthBeats);

        var track = Clone(sourceTrack);
        track.Clips = selected.Select(Clone).ToList();
        foreach (var c in track.Clips) c.StartBeat -= start;
        track.UseStepSequencer = false;
        track.Frozen = false;
        track.FrozenBackupJson = null;
        track.FrozenSourcePath = null;

        var pcm = engine.Render(RenderProject(project, track));
        int wantedFrames = Math.Min(pcm.Length / AudioEngine.Channels,
            Math.Max(1, (int)Math.Ceiling((end - start) * 60.0 / Math.Max(1.0, project.Tempo) * AudioEngine.SampleRate) + AudioEngine.SampleRate));
        pcm = pcm.Take(wantedFrames * AudioEngine.Channels).ToArray();

        string path = NewRenderPath(project, projectPath, sourceTrack.Name + " Consolidated");
        WriteWav24(path, pcm);
        sourceTrack.Clips.RemoveAll(c => selectedIds.Contains(c.Id));
        var consolidated = new ProjectClip
        {
            Type = ClipType.Audio,
            Name = sourceTrack.Name + " (Consolidated)",
            SourcePath = path,
            StartBeat = start,
            LengthBeats = Math.Max(.25, end - start),
            SourceTempo = project.Tempo,
            WarpEnabled = false
        };
        sourceTrack.Clips.Add(consolidated);
        return consolidated;
    }

    public static void FreezeTrack(StudioProject project, Track track, AudioEngine engine, string? projectPath)
    {
        if (track.Frozen) throw new InvalidOperationException("Track is already frozen.");
        string backup = JsonSerializer.Serialize(track, JsonOptions);
        var isolated = Clone(track);
        isolated.Frozen = false;
        isolated.FrozenBackupJson = null;
        isolated.FrozenSourcePath = null;

        var pcm = engine.Render(RenderProject(project, isolated));
        string path = NewRenderPath(project, projectPath, track.Name + " Freeze");
        WriteWav24(path, pcm);
        double beats = Math.Max(.25, PcmBeats(pcm, project.Tempo));

        track.Clips = new List<ProjectClip>
        {
            new()
            {
                Type = ClipType.Audio,
                Name = track.Name + " (Frozen)",
                SourcePath = path,
                StartBeat = 0,
                LengthBeats = beats,
                SourceTempo = project.Tempo,
                WarpEnabled = false
            }
        };
        track.Devices.Clear();
        track.Automation.Clear();
        track.UseStepSequencer = false;
        track.Frozen = true;
        track.FrozenSourcePath = path;
        track.FrozenBackupJson = backup;
    }

    public static void UnfreezeTrack(StudioProject project, Track frozenTrack)
    {
        if (!frozenTrack.Frozen || string.IsNullOrWhiteSpace(frozenTrack.FrozenBackupJson))
            throw new InvalidOperationException("This track has no recoverable freeze backup.");
        var restored = JsonSerializer.Deserialize<Track>(frozenTrack.FrozenBackupJson, JsonOptions)
            ?? throw new InvalidDataException("The freeze backup is invalid.");
        int index = project.Tracks.IndexOf(frozenTrack);
        if (index < 0) throw new InvalidOperationException("Track is not part of the current project.");
        project.Tracks[index] = restored;
    }

    public static void FlattenTrack(Track track)
    {
        if (!track.Frozen) throw new InvalidOperationException("Track is not frozen.");
        track.Frozen = false;
        track.FrozenBackupJson = null;
        track.FrozenSourcePath = null;
        track.Type = TrackType.Audio;
    }

    private static StudioProject RenderProject(StudioProject original, Track track)
    {
        return new StudioProject
        {
            Name = original.Name + " Render",
            Tempo = original.Tempo,
            Key = original.Key,
            BeatsPerBar = original.BeatsPerBar,
            MetronomeEnabled = false,
            GlobalAutomation = Clone(original.GlobalAutomation),
            Tracks = new List<Track> { track }
        };
    }

    private static string NewRenderPath(StudioProject project, string? projectPath, string stem)
    {
        string root = !string.IsNullOrWhiteSpace(projectPath)
            ? Path.Combine(Path.GetDirectoryName(projectPath!)!, "Media", "Renders")
            : Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments), "LemmingsStudio", "Renders", Safe(project.Name));
        Directory.CreateDirectory(root);
        return Path.Combine(root, $"{Safe(stem)}_{DateTime.Now:yyyyMMdd_HHmmss_fff}.wav");
    }

    private static string Safe(string value)
    {
        foreach (char c in Path.GetInvalidFileNameChars()) value = value.Replace(c, '_');
        return string.IsNullOrWhiteSpace(value) ? "Render" : value;
    }

    private static double PcmBeats(float[] pcm, double tempo)
        => (pcm.Length / (double)AudioEngine.Channels / AudioEngine.SampleRate) * Math.Max(1.0, tempo) / 60.0;

    private static void WriteWav24(string path, float[] pcm)
    {
        var provider = new BufferProvider(pcm);
        WaveFileWriter.CreateWaveFile(path, new SampleToWaveProvider24(provider));
    }

    private static T Clone<T>(T value)
        => JsonSerializer.Deserialize<T>(JsonSerializer.Serialize(value, JsonOptions), JsonOptions)!;

    private sealed class BufferProvider : ISampleProvider
    {
        private readonly float[] data;
        private int position;
        public BufferProvider(float[] data) { this.data = data; WaveFormat = WaveFormat.CreateIeeeFloatWaveFormat(AudioEngine.SampleRate, AudioEngine.Channels); }
        public WaveFormat WaveFormat { get; }
        public int Read(float[] buffer, int offset, int count)
        {
            int n = Math.Min(count, data.Length - position);
            if (n <= 0) return 0;
            Array.Copy(data, position, buffer, offset, n);
            position += n;
            return n;
        }
    }
}
