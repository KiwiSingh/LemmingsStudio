# Current scope

The product decision is **Windows in Python; macOS stays Swift**.

- Working branch: `rewrite/python-windows`.
- Unchanged baseline: `main` at `4a2c0cf1b137e21152fa9d8cf9844f2c5ec777fc`.
- The earlier `rewrite/python-cross-platform` branch remains at the baseline as
  historical context. It is not the active product branch.
- New files live under `PythonStudio/`, `Docs/PythonRewrite/` and the dedicated
  Windows-only workflow. Existing Swift and C# application files are not changed.
- Local development and testing on this Mac is permitted; no Python macOS release
  or replacement of the Swift application is planned.
- The retained macOS build is the functional and musical reference. Preservation
  of every workflow is tracked in PARITY.md; a completed initial slice does not
  establish full parity.
- All local project/build work, temporary files, logs and caches are directed to
  Zweidrive. GitHub runners build remotely; downloaded results go to Zweidrive.
