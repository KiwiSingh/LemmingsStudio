# Carla Single Plug-in Bridge Buildfix 73

This buildfix removes the manual Add Plugin friction for Carla fallback hosting.

## Changes

- Detects `carla-single` alongside CLI/Homebrew Carla and in bundled helper locations.
- Bundles `carla-single` into `Contents/Resources/Helpers/CarlaFormula/carla-single` when Homebrew installed Carla as a CLI formula.
- Opens VST/VST3 plug-ins through `carla-single <format> <plugin-path>` instead of launching empty Carla.
- Keeps main `carla` as a fallback only when the single plug-in helper is unavailable.
- Brings the Carla subprocess to the front after launch so the plug-in bridge appears over LemmingsStudio instead of hiding in the background.
- Preserves the no-fake-Carla.app behavior from buildfix 72.

This still keeps hosting out-of-process for crash isolation, but makes the UX closer to a DAW-style external plug-in editor launch.
