# LemmingsStudio Windows — buildfix213 (Claude): AIFF compile fix + robust Inno Setup detection

## Fix 1 — AIFF export compile error (CS1503)
`AiffFileWriter.CreateAiffFile(path, IWaveProvider)` doesn't exist — that overload wants a
`WaveStream`, but `SampleToWaveProvider24/16` are `IWaveProvider`. Switched `WriteAiff` to the
instance writer and pump the buffer:
```csharp
using var writer = new AiffFileWriter(path, wp.WaveFormat);
var buffer = new byte[wp.WaveFormat.AverageBytesPerSecond];
int read;
while ((read = wp.Read(buffer, 0, buffer.Length)) > 0)
    writer.Write(buffer, 0, read);
```
WAV/MP3/FLAC paths were unaffected; AIFF now compiles and writes 16/24-bit PCM.

## Fix 2 — Inno Setup not detected even when installed
The old check only looked at two hardcoded `Inno Setup 6` paths. Now it also:
- globs version-agnostic locations incl. **user-scope** winget installs
  (`%LOCALAPPDATA%\Programs\Inno Setup*`, the WinGet Packages dir),
- falls back to `ISCC` on PATH,
- and reads the **registry** uninstall keys (machine + user) for Inno Setup's `InstallLocation`.
It also prints the resolved `ISCC.exe` path, and you can always override with
`-InnoSetupPath 'C:\path\to\ISCC.exe'`.
