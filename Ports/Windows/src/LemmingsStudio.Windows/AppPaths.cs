namespace LemmingsStudio.Windows;

public static class AppPaths
{
    public static string Root => Ensure(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "MagmaVance", "LemmingsStudio"));
    public static string Autosaves => Ensure(Path.Combine(Root, "Autosaves"));
    public static string Logs => Ensure(Path.Combine(Root, "Logs"));
    public static string Diagnostics => Ensure(Path.Combine(Root, "Diagnostics"));
    public static string UserProjects => Ensure(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments), "LemmingsStudio", "Projects"));
    public static string Recordings => Ensure(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments), "LemmingsStudio", "Recordings"));
    public static string Renders => Ensure(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments), "LemmingsStudio", "Renders"));
    public static string SpliceCache => Ensure(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments), "LemmingsStudio", "SpliceCache"));

    public static void EnsureFirstRunFolders()
    {
        _ = Root; _ = Autosaves; _ = Logs; _ = Diagnostics;
        _ = UserProjects; _ = Recordings; _ = Renders; _ = SpliceCache;
    }

    private static string Ensure(string path)
    {
        Directory.CreateDirectory(path);
        return path;
    }
}
