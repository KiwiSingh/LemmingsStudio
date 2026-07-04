# Buildfix163 — Official Demucs cert + weight cache fix

- Auto stem splitting now prefers official Demucs before MLX on Apple Silicon, because current `demucs-mlx` can crash with the MLX GPU stream/thread error.
- Stem subprocesses now receive certifi-backed `SSL_CERT_FILE`, `REQUESTS_CA_BUNDLE`, and `CURL_CA_BUNDLE` so Python.org/macOS beta SSL trust issues do not break Demucs downloads.
- Stem subprocesses now receive app-local model cache environment variables, including `TORCH_HOME`, `XDG_CACHE_HOME`, `HF_HOME`, `HF_HUB_CACHE`, and `MLX_WEIGHTS_CACHE`.
- `build.sh` now pre-caches official PyTorch Demucs weights during packaging into `Contents/Resources/StemBackends/ModelCache/torch`.
- New build knobs: `DEMUCS_PRELOAD_WEIGHTS`, `DEMUCS_PRELOAD_MODELS`, and `DEMUCS_PRELOAD_STRICT`.

No code-signing, recording, Splice, Serum/hosted plugin, RVC, export, mixer, warp, or metronome/count-in changes.
