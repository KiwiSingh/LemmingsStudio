# Carla single-host discovery Buildfix 82

Buildfix 81 could still open an empty Carla window when Splice Sounds VST3 was
selected. That happened when LemmingsStudio found `Carla.app`, but did not find
the real `carla-single` helper used for direct single-plug-in hosting.

Changes:

- Recursively searches inside bundled, cached, system, Caskroom, and Cellar
  Carla installations for an executable named `carla-single`.
- Treats a plug-in-specific VST/VST3 bridge request as failed when
  `carla-single` cannot be found, instead of opening main Carla and pretending
  the plug-in was loaded.
- Keeps manual main-Carla launch available for the standalone “Open Carla"
  button, but no longer uses it as the auto-load path for Splice Sounds VST3.
- Status text now tells the user exactly whether single-plug-in hosting is ready.

This should fix the “new Carla window spawns but Splice Sounds VST3 never loads”
case by forcing the code path to use `carla-single` or report the missing helper.
