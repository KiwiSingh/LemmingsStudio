# Buildfix 56 — Agentic Serum Mapping, Fullscreen Launch, Splash

This pass adds three beta-polish features:

- The Sound Agent now accepts Claude/Ollama responses in multiple plugin-parameter shapes, including Serum/Serum 2-style names.
- Hosted AU parameter application now fuzzy-maps common synth labels and scales normalized 0...1 values into the AU parameter range.
- The app launches into fullscreen by default and shows a lemmings-inspired splash screen while the UI/audio engine comes up.

## Sound Agent / Serum

Claude may return JSON like any of these:

```json
{"params":{"filter_cutoff":0.42,"env1_attack":0.05}}
{"serum":{"Osc A Level":0.8,"LFO 1 Rate":0.25}}
{"parameters":[{"name":"Filter Cutoff","value":0.55}]}
```

`DeviceTranslationLayer.normalizedPluginParams(from:)` flattens these into a single parameter plan. The AU host then tries exact address matches, exact display-name matches, compact/fuzzy matches, and Serum-style aliases such as Filter Cutoff, Osc A Level, Env 1 Attack, LFO 1 Rate, and FX mix controls.

## Fullscreen Launch

`launchFullscreenEnabled` defaults to true and can be toggled in Settings → DAW.

## Splash Screen

`Sources/LemmingsStudio/Resources/LemmingsSplash.png` is a transparent 2048×2048 PNG used by `LemmingsSplashView`. It is intentionally decorative and beta-facing; it can be replaced later with final branding art without changing the app code.
