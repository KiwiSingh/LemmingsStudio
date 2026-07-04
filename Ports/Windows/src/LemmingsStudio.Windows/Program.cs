namespace LemmingsStudio.Windows;

internal static class Program
{
    [STAThread]
    private static void Main()
    {
        ApplicationConfiguration.Initialize();
        using (var splash = new StartupSplashForm())
        {
            splash.ShowDialog();
        }
        Application.Run(new MainForm());
    }
}
