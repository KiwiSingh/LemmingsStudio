# Buildfix223 — Windows Demucs TorchCodec bypass

Fixes Windows x64 Demucs failures where newer `torchaudio.save()` routes through
TorchCodec, then TorchCodec fails to load native `libtorchcodec_core*.dll` or a
matching full-shared FFmpeg stack.

Changes:
- `stem_runner.py` no longer treats `torchcodec` as required.
- Before launching Demucs, it monkey-patches `torchaudio.save()` to write stems
  through `soundfile`, avoiding TorchCodec entirely for ordinary WAV stem output.
- `setup-backend.ps1` stops installing/verifying TorchCodec by default.
- Demucs model preload no longer runs full separation/export on the probe file.
  It now loads `demucs.pretrained.get_model(name)` to force model-weight caching
  without touching the fragile audio save path.

This keeps Demucs dependency setup focused on `torch`, `torchaudio`, `demucs`,
and `soundfile`, while avoiding TorchCodec/FFmpeg shared-DLL compatibility churn.
