# LemmingsStudio Windows — buildfix205 (Claude): instrument rack + latency port, GitHub Actions removed

Ports the macOS instrument-rack UI and the audio-latency control to the Windows build, and
removes the GitHub Actions pipeline entirely per request.

## Instrument rack (new `Features/DeviceRackPanel.cs` + "Devices" tab)
- New **Devices** tab: pick a track, **Add Device ▾** from a stock catalog (Auto Filter,
  Saturator, EQ Three, Compressor, Reverb, Delay, Utility), tweak per-parameter sliders,
  toggle **On**, or **Remove** — the Windows analogue of the Mac Ableton-style insert chain.
- Edits write straight into the project model (`DeviceSlot.Parameters`), so they save/load and
  can drive automation.
- **Made audible, not cosmetic:** the engine now applies the first enabled device's **Cutoff**
  (one-pole low-pass) and **Drive** (tanh saturation) to **audio clips** too (the synth already
  used them for MIDI). So Auto Filter / Saturator immediately change playback.

## Latency control (engine + transport)
- `AudioEngine.OutputLatencyMs` (default 200) replaces the hard-coded WaveOut latency.
- Transport bar gains a **Latency** dropdown (50/100/150/200/300 ms). Lower = snappier,
  higher = safer against dropouts (handy inside a VM). Applies on next Play.

## GitHub Actions removed
- Deleted `.github/` (both `windows-port.yml` and `windows-installer.yml`).
- Scrubbed Actions/workflow references from `README.md`, `WindowsPortPlan.md`, and the build
  guide. Building is now purely local.

## Beginner build guide — Parallels only
- Rewrote **Docs/WindowsBuildForNoobs.md** for a total beginner working **only inside
  Parallels** (Windows 11 ARM): install 3 tools with winget, `cd`, one build line
  (`-Backend cpu -Runtime win-arm64 -SkipInstaller`), run the .exe. Includes the new Devices
  tab + Latency tour and the external-drive note.

## Honest scope
- Of the stock devices, only **Cutoff** (Auto Filter) and **Drive** (Saturator) are processed
  by the offline engine today; EQ/Comp/Reverb/Delay params are stored and will become audible
  as more DSP is ported. VST/AU hosting (the Mac external-plugin cards) remains a later native
  layer, not part of this offline engine.
- Authored on Linux without the .NET toolchain: brace-balanced and standard WinForms/NAudio
  APIs, but expect at most minor fixups on first Windows build.
