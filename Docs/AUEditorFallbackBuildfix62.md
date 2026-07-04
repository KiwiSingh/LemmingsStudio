# AU Editor Fallback Buildfix 62

Xcode/macOS SDK 27 does not expose `AUAudioUnit.requestViewController(...)` on the build path used by LemmingsStudio. Buildfix 60 tried to call that API to display vendor plug-in editors, which caused a compile break.

This build removes that unavailable API call and opens a generic AU parameter panel instead. The panel is still a real plug-in window: it targets the loaded Audio Unit, lists its exposed `AUParameterTree` parameters, and lets users adjust values through sliders. For AU plug-ins that do not expose automatable parameters, the window explains that the component did not provide host-visible controls.

This keeps Splice Sounds / Bridge and other AU fallbacks from degenerating into Finder reveal-only behavior while avoiding the unavailable vendor-editor API.
