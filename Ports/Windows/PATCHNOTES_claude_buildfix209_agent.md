# LemmingsStudio Windows — buildfix209 (Claude): agentic AI producer (mirrors the Mac build)

Ports the macOS AIAssistant + AssistantExecutor so the Windows build can take a natural-language
request and actually edit the project, not just chat.

## `Features/AIAssistant.cs`
- **AIAssistant.RunAsync(prompt, project, model)** — sends the same producer system prompt +
  a project-state summary to Ollama, asks for a JSON plan `{"summary",[ops]}`, and parses it
  into typed ops. Mirrors the Mac op schema:
  `add_notes, set_clip_length, clear_clip, transpose, quantize, humanize, add_device,
  set_param, set_tempo`.
- **Deterministic fallback** — when the model doesn't return clean JSON, the same chord /
  bassline / melody generators from the Mac build kick in (progression by major/minor,
  scale-correct thirds, nearest-MIDI voicing), so a musical result still lands.
- **KeyInfo** parses the Windows project's `Key` string ("C minor", "A# major") into root
  pitch-class + scale intervals (the Mac had `project.scale`/`keyRoot` natively).

## `AssistantExecutor`
- Applies the typed ops to the Windows model: creates clips on demand, converts note velocity
  from the Mac's 0..1 float to the Windows `MidiNote` 0..127 int, extends clip length to fit,
  transpose/quantize/humanize via record `with` rewrites, add_device from the stock catalog
  (with Mac aliases like "EQ Eight" → "EQ Three"), and set_param into `DeviceSlot.Parameters`.

## AI tab
- New **Run Agent ⚡** button: plans → applies → shows the summary and a per-op log, then
  refreshes the UI (arrangement, devices, mixer) so edits appear immediately.

## Honest scope
- Supported ops match what the Windows model can represent. `set_automation` and
  `set_drum_groove` from the Mac are intentionally omitted for now (the Windows automation/drum
  models differ); everything else is ported.
- The deterministic generators are the musical fallback; the Mac's full prose/grid note parser
  isn't ported yet (JSON ops + generators cover the common cases).
- Authored on Linux without the .NET toolchain — brace-balanced, standard System.Text.Json /
  records; expect at most minor fixups on first Windows build.
