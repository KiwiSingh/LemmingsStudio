# Buildfix190 — Text-Safe Delete + First-Run Model Request Hardening

## Fixes

### 1. Backspace/Delete no longer steals text input from AI tabs

Buildfix189 correctly scoped delete to the Arrangement workspace, but the global AppKit key monitor still allowed delete routing when the main workspace remained Arrangement while focus had moved into a SwiftUI text editor in the agentic AI/sidebar area.

Buildfix190 treats focused AppKit/SwiftUI text entry as authoritative:

- `NSTextView` field editors keep Backspace/Delete.
- `NSTextField`/`SecureField` keep Backspace/Delete.
- Controls with an active field editor keep Backspace/Delete.
- Class-name fallback covers SwiftUI/AppKit text wrappers.
- Arrangement clip/track deletion still works when no text editor owns focus.

This protects:

- Agentic AI prompt boxes
- General chat prompt boxes
- Claude API key field
- Ollama model directory field
- Splice search fields
- Any other regular text field in the main app window

### 2. Ollama/model requests are hardened for first run

First-run local model requests could fail or time out because the Ollama server may be reachable before the selected model is installed or fully loaded.

Buildfix190 adds:

- generation preflight that starts/ensures the Ollama server;
- selected-model install check before generation;
- automatic pull if the selected model is missing;
- longer generation timeout for cold model loads;
- `keep_alive: 10m` to avoid immediately unloading the model;
- one retry after transient connection/timeout/server-start errors.

Claude requests now also set an explicit timeout and report non-200 API responses instead of trying to parse them as successful responses.

## Changed files

- `Sources/LemmingsStudio/App/App.swift`
- `Sources/LemmingsStudio/Generative/Ollama.swift`
- `Sources/LemmingsStudio/Generative/LLM.swift`
