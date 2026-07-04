"""
LemmingsStudio Windows stem-splitter entry point.

Routes a stem-separation job to the best accelerator for this machine:

  1. If an ONNX stem model is available AND ONNX Runtime can load an accelerated
     provider (CUDA / DirectML / QNN / OpenVINO), run via ONNX Runtime on that
     provider. This is the path that reaches AMD/Intel GPUs and ARM NPUs.
  2. Otherwise run official PyTorch Demucs on the right torch device (CUDA if
     present, else CPU). This is the path that works out of the box today.

Usage:
    python stem_runner.py --flavor directml --input song.wav --output outdir
    python stem_runner.py --probe directml      # just print what would be used

Exit code 0 = success.
"""
from __future__ import annotations

import argparse
import os
import importlib.util
import runpy
import sys

import provider_select


def _log(msg: str) -> None:
    print(f"[lemmings-stems] {msg}", flush=True)


def _find_onnx_model() -> str | None:
    """
    Look for an ONNX stem model the ORT path can use. We check, in order:
      $LEMMINGS_STEM_ONNX, then <this dir>/models/*.onnx
    Returns None if none is present (then we use the PyTorch path).
    """
    env = os.environ.get("LEMMINGS_STEM_ONNX")
    if env and os.path.isfile(env):
        return env
    models_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "models")
    if os.path.isdir(models_dir):
        for name in sorted(os.listdir(models_dir)):
            if name.lower().endswith(".onnx"):
                return os.path.join(models_dir, name)
    return None


def run_onnx(model_path: str, flavor: str, input_path: str, output_dir: str) -> int:
    """
    Create an ONNX Runtime session on the selected provider and confirm it loaded.

    NOTE: the per-model inference adapter (STFT framing, overlap-add, stem
    reconstruction) depends on which ONNX export you use, so the actual separation
    call is intentionally left as the one integration point to fill once you pick a
    model export. Until then this still proves the accelerator path end-to-end:
    it loads the model on the real provider (so you can SEE DirectML/CUDA/QNN engage)
    and then defers to the PyTorch path for the actual stems so you always get output.
    """
    try:
        import onnxruntime as ort
    except Exception as e:
        _log(f"onnxruntime not available ({e!r}); using PyTorch path.")
        return run_pytorch(flavor, input_path, output_dir)

    providers = provider_select.select_providers(flavor, list(ort.get_available_providers()))
    _log(f"ONNX Runtime providers (priority order): {providers}")
    try:
        sess = ort.InferenceSession(model_path, providers=providers)
        active = sess.get_providers()
        _log(f"Loaded {os.path.basename(model_path)} on: {active[0]} (full chain {active})")
    except Exception as e:
        _log(f"Could not start ONNX session ({e!r}); using PyTorch path.")
        return run_pytorch(flavor, input_path, output_dir)

    # >>> Model-specific inference adapter goes here. <<<
    # Once a concrete ONNX stem model is chosen, replace this fallback with the
    # real STFT -> sess.run(...) -> ISTFT -> write-stems pipeline.
    _log("ONNX accelerator confirmed. Running separation via PyTorch for now "
         "(plug the model adapter in run_onnx to do inference on the NPU/GPU).")
    return run_pytorch(flavor, input_path, output_dir)


def _missing_demucs_runtime() -> list[str]:
    missing: list[str] = []
    for module_name in ("demucs", "torch", "torchaudio", "soundfile"):
        try:
            if importlib.util.find_spec(module_name) is None:
                missing.append(module_name)
        except Exception:
            missing.append(module_name)
    return missing


