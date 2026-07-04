# Buildfix196 — General Chat No Silent Hang

This patch hardens the general Chat model request path so it cannot look like the model simply never responds.

## Fixes

- Removed silent Ollama model pulls from `generate()`.
  - Missing models now fail fast with a clear instruction to use the AI engine picker’s Download button.
  - Explicit downloads still happen through the picker, where progress is visible.
- Added a visible pending chat bubble (`Thinking…`) that is replaced by the model response or error.
- Added hard generation timeout racing around Ollama requests.
- Added bounded retry for transient first-run/cold-run Ollama connection/timeout errors.
- Added a custom URLSession configuration with finite request/resource timeouts.
- Added `num_predict` limits so local models cannot keep generating forever.
- Cleaned leading `<think>...</think>` blocks when a thinking model returns them before the final answer.
- Ollama JSON/error payloads now surface their `error` field instead of looking like an empty/no-response failure.

## Files changed

- `Sources/LemmingsStudio/Generative/Ollama.swift`
- `Sources/LemmingsStudio/App/App.swift`
