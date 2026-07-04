# LemmingsStudio Windows — buildfix207 (Claude): full effect rack live + Ollama Windows-hardened

## Whole rack is now audible
`AudioEngine.ApplyDeviceChain` processes every stock effect in chain order, on both audio and
MIDI clips:
- **EQ Three** — 3-band (low 250 Hz / mid / high 3.5 kHz) gains + output gain (0.5 = unity).
- **Compressor** — envelope-follower feed-forward comp (threshold/ratio/attack/release/makeup).
- **Reverb** — Freeverb-lite: 4 comb filters + 1 all-pass per channel (size/decay/wet), with a
  small L/R offset for width.
- **Delay** — per-channel feedback delay (time/feedback/wet).
- **Utility** — gain, mid/side stereo width, and equal-power pan.
- These join the existing **Auto Filter**, **Saturator**, **Bit Crusher**, and the
  **Oscillatron** / **LemmingBass** instruments.

## Ollama — made Windows-correct
`Features/OllamaClient.cs` hardened for Windows specifically:
- **Proxy bypass** (`UseProxy=false`): a configured system/corporate proxy otherwise
  intercepts even 127.0.0.1 calls and makes the local daemon look offline.
- **Explicit IPv4 `127.0.0.1`** (never "localhost"): avoids Windows resolving to IPv6 `::1`
  first while Ollama is bound to IPv4 — the classic localhost stall.
- **`EnsureServerAsync`**: if the daemon isn't up, launches `ollama serve` (on PATH after the
  Windows installer) and polls. The AI tab's **Check Server** now auto-starts it.
- Streaming pulls use `ResponseHeadersRead` so a long download isn't killed by the request
  timeout; generate timeout raised to 10 min.
- Ollama's REST API is identical across platforms, so list/pull/generate, `<think>`-stripping,
  and the `/api/generate`→`/api/chat` fallback all work unchanged.

## Honest scope
- Effects run per-clip (each clip gets its own effect instance), so reverb/delay tails don't
  bleed across clip boundaries — fine for offline bouncing, a per-track effect bus is a later
  refinement.
- DSP are clean, characterful implementations (not emulations of specific hardware).
- Authored on Linux without the .NET toolchain — brace-balanced, standard WinForms/NAudio/
  HttpClient APIs; expect at most minor fixups on first Windows build.
