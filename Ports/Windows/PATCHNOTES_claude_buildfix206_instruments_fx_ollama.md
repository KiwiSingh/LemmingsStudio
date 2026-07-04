# LemmingsStudio Windows — buildfix206 (Claude): Bit Crusher, Oscillatron, LemmingBass + Ollama

Ports three more devices from the Mac build and brings the local-AI (Ollama) integration to
the Windows port.

## Instruments (MIDI synths, selected by device name)
`AudioEngine.RenderMidiClip` now dispatches per track instrument:
- **Oscillatron** — three detuned saw oscillators + a sub sine through a low-pass and AR
  envelope (rich, wide). Params: Cutoff, Detune, Sub.
- **LemmingBass** — sine+square-blend osc + sub sine + a click transient ("Punch") → tanh
  drive → low-pass (deep mono bass). Params: Cutoff, Drive, Sub, Punch, Wave.
- The original stock synth remains the default. Add Oscillatron/LemmingBass from the Devices
  tab to switch a track's voice.

## Effect: Bit Crusher (Redux)
The device chain is now a real multi-effect series. New **Bit Crusher**: amplitude
bit-depth reduction (Bits) + sample-rate sample-and-hold (Downsample), with dry/wet. Joins
**Auto Filter** (Cutoff) and **Saturator** (Drive), all applied in order to **both audio and
MIDI** clips on the track.

## Local AI — Ollama (was missing on Windows)
- `Features/OllamaClient.cs` — C# port of the Mac client: talks to `http://127.0.0.1:11434`,
  lists installed models, pulls a model with progress, and generates text. Strips `<think>`
  reasoning blocks and falls back from `/api/generate` to `/api/chat`. Recommends a model by
  system RAM (GlobalMemoryStatusEx).
- `Features/AIPanel.cs` + a new **AI** tab: Check Server, Refresh/Pull models, prompt →
  Generate. Clear guidance if Ollama isn't installed/running.

## Catalog + UI
- Devices tab gains **Oscillatron**, **LemmingBass**, and **Bit Crusher** in **Add Device ▾**.

## Honest scope
- EQ/Comp/Reverb/Delay/Utility are still model-only (stored, not yet processed). Oscillatron/
  LemmingBass are faithful-character approximations of the Mac synths, not sample-exact ports.
- Ollama must be installed and running locally (ollama.com); the panel detects and guides.
- Authored on Linux without the .NET toolchain — brace-balanced, standard WinForms/NAudio/
  HttpClient APIs; expect at most minor fixups on first Windows build.
