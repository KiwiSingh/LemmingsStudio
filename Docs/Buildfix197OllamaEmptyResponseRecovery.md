# Buildfix 197 — Ollama Empty Response Recovery

Fixes the case where General Chat reports `The model returned an empty response` even though the request completed.

## Root cause

Buildfix196 correctly surfaced empty Ollama replies, but it also exposed a common thinking-model edge case:

- `/api/generate` can return a response that is only `<think>...</think>` with no visible final answer.
- The chat cleaner strips `<think>` blocks so internal reasoning is not shown.
- If the model returned only a thinking block, the cleaner produced an empty string.
- The UI then displayed `The model returned an empty response` without trying to recover.

## Fix

- Split Ollama request construction into reusable helpers.
- Keep the primary `/api/generate` call for normal generation.
- If a plain-text generation returns no visible answer, retry once through `/api/chat` with an explicit final-answer-only instruction.
- Keep the retry non-streaming, bounded, and capped with `num_predict`.
- If both `/api/generate` and `/api/chat` return no visible answer, show a clear actionable error instead of silently spinning or reporting a vague empty response.
- Continue stripping `<think>...</think>` when a real visible answer remains.

## Files changed

- `Sources/LemmingsStudio/Generative/Ollama.swift`
