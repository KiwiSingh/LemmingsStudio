using System.Text.Json;

namespace LemmingsStudio.Windows;

public static class ProjectIO
{
    private static readonly JsonSerializerOptions Options = new()
    {
        WriteIndented = true,
        PropertyNameCaseInsensitive = true
    };

    public static void Save(string path, StudioProject project) => SaveAtomic(path, project);

    public static void SaveAtomic(string path, StudioProject project)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(path) ?? Environment.CurrentDirectory);
        var temp = path + ".tmp";
        var backup = path + ".bak";
        var json = JsonSerializer.Serialize(project, Options);
        File.WriteAllText(temp, json);
        // Verify the just-written payload before replacing the user's project file.
        _ = JsonSerializer.Deserialize<StudioProject>(File.ReadAllText(temp), Options)
            ?? throw new InvalidDataException("Project serialization verification failed.");
        if (File.Exists(path))
        {
            try { File.Replace(temp, path, backup, ignoreMetadataErrors: true); }
            catch { File.Copy(path, backup, true); File.Move(temp, path, true); }
        }
        else File.Move(temp, path, true);
    }

    public static StudioProject Load(string path)
    {
        var json = File.ReadAllText(path);
        var project = JsonSerializer.Deserialize<StudioProject>(json, Options) ?? StudioProject.New();
        if (string.IsNullOrWhiteSpace(project.Name) || project.Name == "Untitled")
            project.Name = Path.GetFileNameWithoutExtension(path);
        project.GlobalAutomation ??= new List<AutomationLane>();
        project.Tracks ??= new List<Track>();
        project.ReturnBuses ??= new List<ReturnBus>();
        if (project.ReturnBuses.Count == 0)
        {
            project.ReturnBuses.Add(new ReturnBus { Name = "Return A", ColorHex = "#9A78F5" });
            project.ReturnBuses.Add(new ReturnBus { Name = "Return B", ColorHex = "#58C7B6" });
        }
        foreach (var track in project.Tracks)
            track.Sends ??= new Dictionary<Guid, float>();
        return project;
    }
}
