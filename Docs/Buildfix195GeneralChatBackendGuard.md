# Buildfix195 — General Chat backend guard

Fixes a regression where the normal Chat tab could look broken even though the shared LLM backend worked elsewhere.

## Fixes

- General Chat now protects its prompt field like the Agentic AI prompt so global Backspace/Delete handling will not steal text editing.
- The Chat ask button now flips `working` on the main actor explicitly.
- Empty/blank Ollama model tags are now normalized to the recommended local model before constructing the backend.
- The selected Ollama model tag is persisted when the default is auto-filled.
- Ollama generation now fails fast with a clear message if a blank model tag ever reaches the client instead of timing out or blocking mysteriously.
- Claude API keys are trimmed before backend construction so pasted whitespace/newlines do not create confusing auth failures.

## Expected behavior

- Chat tab answers normal questions using the selected backend.
- First run with Local Ollama should either pull/use the selected model or show a clear setup error.
- Backspace in the Chat prompt edits text; it does not delete Arrangement clips/tracks.
