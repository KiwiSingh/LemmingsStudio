# LemmingsStudio Windows — buildfix179 (Claude): multi-vendor accelerator targeting + auto-detect

Wires up real ONNX Runtime execution-provider selection so one codebase targets
**NVIDIA / AMD / Intel / ARM-NPU / CPU**, and makes the app auto-pick the right one.

## The honest starting point
The old scripts installed `onnxruntime-*` but **never used it** — both the smoke test and
preload just ran `python -m demucs` (PyTorch). So there was no provider selection. This
makes it real.

## New backend brain (`Ports/Windows/backend/`)
- **`provider_select.py`** — single source of truth mapping a flavor + the providers ORT
  actually reports into an ordered list, always ending in CPU:
  - cuda → CUDAExecutionProvider, directml → DmlExecutionProvider,
    openvino → OpenVINOExecutionProvider, qnn → QNNExecutionProvider, plus an `auto`
    priority chain. Verified across NVIDIA/AMD/Intel/Snapdragon/CPU-fallback cases.
- **`stem_runner.py`** — one entry point that runs ONNX Runtime on the selected provider
  when an ONNX stem model is present (the path that reaches AMD/Intel GPUs and ARM NPUs),
  otherwise runs PyTorch Demucs on the right torch device (CUDA/CPU — works today). It also
  supports `--probe` to print exactly what it would use.

## Scripts
- **`detect-hardware.ps1`** now detects GPU vendor **and NPU likelihood**, recommends a
  flavor (cuda/directml/openvino/qnn/cpu), and with `-Json` emits a machine-readable line.
- **`setup-backend.ps1`** adds **qnn** and **openvino** flavors (correct ORT packages:
  onnxruntime-qnn / onnxruntime-openvino / -directml / -gpu / onnxruntime), and probes the
  chosen provider after install.
- **`test-stems.ps1`** now routes through `stem_runner.py --flavor <backend>` so the engaged
  accelerator is logged.
- **`build-installer.ps1` / `build-windows.ps1`** accept the new flavors and ship the
  `backend/` folder in the published app.

## App (C#)
- **`HardwareDetector.cs`** runs `detect-hardware.ps1 -Json` and parses the recommendation.
- **`MainForm`** auto-detects on launch (status bar shows the chosen backend), adds a
  **Tools → Detect Hardware…** item and Install/Repair entries for **OpenVINO** and **QNN**,
  and stem-split now uses the auto-selected backend instead of hard-coded DirectML.

## Honest scope
- CUDA and CPU stem-splitting work out of the box. DirectML/OpenVINO/QNN are wired and will
  **load on the real provider** (you'll see it in the log), but driving the *actual* model on
  the GPU/NPU needs an ONNX-exported stem model — the one integration point left marked in
  `run_onnx()`. Until a model is dropped in `backend/models/`, those flavors still produce
  stems via the CUDA/CPU path so you always get output.
- ARM-NPU (QNN) genuinely needs real Copilot+ hardware; it cannot be exercised inside
  Parallels.
- Authored on Linux: Python is syntax-checked and the selection logic unit-verified; C#/PS
  are author-and-read (no toolchain here) — expect at most minor fixups on first Windows build.

## Beginner build instructions
See the rewritten **Docs/WindowsBuildForNoobs.md** — full zero-knowledge walkthrough,
including Parallels (Windows 11 ARM) setup and a backend-picker table.
