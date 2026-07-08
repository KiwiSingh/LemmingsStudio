# buildfix284 — visionOS Full-Fat Offline MLX Bundle

- visionOS simulator and public IPA builds now default to `VISION_MODEL_BUNDLE_PROFILE=full`.
- Added `Ports/visionOS/prepare-visionos-models.sh`, which prefetches all curated MLX VLM repositories into a reusable macOS cache.
- Full profile includes Qwen2.5-VL 3B 4-bit, Qwen2.5-VL 7B 4-bit, Llama 3.2 Vision 11B 4-bit, and InternVL2 4B 4-bit.
- Build script injects model directories into `LemmingsStudio.app/Models/` before simulator ZIP or resignable IPA packaging.
- Local runtime now prefers bundled model directories and falls back to the Hugging Face downloader only when a bundle is unavailable.
- Added `default`, `minimal`, and `none` bundle profiles for development/storage-constrained builds while keeping `full` as the default.
- Public versions remain macOS 2.0, Windows 2.0, visionOS 1.0.
- Startup model state now detects bundled model directories and exposes their local paths to the MLX runtime UI.
- Model injection verifies each embedded model has `config.json` and at least one recognized weight file before packaging succeeds.
- `release-visionos.sh` explicitly defaults to the full profile so public artifacts cannot silently inherit the old thin behavior.
