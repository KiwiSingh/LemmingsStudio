# Buildfix231 — Windows VST3 PCM streaming pass

This pass extends the native Windows VST3 helper beyond editor/live-MIDI testing.

## Added

- JSONL request/response IDs in `LemmingsVst3Host.exe`.
- Compact one-line JSON output from the helper so the C# bridge can parse JSONL reliably.
- `renderMidi` helper command:
  - accepts timestamped MIDI events,
  - renders the loaded VST3 instrument offline in blocks,
  - returns interleaved float32 PCM as base64.
- `processAudio` helper command:
  - accepts interleaved float32 PCM as base64,
  - processes the buffer through the loaded VST3 effect,
  - returns processed interleaved float32 PCM as base64.
- C# synchronous IPC request handling with timeouts and pending-response tracking.
- Windows `AudioEngine` now attempts native VST3 rendering for MIDI clips when the track instrument is VST3.
- Windows `AudioEngine` now attempts native VST3 effect processing in the device chain.
- Failure policy is dry/safety fallback rather than total render failure.

## Still not the final VST3 parity layer

This is the first real PCM bridge. It is intentionally block-based and simple so we can test correctness before optimizing. Follow-up work should add:

- persistent per-slot latency reporting/compensation,
- parameter enumeration and automation binding,
- preset/state save/restore,
- sidechain/bus layout negotiation,
- larger-buffer shared-memory transport if JSON/base64 proves too slow for big exports.
