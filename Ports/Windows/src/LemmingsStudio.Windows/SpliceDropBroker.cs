using LemmingsStudio.Windows.Features;

namespace LemmingsStudio.Windows;

public sealed class SpliceDropAsset
{
    public string Name { get; init; } = "Splice Sample";
    public string FilePath { get; init; } = "";
    public double? Bpm { get; init; }
    public double? DurationSeconds { get; init; }
    public string Key { get; init; } = "";
    public string Type { get; init; } = "";
}

public static class SpliceDropBroker
{
    public const string DataFormat = "LemmingsStudio.SpliceSample";
    public static Func<SpliceSample, Task<SpliceDropAsset?>>? Resolver { get; set; }

    public static Task<SpliceDropAsset?> ResolveAsync(SpliceSample sample)
        => Resolver?.Invoke(sample) ?? Task.FromResult<SpliceDropAsset?>(null);
}
