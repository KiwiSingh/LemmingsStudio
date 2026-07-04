using System.Runtime.InteropServices;

namespace LemmingsStudio.Windows;

internal static class DisplayRefreshRateDetector
{
    private const int ENUM_CURRENT_SETTINGS = -1;
    private const int CCHDEVICENAME = 32;
    private const int CCHFORMNAME = 32;

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
    private struct DEVMODE
    {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = CCHDEVICENAME)] public string dmDeviceName;
        public ushort dmSpecVersion;
        public ushort dmDriverVersion;
        public ushort dmSize;
        public ushort dmDriverExtra;
        public uint dmFields;
        public int dmPositionX;
        public int dmPositionY;
        public uint dmDisplayOrientation;
        public uint dmDisplayFixedOutput;
        public short dmColor;
        public short dmDuplex;
        public short dmYResolution;
        public short dmTTOption;
        public short dmCollate;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = CCHFORMNAME)] public string dmFormName;
        public ushort dmLogPixels;
        public uint dmBitsPerPel;
        public uint dmPelsWidth;
        public uint dmPelsHeight;
        public uint dmDisplayFlags;
        public uint dmDisplayFrequency;
    }

    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    private static extern bool EnumDisplaySettings(string? deviceName, int modeNum, ref DEVMODE devMode);

    public static int DetectPrimaryRefreshRate(int fallback = 60)
    {
        try
        {
            var mode = new DEVMODE();
            mode.dmSize = (ushort)Marshal.SizeOf<DEVMODE>();
            if (EnumDisplaySettings(null, ENUM_CURRENT_SETTINGS, ref mode))
            {
                var hz = (int)mode.dmDisplayFrequency;
                if (hz >= 23 && hz <= 500) return hz;
            }
        }
        catch { }
        return fallback;
    }

    public static int NearestSupported(int detected, IEnumerable<int> supported, int fallback = 60)
    {
        var values = supported.Where(v => v > 0).Distinct().OrderBy(v => v).ToList();
        if (values.Count == 0) return fallback;
        return values.OrderBy(v => Math.Abs(v - detected)).ThenBy(v => v).FirstOrDefault(fallback);
    }
}
