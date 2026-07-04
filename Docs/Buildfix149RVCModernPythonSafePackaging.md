# Buildfix 149 — RVC modern-Python-safe packaging

## Why

buildfix148 still attempted PyPI RVC adapter packages by default. On Python 3.14,
`rvc-python` pulled legacy `fairseq` and old `numpy<=1.25.3`, while
`rvc-inferpy` forced old `faiss-cpu` constraints. The cloned RVC WebUI runtime
also tried to install `aria2`, whose wheel metadata generation fails on macOS.

## What changed

- Removed `rvc-python` and `rvc-inferpy` from the default required RVC pip spec.
- Added `RVC_INSTALL_PYPI_ADAPTERS=1` as an explicit opt-in for those adapters.
- Kept `RVC_TRY_FAIRSEQ=1` opt-in for legacy fairseq.
- Runtime `requirements.txt` filtering now skips known macOS/new-Python build breakers:
  - `fairseq`
  - `aria2`
  - `rvc-python`
  - `rvc-inferpy`
  - old pinned `numpy<=...`
  - old pinned `faiss-cpu==1.7...` / `<1.8`
- The full RVC WebUI runtime clone and Hugging Face asset prepackaging remain intact.
- Optional/legacy adapter failures remain non-fatal and are written to warning files.

## Notes

The default build now packages the RVC runtime and assets without letting fragile
PyPI adapters block app packaging on Python 3.14/macOS betas.

Opt into adapters only on a compatible Python, usually 3.10/3.11:

```bash
RVC_INSTALL_PYPI_ADAPTERS=1 PYTHON_BIN=/path/to/python3.10 ./build.sh
```

Opt into fairseq only when a specific RVC fork truly needs it:

```bash
RVC_TRY_FAIRSEQ=1 PYTHON_BIN=/path/to/python3.10 ./build.sh
```

Code-signing logic, recording fixes, Splice, plugin hosting, Serum/Serum 2 fixes,
and Demucs packaging were not touched.
