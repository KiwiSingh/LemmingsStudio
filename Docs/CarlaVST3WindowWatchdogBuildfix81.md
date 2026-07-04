# Carla VST3 Window Watchdog Buildfix 81

This build fixes the VST3 fallback path where LemmingsStudio detected and inserted a VST3 plug-in slot, but the Carla-hosted plug-in window never appeared.

Changes:

- Launches `carla-single` using the documented argument shape: `native <format> <plugin path> <label>`.
- Adds a stable bridge label so spawned Carla bridge windows/processes are easier for macOS to identify.
- Captures Carla stdout/stderr to `~/Library/Application Support/LemmingsStudio/PluginHosts/Logs/`.
- Focuses the spawned bridge process repeatedly after launch instead of only once.
- Adds a watchdog: if `carla-single` exits before showing a usable bridge, Lemmings opens main Carla and surfaces the captured diagnostic output instead of pretending success.
- Keeps the VST3/AU isolation model intact: Splice VST3 still goes through Carla instead of the in-process AU path.

Notes:

`carla-single` is a bridge helper, so the app now treats early exit or silent failure as a bridge failure and reports the log path. If the bridge helper is present but not capable of showing that plug-in's editor on the current macOS/Homebrew build, the diagnostic log should finally reveal why.
