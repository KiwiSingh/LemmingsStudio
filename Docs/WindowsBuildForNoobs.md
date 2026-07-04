# Building LemmingsStudio for Windows — complete-beginner guide (Parallels only)

This assumes you know **nothing** and that you're running Windows inside **Parallels
Desktop** on a Mac. Follow it top to bottom. Where it says "type this", type it into the
blue **PowerShell** window exactly, then press Enter.

There is **no GitHub / cloud step** here — everything builds and runs locally in your VM.

---

## Step 1 — Get Windows running in Parallels

1. Open **Parallels Desktop**. If you don't have a Windows VM yet, click **Install Windows**
   — Parallels downloads **Windows 11 ARM** automatically (your Mac is Apple Silicon, so it's
   the ARM edition; that's expected and fine).
2. Start the VM and wait for the Windows desktop.
3. Because it's Windows-on-ARM, the build "runtime" is **`win-arm64`**. We use that below.

> **External-drive tip:** if your VM lives on an external drive to save internal SSD space,
> that's fine — build on the VM's own `C:` drive (already on the external). Don't build across
> the `\\Mac\...` shared folder (slow/flaky), and stop the external drive from sleeping
> mid-build.

---

## Step 2 — Install the tools (one time)

Open PowerShell **as administrator**: click **Start**, type `powershell`, right-click
**Windows PowerShell**, choose **Run as administrator**, click **Yes**. Type these one at a
time, waiting for each to finish:

```powershell
winget install Microsoft.DotNet.SDK.8
winget install Python.Python.3.11
winget install Microsoft.PowerShell
```

- **.NET 8 SDK** — builds the app.
- **Python 3.11** — runs the AI stem splitter.
- **PowerShell 7** — the modern shell our scripts prefer.

(Optional, only if you want an installer `.exe`: `winget install JRSoftware.InnoSetup`.)

Now **close that window and open a brand-new PowerShell window** so it sees the new tools:

```powershell
dotnet --version
python --version
```

You should see version numbers. If you get "not recognized", restart Windows and re-open
PowerShell. If you later see "running scripts is disabled", run this once and answer `Y`:
```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

---

## Step 3 — Build and run the app

Copy the LemmingsStudio folder into your VM (e.g. into Documents), then go to the Windows
port folder — change the path to match where you put it:

```powershell
cd "$HOME\Documents\LemmingsStudio\Ports\Windows"
```

Build and launch (no installer, just run it):

```powershell
./build-windows.ps1 -Backend cpu -Runtime win-arm64 -SkipInstaller
.\artifacts\publish-win-arm64-cpu\LemmingsStudio.exe
```

That downloads NAudio, compiles the app, and launches it. **Use `-Backend cpu` inside
Parallels** — a VM has no real GPU/NPU, so CPU is the right choice.

> Want an installer `.exe` too? Install Inno Setup (Step 2) and drop `-SkipInstaller`. The
> finished `...-Setup.exe` lands in `artifacts\installer`.

---

## Step 4 — First-run tour

1. **Make sound:** drag a `.wav` from File Explorer onto a track in the **Arrangement** tab,
   then press **▶ Play**. **Export Audio…** bounces a file (WAV 16/24/32-bit, AIFF, plus
   MP3/FLAC when ffmpeg is available).
2. **Latency:** the transport bar has a **Latency** dropdown. Lower = snappier, but inside a
   VM you may hear dropouts — if so, raise it (200–300 ms). It applies on the next Play.
3. **Devices (instrument rack):** open the **Devices** tab, pick a track, click
   **Add Device ▾**, and tweak sliders. Audible today: instruments **Oscillatron** and
   **LemmingBass** (drop one on an instrument track to change its sound), and effects
   **Auto Filter**, **Saturator**, **Bit Crusher**, **EQ Three**, **Compressor**, **Reverb**,
   **Delay**, and **Utility** — all process audio now, in chain order.
4. **AI (Ollama):** open the **AI** tab, click **Check Server**. If Ollama isn't installed,
   it offers to **install it automatically** (via winget, or the official installer) — or use
   the **Install Ollama** button. Then pick a model (or **Pull Recommended**) and **Generate**.
   • **Run Agent ⚡** turns a plain-English request (e.g. *“add 4 bars of bass chords on
   the Bass track”*) into actual edits — it asks the model for a JSON plan and applies it to
   your project, falling back to a built-in chord/bass/melody generator if needed. It can also
   add **automation curves**, lay down **drum grooves** (Lo-Fi/Tech House/Slap House/EDM/
   Breakbeat), and read **note grids** like *“Bar 1: C2 - - - | E2 - G2 -”* straight from the model.
   • **Design Sound 🎛** turns a description (e.g. *“warm 80s synthwave pluck”*) into actual
   synth-parameter settings on a track's instrument (Oscillatron / LemmingBass / Stock Synth).

5. **Splice browser:** open the **Splice** tab, click **Connect Splice** (signs you in through
   your browser once), then search the Splice catalog by text + BPM. Select a result and
   **Add to Project** to download it (first download of a sample spends one Splice credit) and
   drop it onto a new audio track.
6. **Stem splitting (optional):** **Tools → Install / Repair CPU Backend** (needs internet,
   a few minutes), then select an audio clip and **Tools → Stem Split Selected Clip…**. Watch
   the **Log** tab.

---

## Picking a backend (only matters on real PCs, not Parallels)

Inside Parallels always use **`cpu`**. On real hardware later, use **Tools → Detect
Hardware…** and pick `cuda` (NVIDIA), `directml` (AMD/Intel GPU), `openvino` (Intel),
`qnn` (Snapdragon/Copilot+ NPU), or `cpu`. GPU/NPU flavors can't be exercised in a VM.

---

## If something breaks

- **"dotnet/python not recognized"** → open a fresh PowerShell window, or restart Windows.
- **"running scripts is disabled"** → `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`.
- **No sound in Parallels** → check the VM has an audio device (Parallels ▸ Devices) and
  Windows isn't muted; if playback stutters, raise the **Latency** dropdown.
- **MP3/FLAC export errors** → those need **ffmpeg**: `winget install Gyan.FFmpeg` (use a
  **win-arm64** ffmpeg build for the ARM VM), or drop `ffmpeg.exe` next to
  `LemmingsStudio.exe`. WAV/AIFF never need it.
