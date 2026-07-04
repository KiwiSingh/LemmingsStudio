"""
ONNX Runtime execution-provider selection for LemmingsStudio (Windows).

This is the single source of truth for "which accelerator do we run on?". It maps
a requested backend flavor + the providers ONNX Runtime actually reports as available
on THIS machine into an ordered provider list, so one codebase can target:

    NVIDIA  -> CUDAExecutionProvider
    AMD/Intel/any DX12 GPU -> DmlExecutionProvider  (DirectML)
    Intel (CPU/iGPU/Arc, native) -> OpenVINOExecutionProvider
    Snapdragon / Copilot+ NPU -> QNNExecutionProvider
    anything -> CPUExecutionProvider  (universal fallback, always appended)

ONNX Runtime tries providers in order and silently falls back to the next if one
can't load, so we always end with CPU. Import this from stem_runner.py.

Honest note: having the provider available is necessary but not sufficient — the
NPU (QNN) path also needs an NPU-friendly (often INT8-quantized) ONNX model, which
is the immature part of the Windows ML stack as of early 2026. The CUDA and CPU
paths are the ones that work out of the box today.
"""
from __future__ import annotations

# Friendly flavor -> the provider we PREFER for that flavor, highest priority first.
# CPUExecutionProvider is always appended as the final fallback.
_FLAVOR_PRIORITY = {
    "cuda":     ["CUDAExecutionProvider", "DmlExecutionProvider"],
    "directml": ["DmlExecutionProvider"],
    "openvino": ["OpenVINOExecutionProvider", "DmlExecutionProvider"],
    "qnn":      ["QNNExecutionProvider", "DmlExecutionProvider"],
    "cpu":      [],
    "auto":     ["CUDAExecutionProvider", "QNNExecutionProvider",
                 "OpenVINOExecutionProvider", "DmlExecutionProvider"],
}


def available_providers() -> list[str]:
    """Providers this ONNX Runtime install actually reports. Empty if ORT missing."""
    try:
        import onnxruntime as ort
        return list(ort.get_available_providers())
    except Exception:
        return []


def select_providers(flavor: str, available: list[str] | None = None) -> list[str]:
    """
    Return an ordered provider list for `flavor`, filtered to what's available,
    always ending in CPUExecutionProvider.

    >>> select_providers("cuda", ["CUDAExecutionProvider", "CPUExecutionProvider"])
    ['CUDAExecutionProvider', 'CPUExecutionProvider']
    >>> select_providers("directml", ["CPUExecutionProvider"])
    ['CPUExecutionProvider']
    """
    flavor = (flavor or "auto").lower()
    if available is None:
        available = available_providers()

    preferred = _FLAVOR_PRIORITY.get(flavor, _FLAVOR_PRIORITY["auto"])
    ordered: list[str] = []
    for p in preferred:
        if p in available and p not in ordered:
            ordered.append(p)
    # Universal fallback, never duplicated.
    if "CPUExecutionProvider" not in ordered:
        ordered.append("CPUExecutionProvider")
    return ordered


def torch_device(flavor: str) -> str:
    """
    Device string for the PyTorch Demucs path (the working default backend).
    Only CUDA has real PyTorch acceleration on Windows today; DirectML/QNN/OpenVINO
    are ONNX-Runtime concepts, so those flavors run Demucs on CPU unless CUDA exists.
    """
    flavor = (flavor or "auto").lower()
    try:
        import torch
        if torch.cuda.is_available() and flavor in ("cuda", "auto"):
            return "cuda"
    except Exception:
        pass
    return "cpu"


def describe(flavor: str) -> str:
    avail = available_providers()
    chosen = select_providers(flavor, avail)
    dev = torch_device(flavor)
    return (
        f"flavor={flavor}\n"
        f"onnxruntime_available={avail or '(onnxruntime not installed)'}\n"
        f"onnx_provider_order={chosen}\n"
        f"pytorch_demucs_device={dev}"
    )


if __name__ == "__main__":
    import sys
    print(describe(sys.argv[1] if len(sys.argv) > 1 else "auto"))
