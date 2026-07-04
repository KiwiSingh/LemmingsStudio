#!/usr/bin/env python3
"""Full-fat RVC voice transform service for LemmingsStudio.

This service intentionally does NOT fall back to a fake EQ/pitch transform. It
requires a real RVC-compatible runtime plus a user/consent-provided model .pth.
The build script bundles the RVC WebUI runtime and common HuBERT/RMVPE/pretrained
assets under Contents/Resources/Voice/RVC-WebUI.
"""
from __future__ import annotations

import argparse
import os
import pathlib
import shutil
import subprocess
import sys
from typing import Iterable, Optional, Sequence, Tuple


def _resource_root() -> pathlib.Path:
    # .../Contents/Resources/Services/voice_transform.py
    return pathlib.Path(__file__).resolve().parents[1]


def _rvc_root() -> pathlib.Path:
    env = os.environ.get("LEMMINGS_RVC_ROOT", "").strip()
    if env:
        return pathlib.Path(env).expanduser().resolve()
    return _resource_root() / "Voice" / "RVC-WebUI"


def _find_first(root: pathlib.Path, patterns: Iterable[str], exclude_dirs: Sequence[str] = ()) -> Optional[pathlib.Path]:
    if root.is_file():
        return root
    if not root.exists():
        return None
    excluded = {x.lower() for x in exclude_dirs}
    for pattern in patterns:
        for candidate in sorted(root.rglob(pattern)):
            parts = {p.lower() for p in candidate.parts}
            if parts & excluded:
                continue
            if candidate.is_file():
                return candidate
    return None


def _resolve_model(model_arg: str) -> Tuple[pathlib.Path, Optional[pathlib.Path]]:
    raw = model_arg.strip()
    if raw.startswith("builtin://"):
        raise RuntimeError(
            "Built-in starter voices are catalogue/profile slots only. Import a consent-cleared RVC .pth model or a folder containing one."
        )
    if raw.startswith("file://"):
        raw = raw[7:]
    model_path = pathlib.Path(raw).expanduser()
    if not model_path.exists():
        raise RuntimeError(f"RVC model path does not exist: {model_path}")

    model_file = _find_first(model_path, ["*.pth"], exclude_dirs=("pretrained", "pretrained_v2", "pretrained_v0", "hubert", "rmvpe"))
    if model_file is None:
        raise RuntimeError(f"No RVC .pth model found in: {model_path}")
    index_file = _find_first(model_path if model_path.is_dir() else model_path.parent, ["*.index"])
    return model_file, index_file


def _ensure_runtime(root: pathlib.Path) -> None:
    if not root.exists():
        raise RuntimeError(f"Bundled RVC runtime missing: {root}")
    hubert = root / "assets" / "hubert" / "hubert_base.pt"
    rmvpe_pt = root / "assets" / "rmvpe" / "rmvpe.pt"
    rmvpe_onnx = root / "assets" / "rmvpe" / "rmvpe.onnx"
    missing = []
    if not hubert.exists():
        missing.append("assets/hubert/hubert_base.pt")
    if not (rmvpe_pt.exists() or rmvpe_onnx.exists()):
        missing.append("assets/rmvpe/rmvpe.pt or rmvpe.onnx")
    if missing:
        raise RuntimeError("Bundled RVC runtime is incomplete: " + ", ".join(missing))


def _run(cmd: Sequence[str], cwd: pathlib.Path) -> bool:
    print("RVC exec: " + " ".join(map(str, cmd)), file=sys.stderr)
    proc = subprocess.run(list(map(str, cmd)), cwd=str(cwd))
    return proc.returncode == 0


def _try_rvc_python(input_path: pathlib.Path, model_file: pathlib.Path, output_path: pathlib.Path, index_file: Optional[pathlib.Path]) -> bool:
    try:
        from rvc_python.infer import RVCInference  # type: ignore
    except Exception as exc:
        print(f"rvc_python unavailable: {exc}", file=sys.stderr)
        return False
    try:
        device = os.environ.get("LEMMINGS_RVC_DEVICE", "cpu")
        rvc = RVCInference(device=device)
        rvc.load_model(str(model_file))
        # rvc-python handles optional index internally in some versions. Do not
        # invent fake arguments when the installed version does not accept them.
        rvc.infer_file(str(input_path), str(output_path))
        return output_path.exists() and output_path.stat().st_size > 44
    except Exception as exc:
        print(f"rvc_python inference failed: {exc}", file=sys.stderr)
        return False


def _try_cli_candidates(root: pathlib.Path, input_path: pathlib.Path, model_file: pathlib.Path, output_path: pathlib.Path, index_file: Optional[pathlib.Path]) -> bool:
    # Several RVC forks ship different CLI wrappers. Try common interfaces with
    # conservative CPU/RMVPE defaults. If none is present, fail loudly.
    candidates = [
        root / "infer_cli.py",
        root / "tools" / "infer_cli.py",
        root / "infer" / "infer_cli.py",
    ]
    index_arg = str(index_file) if index_file else ""
    for cli in candidates:
        if not cli.exists():
            continue
        attempts = [
            [sys.executable, str(cli), "--input_path", str(input_path), "--opt_path", str(output_path), "--model_path", str(model_file), "--index_path", index_arg, "--f0method", "rmvpe", "--f0up_key", "0"],
            [sys.executable, str(cli), "--input", str(input_path), "--output", str(output_path), "--model", str(model_file), "--index", index_arg, "--pitch", "0", "--f0method", "rmvpe"],
        ]
        for cmd in attempts:
            if _run(cmd, root) and output_path.exists() and output_path.stat().st_size > 44:
                return True
    return False


def transform(input_path: pathlib.Path, model_arg: str, output_path: pathlib.Path) -> pathlib.Path:
    root = _rvc_root()
    _ensure_runtime(root)
    model_file, index_file = _resolve_model(model_arg)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    if output_path.exists():
        output_path.unlink()

    # Make RVC's relative asset lookups deterministic.
    os.environ.setdefault("PYTHONPATH", str(root))
    os.environ.setdefault("RVC_ROOT", str(root))

    if _try_rvc_python(input_path, model_file, output_path, index_file):
        return output_path
    if _try_cli_candidates(root, input_path, model_file, output_path, index_file):
        return output_path

    raise RuntimeError(
        "No working RVC inference entrypoint was available. The app bundle must include rvc-python/rvc-inferpy or an RVC infer_cli.py-compatible runtime."
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True)
    parser.add_argument("--model", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    try:
        out = transform(pathlib.Path(args.input), args.model, pathlib.Path(args.output))
        print(str(out))
        return 0
    except Exception as exc:
        print(f"RVC voice transform failed: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
