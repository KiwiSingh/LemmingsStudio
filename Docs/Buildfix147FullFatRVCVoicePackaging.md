# Buildfix147 — Full-fat RVC voice packaging

Base: Claude buildfix145 plus buildfix146 AI backend/chat changes.

## Scope

This buildfix removes the lightweight fake/local voice-transform fallback and switches the Voice AI service to require a real RVC runtime/model path.

## What changed

- `build.sh` now treats RVC as a full bundled runtime rather than a handful of audio DSP Python packages.
- Adds RVC packaging knobs:
  - `RVC_RUNTIME_REPO`
  - `RVC_RUNTIME_REF`
  - `RVC_ASSETS_HF_REPO`
  - `RVC_PRELOAD_STRICT`
  - `RVC_PRELOAD_ALL`
  - `RVC_ALLOW_PATTERNS`
- `build.sh` clones the RVC WebUI runtime into `Contents/Resources/Voice/RVC-WebUI`.
- `build.sh` installs RVC runtime requirements when available.
- `build.sh` downloads HuBERT/RMVPE/pretrained/UVR/infer-pack assets from the configured Hugging Face repo.
- `build.sh` normalizes common asset paths into:
  - `assets/hubert/hubert_base.pt`
  - `assets/rmvpe/rmvpe.pt` / `rmvpe.onnx`
  - `assets/pretrained*`
  - `assets/uvr5_weights`
- `voice_transform.py` now fails loudly if a real RVC runtime/model is unavailable.
- `voice_transform.py` no longer performs the old pitch/EQ/compression fallback.
- Built-in Voice AI entries are catalogue slots only; rendering requires an imported consent-cleared RVC `.pth` model or folder containing one.

## Intentionally not touched

- Claude's recording fix
- Claude's code-signing / microphone entitlement logic
- Splice MCP/download/preview
- Serum / Serum 2 / hosted plugin fixes
- AU hosting
- Demucs/stems
- Piano Roll
- Browser drag/drop
- Monitor modes
- Mixer FX
- Warp controls
- Metronome/count-in
