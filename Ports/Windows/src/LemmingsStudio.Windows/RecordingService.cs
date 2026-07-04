using NAudio.CoreAudioApi;
using NAudio.Wave;

namespace LemmingsStudio.Windows;

public enum AudioInputBackend { WinMM, WasapiShared, WasapiExclusive }
public enum InputMonitoringMode { Off, Software, HardwareDirect }

public sealed class AudioInputDescriptor
{
    public AudioInputBackend Backend { get; init; }
    public int Index { get; init; }
    public string Name { get; init; } = "Audio Input";
    public override string ToString() => Name;
}

public sealed class RecordingService : IDisposable
{
    public event Action<string>? Log;
    public event Action<float>? LevelChanged;

    private IWaveIn? input;
    private WaveFileWriter? writer;
    private WaveOutEvent? monitorOut;
    private BufferedWaveProvider? monitorBuffer;
    private readonly object sync = new();
    private string? recordingPath;
    private DateTime recordingStartedUtc;
    private WaveFormat? activeFormat;

    public bool IsRecording => input != null;
    public string? CurrentPath => recordingPath;
    public TimeSpan Elapsed => IsRecording ? DateTime.UtcNow - recordingStartedUtc : TimeSpan.Zero;
    public WaveFormat? ActiveFormat => activeFormat;

    public IReadOnlyList<AudioInputDescriptor> Inputs(AudioInputBackend backend)
    {
        var list = new List<AudioInputDescriptor>();
        if (backend == AudioInputBackend.WinMM)
        {
            for (int i = 0; i < WaveIn.DeviceCount; i++)
            {
                try
                {
                    var caps = WaveIn.GetCapabilities(i);
                    list.Add(new AudioInputDescriptor { Backend = backend, Index = i, Name = string.IsNullOrWhiteSpace(caps.ProductName) ? $"WinMM Input {i}" : $"{caps.ProductName}  [WinMM]" });
                }
                catch { list.Add(new AudioInputDescriptor { Backend = backend, Index = i, Name = $"WinMM Input {i}" }); }
            }
            return list;
        }

        try
        {
            using var mm = new MMDeviceEnumerator();
            var endpoints = mm.EnumerateAudioEndPoints(DataFlow.Capture, DeviceState.Active).ToList();
            for (int i = 0; i < endpoints.Count; i++)
            {
                var name = endpoints[i].FriendlyName;
                var tag = backend == AudioInputBackend.WasapiExclusive ? "WASAPI exclusive" : "WASAPI shared";
                list.Add(new AudioInputDescriptor { Backend = backend, Index = i, Name = $"{name}  [{tag}]" });
            }
        }
        catch (Exception ex) { Log?.Invoke("WASAPI input enumeration failed: " + ex.Message); }
        return list;
    }

    public IReadOnlyList<string> InputNames() => Inputs(AudioInputBackend.WinMM).Select(i => i.Name).ToList();

    public string Start(AudioInputBackend backend, int deviceIndex, string destinationPath, InputMonitoringMode monitoring, int monitorLatencyMs = 80)
    {
        if (IsRecording) throw new InvalidOperationException("Audio recording is already running.");
        Directory.CreateDirectory(Path.GetDirectoryName(destinationPath)!);
        recordingPath = destinationPath;

        input = CreateInput(backend, deviceIndex, monitorLatencyMs);
        activeFormat = input.WaveFormat;
        writer = new WaveFileWriter(destinationPath, activeFormat);

        if (monitoring == InputMonitoringMode.Software)
        {
            monitorBuffer = new BufferedWaveProvider(activeFormat)
            {
                BufferDuration = TimeSpan.FromSeconds(3),
                DiscardOnBufferOverflow = true
            };
            monitorOut = new WaveOutEvent { DesiredLatency = Math.Clamp(monitorLatencyMs, 25, 300) };
            monitorOut.Init(monitorBuffer);
            monitorOut.Play();
            Log?.Invoke($"Software input monitoring enabled ({monitorLatencyMs} ms target latency). Use headphones to avoid feedback.");
        }
        else if (monitoring == InputMonitoringMode.HardwareDirect)
        {
            // Windows does not expose a universal DAW-safe switch for direct monitoring.
            // On interfaces that provide it, this must be enabled in the driver/control panel.
            Log?.Invoke("Hardware/direct monitoring selected: LemmingsStudio will not echo the input in software. Enable direct monitoring in your audio interface/Windows mixer if supported.");
        }

        input.DataAvailable += OnDataAvailable;
        input.RecordingStopped += OnRecordingStopped;
        recordingStartedUtc = DateTime.UtcNow;
        input.StartRecording();
        Log?.Invoke($"Audio recording started via {backend}: {Path.GetFileName(destinationPath)} ({activeFormat.SampleRate} Hz, {activeFormat.Channels} ch, {activeFormat.Encoding}).");
        return destinationPath;
    }

    // Back-compat path used by older panels/scripts.
    public string Start(int deviceIndex, string destinationPath, bool monitor, int monitorLatencyMs = 80)
        => Start(AudioInputBackend.WinMM, deviceIndex, destinationPath, monitor ? InputMonitoringMode.Software : InputMonitoringMode.Off, monitorLatencyMs);

