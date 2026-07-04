# Buildfix 146 — AI Backend Cleanup, General Chat, Voice AI Sanity

## Scope guard

This buildfix intentionally does **not** touch the recording implementation, code-signing/build signing fixes, Splice MCP/download/preview code, or the recent Claude Serum/Serum 2/hosted plug-in fixes.

## AI backend cleanup

- Removed the old selectable deterministic/semantic fallback engine from the shared AI backend picker.
- Agentic AI surfaces now expose only:
  - Claude API
  - Local Ollama
- The internal offline backend remains only as a guard when Claude has no key, so the UI can show a useful warning instead of pretending an agent is active.

## General chatbot

- Added a regular Chat tab to the right dock.
- Chat uses the same selected backend as the agentic tools: Claude API or local Ollama.
- It answers normal production/workflow questions without emitting project-edit JSON.
- The chat prompt includes a lightweight project snapshot so users can ask things like mashup key planning, arrangement, mixing, and workflow questions.

## Voice AI sanity pass

- Replaced the previous `voice_transform.py` placeholder/copy behavior with a real local offline transform path.
- The bundled service now reads audio, applies a lightweight consent-first singing-voice profile, and writes a rendered WAV.
- Built-in starter voice entries now use `builtin://` profiles instead of invalid placeholder URLs.
- Imported model folders may optionally include `voice_profile.json` to steer pitch/tone/compression/room profile values.

## Files changed

- `Sources/LemmingsStudio/App/App.swift`
- `Sources/LemmingsStudio/Views/AIPanels.swift`
- `Sources/LemmingsStudio/Views/ProDAWShell.swift`
- `Sources/LemmingsStudio/Integration/VoiceModelRepository.swift`
- `Sources/LemmingsStudio/Resources/Services/voice_transform.py`