def _patch_torchaudio_save_for_demucs() -> None:
    """Avoid torchaudio's newer TorchCodec save path on Windows.

    Newer torchaudio releases route ta.save() through torchcodec. On Windows,
    torchcodec then requires a matching native libtorchcodec build plus a
    full-shared FFmpeg DLL stack. Demucs only needs to write ordinary stem WAVs,
    so use soundfile for the save step instead. This keeps Demucs independent of
    torchcodec/ffmpeg-shared compatibility churn.
    """
    try:
        import numpy as np
        import soundfile as sf
        import torch
        import torchaudio
    except Exception as e:
        _log(f"Could not install torchaudio.save compatibility patch ({e!r}); continuing without it.")
        return

    def lemmings_save(uri, src, sample_rate, channels_first=True, format=None,
                      encoding=None, bits_per_sample=None, buffer_size=4096,
                      backend=None, compression=None):
        wav = src.detach().cpu() if hasattr(src, "detach") else torch.as_tensor(src).cpu()
        if channels_first and wav.ndim == 2:
            wav = wav.transpose(0, 1)
        elif wav.ndim == 1:
            wav = wav.unsqueeze(1)
        data = wav.numpy().astype(np.float32, copy=False)
        # Demucs already normalizes before save_audio(); clamp defensively so
        # odd probe files or edge cases do not produce invalid PCM.
        data = np.clip(data, -1.0, 1.0)
        target = str(uri)
        subtype = None
        if bits_per_sample == 16:
            subtype = "PCM_16"
        elif bits_per_sample == 24:
            subtype = "PCM_24"
        elif bits_per_sample == 32:
            subtype = "PCM_32"
        sf.write(target, data, int(sample_rate), subtype=subtype)

    torchaudio.save = lemmings_save
    _log("Patched torchaudio.save to soundfile backend to avoid TorchCodec DLL/FFmpeg-shared issues.")


def run_pytorch(flavor: str, input_path: str, output_dir: str) -> int:
    """Official PyTorch Demucs on the best torch device for this flavor."""
    missing = _missing_demucs_runtime()
    if missing:
        _log("Stem splitting is not available in this backend: missing " + ", ".join(missing))
        _log("On native Windows ARM64 this is expected today because torchaudio/numba/llvmlite/soxr wheels are incomplete. Use a win-x64 build/Python under emulation for Demucs stems, or provide an ONNX stem model via LEMMINGS_STEM_ONNX.")
        return 12
    device = provider_select.torch_device(flavor)
    _patch_torchaudio_save_for_demucs()
    _log(f"PyTorch Demucs on device: {device}")
    os.makedirs(output_dir, exist_ok=True)
    sys.argv = ["demucs", "-n", "htdemucs", "-d", device, "-o", output_dir, input_path]
    try:
        runpy.run_module("demucs", run_name="__main__")
        return 0
    except SystemExit as e:  # demucs may call sys.exit(0)
        return int(e.code) if isinstance(e.code, int) else 0
    except Exception as e:
        _log(f"Demucs failed: {e!r}")
        return 1


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="LemmingsStudio stem splitter")
    ap.add_argument("--flavor", default="auto",
                    help="cuda | directml | openvino | qnn | cpu | auto")
    ap.add_argument("--input", help="input audio file")
    ap.add_argument("--output", help="output directory")
    ap.add_argument("--probe", nargs="?", const="auto",
                    help="print the chosen providers/device and exit")
    args = ap.parse_args(argv)

    if args.probe is not None:
        print(provider_select.describe(args.probe if args.probe != "auto" else args.flavor))
        missing = _missing_demucs_runtime()
        if missing:
            print("Demucs runtime: unavailable (missing " + ", ".join(missing) + ")")
            print("Tip: native Windows ARM64 currently needs a non-Demucs path such as an ONNX stem model, or use win-x64/Python x64 under emulation for stems.")
        else:
            print("Demucs runtime: available")
        return 0

    if not args.input or not args.output:
        ap.error("--input and --output are required unless --probe is used")
    if not os.path.isfile(args.input):
        _log(f"Input not found: {args.input}")
        return 2

    _log(provider_select.describe(args.flavor).replace("\n", " | "))
    model = _find_onnx_model()
    if model:
        _log(f"Using ONNX model: {model}")
        return run_onnx(model, args.flavor, args.input, args.output)
    _log("No ONNX stem model found; using PyTorch Demucs (works on CUDA/CPU today).")
    return run_pytorch(args.flavor, args.input, args.output)


if __name__ == "__main__":
    raise SystemExit(main())
