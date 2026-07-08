# LemmingsStudio buildfix268 — visionOS Automation Parity

Public versions remain unchanged:

- macOS v2.0
- Windows v2.0
- visionOS v1.0

## What landed

### Persistent project automation

`LemmingsProject` now persists complete visionOS automation lane data. Opening a project restores lanes, write modes, points, curves, visibility, arming state, and curve handles. Saving a project writes the current automation state back into the `.lemmings` document.

### Automation write modes

Each lane now supports:

- Read
- Write
- Touch
- Latch

Touch mode records only while the control is actively manipulated. Latch mode begins writing when manipulation starts and continues until the user explicitly releases automation latches.

### Curve editing

Automation points support:

- Hold
- Linear
- Smooth
- Exponential

Each point also has a `curveHandle` value from -1 through +1, allowing segment bias/easing adjustments instead of only fixed interpolation.

### Spatial gesture automation

The selected spatial surface can expose X, Y, and Z position lanes. The Spatial Editor's position sliders now signal gesture begin/end events to the automation system. Armed Write/Touch/Latch lanes record those motions against the live transport playhead.

### Lane editor UX

The Automation window is now a split-view editor with:

- mixer, Mac Host parameter, and selected spatial-surface exposure
- lane selection
- visibility and arming controls
- Read/Write/Touch/Latch selector
- playhead-based point insertion
- point value and beat editing
- curve type selection
- curve-handle editing
- explicit Release Latches control
- project staging/save control

## Validation

The modified Swift sources were parser-validated in the available environment. A full visionOS SDK type-check, Xcode build, and Vision Pro hardware interaction test still require macOS/Xcode.

## Next for full macOS parity

1. buildfix269 — real MLX model loading, cache/download flow, multimodal context, background scheduling, constrained tool execution, and confirmation gates.
2. buildfix270 — staged Wine ARM64 runtime bring-up, loader/JIT/mmap diagnostics, first VST3 probe host, DSP callback transport, and editor bridge experiments.
3. buildfix271 — final macOS-vs-visionOS parity audit, Xcode/hardware hardening, performance profiling, and release artifact packaging.
