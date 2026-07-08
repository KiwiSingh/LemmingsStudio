# Buildfix260 Semantic Project Graph

The semantic project graph is the foundation for LemmingsStudio's AI-native layer.

It turns project state into a compact graph:

- project → tracks
- tracks → clips
- tracks → mixer routes
- tracks → return sends
- project → plug-in backends
- project → spatial objects
- project → Compatibility Lab candidates

This is designed for:

- MLX local agents
- project memory
- semantic editing commands
- workspace restore
- Host Mode parity checks
- cross-platform feature audits

The graph does not execute plug-ins or DSP. It is safe metadata.
