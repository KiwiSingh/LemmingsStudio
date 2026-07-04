# Carla Formula Wrapper Buildfix 70

Homebrew may install Carla as a command-line formula without a standalone `Carla.app` bundle. LemmingsStudio's previous packaging only looked for an app bundle, so `brew install carla` could succeed while packaging still warned that Carla was unavailable.

This buildfix adds a wrapper path:

- `build.sh` now searches for the `carla` executable via `CARLA_BIN`, `command -v carla`, Homebrew bin paths, and Homebrew Cellar paths.
- If only the CLI binary exists, `build.sh` generates `Contents/Resources/Helpers/Carla.app` as a tiny launcher app that execs the detected `carla` binary.
- Runtime Carla bridge prep can also wrap a Homebrew CLI-only Carla install inside `~/Library/Application Support/LemmingsStudio/PluginHosts/Carla.app`.
- `CARLA_APP=/path/to/Carla.app` still wins when a real app bundle exists.
- `CARLA_BIN=/path/to/carla` can be used to force a specific CLI Carla binary.

This keeps the build green on Homebrew formula installs while still allowing a real Carla.app to be bundled when available.