    private static IWaveIn CreateInput(AudioInputBackend backend, int deviceIndex, int latencyMs)
    {
        latencyMs = Math.Clamp(latencyMs, 10, 500);
        if (backend == AudioInputBackend.WinMM)
        {
            if (deviceIndex < 0 || deviceIndex >= WaveIn.DeviceCount) throw new ArgumentOutOfRangeException(nameof(deviceIndex));
            return new WaveInEvent
            {
                DeviceNumber = deviceIndex,
                WaveFormat = new WaveFormat(AudioEngine.SampleRate, 16, AudioEngine.Channels),
                BufferMilliseconds = Math.Clamp(latencyMs, 20, 250),
                NumberOfBuffers = 3
            };
        }

        using var mm = new MMDeviceEnumerator();
        var endpoints = mm.EnumerateAudioEndPoints(DataFlow.Capture, DeviceState.Active).ToList();
        if (deviceIndex < 0 || deviceIndex >= endpoints.Count) throw new ArgumentOutOfRangeException(nameof(deviceIndex));
        var device = endpoints[deviceIndex];
        var exclusive = backend == AudioInputBackend.WasapiExclusive;
        try
        {
            return CreateWasapiCapture(device, exclusive, latencyMs);
        }
        catch when (exclusive)
        {
            // Some drivers refuse exclusive capture unless the requested format is exact.
            // Fall back to shared so recording still works, but surface it through logging after Start.
            return CreateWasapiCapture(device, false, latencyMs);
        }
    }

    private static WasapiCapture CreateWasapiCapture(MMDevice device, bool exclusive, int latencyMs)
    {
        var ctor = typeof(WasapiCapture).GetConstructor(new[] { typeof(MMDevice), typeof(AudioClientShareMode), typeof(bool), typeof(int) });
        if (ctor != null)
        {
            var shareMode = exclusive ? AudioClientShareMode.Exclusive : AudioClientShareMode.Shared;
            return (WasapiCapture)ctor.Invoke(new object[] { device, shareMode, true, latencyMs });
        }
        // NAudio builds without the explicit share-mode constructor still provide WASAPI shared capture.
        return new WasapiCapture(device, true, latencyMs);
    }

    public string? Stop()
    {
        if (input == null) return recordingPath;
        try { input.StopRecording(); }
        catch (Exception ex) { Log?.Invoke("Audio recording stop failed: " + ex.Message); CleanupInputOnly(); }
        return recordingPath;
    }

    private void OnDataAvailable(object? sender, WaveInEventArgs e)
    {
        lock (sync)
        {
            writer?.Write(e.Buffer, 0, e.BytesRecorded);
            writer?.Flush();
            monitorBuffer?.AddSamples(e.Buffer, 0, e.BytesRecorded);
        }
        LevelChanged?.Invoke(EstimatePeak(e.Buffer, e.BytesRecorded, activeFormat));
    }

    private static float EstimatePeak(byte[] buffer, int bytes, WaveFormat? format)
    {
        if (bytes <= 0) return 0f;
        if (format?.Encoding == WaveFormatEncoding.IeeeFloat && format.BitsPerSample == 32)
        {
            float peak = 0f;
            for (int i = 0; i + 3 < bytes; i += 4)
                peak = Math.Max(peak, Math.Abs(BitConverter.ToSingle(buffer, i)));
            return Math.Clamp(peak, 0f, 1f);
        }
        if (format?.BitsPerSample == 24)
        {
            float peak = 0f;
            for (int i = 0; i + 2 < bytes; i += 3)
            {
                int sample = buffer[i] | (buffer[i + 1] << 8) | (buffer[i + 2] << 16);
                if ((sample & 0x800000) != 0) sample |= unchecked((int)0xFF000000);
                peak = Math.Max(peak, Math.Abs(sample / 8388608f));
            }
            return Math.Clamp(peak, 0f, 1f);
        }
        float p = 0f;
        for (int i = 0; i + 1 < bytes; i += 2)
            p = Math.Max(p, Math.Abs(BitConverter.ToInt16(buffer, i) / 32768f));
        return Math.Clamp(p, 0f, 1f);
    }

    private void OnRecordingStopped(object? sender, StoppedEventArgs e)
    {
        CleanupInputOnly();
        if (e.Exception != null) Log?.Invoke("Audio recording stopped with error: " + e.Exception.Message);
        else Log?.Invoke("Audio recording stopped.");
    }

    private void CleanupInputOnly()
    {
        lock (sync)
        {
            if (input != null)
            {
                input.DataAvailable -= OnDataAvailable;
                input.RecordingStopped -= OnRecordingStopped;
                input.Dispose();
                input = null;
            }
            writer?.Dispose();
            writer = null;
            monitorOut?.Stop();
            monitorOut?.Dispose();
            monitorOut = null;
            monitorBuffer = null;
            activeFormat = null;
        }
    }

    public void Dispose() => Stop();
}
