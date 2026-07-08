# LemmingsStudio buildfix267 — visionOS Recording Parity

Public version numbers are unchanged:

- macOS v2.0
- Windows v2.0
- visionOS v1.0

## Recording parity work

### Persistent recording setup
- count-in bars
- pre-roll bars
- optional punch in/out
- punch-in and punch-out beat positions
- settings persist inside the `.lemmings` project

### Transport-aware recording
- recording can begin after count-in
- pre-roll seeks the transport before the target recording region
- punch mode arms first, begins recording at punch-in, and stops at punch-out
- recording status exposes countdown and punch-arm state

### Take folders and lanes
- microphone recordings append to the active take folder
- takes remain individually addressable
- recorded takes seed initial comp regions where appropriate
- older projects without comp-region fields remain decodable

### Region-level comp editing
- comp regions reference a take over an explicit beat range
- add regions manually
- split selected regions at the playhead
- reassign a region to a different take
- swipe left/right on a comp region to cycle through takes
- selected-take menu remains available for deterministic control

### Comp consolidation/export
- comp regions are rendered in timeline order to a new WAV
- source offsets are respected
- short fade-in/fade-out ramps are applied at region boundaries
- consolidated comps are stored under `Documents/Exports/Comps`
- resulting paths are persisted in the take folder
- consolidation is written into Living Project Memory

## Validation performed
- parsed the complete visionOS Swift source tree with `swiftc -frontend -parse`
- validated `build-visionos.sh` syntax with `bash -n`
- public version metadata left unchanged

## Next for full macOS parity

buildfix268: Automation parity
- persist full automation data in projects
- Write mode
- Touch mode
- Latch mode
- curve handles/interpolation
- record automation from spatial gestures

Then:
- buildfix269: real MLX model loading + constrained tool execution
- buildfix270: Wine ARM64 runtime bring-up and first VST3 probe
- buildfix271: final visionOS/macOS parity audit, Xcode/hardware hardening, and launch packaging
