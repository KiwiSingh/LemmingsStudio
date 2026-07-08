# LemmingsStudio buildfix263 — release-prep AI/chat, sonic signature, and visionOS dual packaging

Public versions remain unchanged:
- macOS v2.0
- Windows v2.0
- visionOS v1.0

## macOS
- Dedicated chat-tuned Ollama model lane for the Chat pane.
- Sound Agent / AI Producer model selection remains separate.
- RAM-aware Qwen3 chat recommendation.
- Replicate Sonic Signature asks Stock Analog vs a named third-party target.
- Applies accessible parameters and requires manual instructions for inaccessible knobs/modes/routing/modulation/FX.

## Windows
- Separate chat model selector and chat-model pull button.
- General chat uses the dedicated chat model while agent/sound tasks keep their own model selection.
- Replicate Signature workflow for the selected Arrangement audio clip.
- Stock Analog vs loaded third-party/VST3 target choice.
- Agent notes must identify inaccessible controls and provide manual tweak instructions.

## visionOS distribution
- `package-simulator` mode produces a public Release simulator ZIP.
- `ipa` mode archives and exports a signed hardware IPA.
- Artifact names remain aligned with visionOS v1.0.

## Next steps for visionOS → macOS parity
1. Live integrated Mac Host Mode endpoints.
2. Streamed plug-in editor frames plus gesture/mouse input return.
3. Real bounce/stem renderer and export UI.
4. Arrangement automation parity.
5. Recording comp lanes and take-folder parity.
6. First executable Wine ARM64 smoke test in Compatibility Lab.
7. Production MLX model loading/tool execution beyond the current runtime scaffold.
