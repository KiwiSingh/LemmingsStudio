using System.Text.Json;

namespace LemmingsStudio.Windows;

public static class ProjectIO
{
    private static readonly JsonSerializerOptions Options = new()
    {
        WriteIndented = true,
        PropertyNameCaseInsensitive = true
    };

    public static void Save(string path, StudioProject project)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(path) ?? Environment.CurrentDirectory);
        File.WriteAllText(path, JsonSerializer.Serialize(project, Options));
    }

    public static StudioProject Load(string path)
    {
        var json = File.ReadAllText(path);
        var project = JsonSerializer.Deserialize<StudioProject>(json, Options) ?? StudioProject.New();
        if (string.IsNullOrWhiteSpace(project.Name) || project.Name == "Untitled")
            project.Name = Path.GetFileNameWithoutExtension(path);
        project.GlobalAutomation ??= new List<AutomationLane>();
        project.Tracks ??= new List<Track>();
        return project;
    }
}
