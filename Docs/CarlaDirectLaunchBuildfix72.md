# Carla Direct Launch Buildfix 72

Fixes two Carla bridge problems seen with Homebrew formula installs:

- macOS reported the generated `Carla.app` wrapper as not responding.
- Carla showed `Failed to load project` because LemmingsStudio passed a plug-in path as a command-line argument, which Carla interpreted as a project file.

Changes:

- CLI-only Homebrew Carla is no longer wrapped as a fake app bundle.
- `build.sh` now bundles a direct launcher script at `Contents/Resources/Helpers/CarlaFormula/carla`.
- Runtime bridge launching now uses `Process` for CLI-only Carla and keeps the process alive in AppState scope.
- Real `Carla.app` bundles are still opened with `NSWorkspace`.
- LemmingsStudio no longer passes `.vst`, `.vst3`, or `.component` paths to Carla as argv. The UI now tells the user to add the plug-in from inside Carla.
- Old generated `studio.lemmings.carla.launcher` wrapper apps are ignored and removed from the cache when Prepare Carla Bridge runs.
