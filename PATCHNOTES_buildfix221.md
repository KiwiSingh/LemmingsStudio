# LemmingsStudio buildfix221

Windows backend setup fix after buildfix220.

## Fixed

- Demucs model preloading no longer uses a tiny/all-zero `silence.wav` probe.
- The preload probe is now a quiet 12-second non-silent stereo WAV, which avoids HTDemucs reflect-padding assertion failures seen during `htdemucs` preload on Windows x64.
- Demucs preload now runs with `--shifts 0 --segment 7` to reduce CPU preload work and avoid unnecessary augmentation during cache warmup.
- Individual preload failures are explicitly treated as non-fatal by checking `$LASTEXITCODE`; setup can complete even if a model preload pass fails.

## Notes

The goal of preload is only to force Demucs model weight download/cache. It is not a validation-quality stem split.
