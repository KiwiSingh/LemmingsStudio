# buildfix310 hotfix 3 — Per-track stock FX routing

- Moves stock FX control from one project-global rack to persisted per-track insert racks.
- Adds a track selector to Stock FX Rack.
- Builds a dedicated Filter → Crusher → Drive → Delay → Reverb AVAudioEngine chain per scheduled project track.
- Encodes universal automation targets as track UUID + effect + parameter so Sway-style gesture mappings affect only the intended track.
- Keeps the legacy project-level stockFXRack field decode-compatible but no longer uses it as the live insert-routing source.
- Preserves bf310 hotfix 2 app-icon and spatial note-release fixes.
