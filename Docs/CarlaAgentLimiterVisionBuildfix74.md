# Buildfix 74 — Carla Agent Bridge + Proper Limiter + visionOS Notes

- Added a Carla-bridged InstrumentTarget so the Sound Agent can address VST/VST3 instruments instead of falling back to a static handoff.
- Carla launches now receive a stable CARLA_OSC_UDP_PORT per plug-in, and agent outputs can send `/set_parameter_value` OSC updates for macro_1...macro_8 and param_0...param_63.
- Agent handoffs are still written under Application Support for audit/debug, but the main path is now live Carla control when Carla is running.
- Reworked Peak Limiter into a real lookahead limiter with threshold, ceiling, release, lookahead, soft clip, output, and stereo-linked gain reduction.
- visionOS port notes: the UI can be ported later, but plug-in hosting, Carla, Homebrew, filesystem scanning, external helpers, and low-level audio assumptions need a separate capability layer.
