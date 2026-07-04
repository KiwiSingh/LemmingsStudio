# Buildfix116 — Demucs MLX preload certificate/runtime fix

Buildfix115 made the preload path more realistic, but packaging still failed on
some macOS/Python combinations with:

```text
SSLCertVerificationError: certificate verify failed: unable to get local issuer certificate
```

The failure occurred while Demucs MLX/torch hub attempted to download upstream
Demucs checkpoints before conversion. The build script now installs `certifi`
into the bundled Python venv and forces Demucs MLX preload/runtime downloads to
use that CA bundle via:

- `SSL_CERT_FILE`
- `REQUESTS_CA_BUNDLE`
- `CURL_CA_BUNDLE`

The generated bundled `StemBackends/demucs-mlx` wrapper also sets those variables
at runtime, so first-use downloads still work if a model was not preloaded.

This build also fixes the preload helper's console-script lookup by prepending
`Contents/Resources/PythonVenv/bin` to `PATH`, so `mlx-weights` can be found
when installed by `demucs-mlx[convert]`.

As a last-resort packaging-only escape hatch, the build script accepts:

```bash
DEMUCS_MLX_ALLOW_INSECURE_SSL=1 ./build.sh
```

Do not use that unless the certifi-backed path still fails on a broken local
Python trust-store setup.
