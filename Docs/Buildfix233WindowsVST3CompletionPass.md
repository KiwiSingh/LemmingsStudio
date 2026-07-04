# Buildfix233 Windows VST3 completion pass

Buildfix233 extends the buildfix230-232 native Windows VST3 host work.

The main design decision remains: third-party VST3 plug-ins live in `LemmingsVst3Host.exe`, outside the WinForms process. The C# app communicates through JSONL control messages. For large PCM render requests, buildfix233 switches from inline base64 to temporary file-backed float32 PCM transport.

Implemented commands:

- `getParameters`
- `setParameter`
- `getState`
- `setState`
- `getInfo`
- `getPrograms`
- `setProgram`
- `renderMidi`
- `processAudio`

Large render requests may use:

- request: `pcmFile`
- response: `pcmFile`

Small requests may continue using inline `pcm` base64.

Automation payloads use normalized values:

```json
{ "frame": 2048, "paramId": "cutoff", "index": 3, "value": 0.72 }
```

The helper applies automation at block boundaries before processing that block. This is much better than clip-only automation and safe for export, but it is not yet per-sample automation.
