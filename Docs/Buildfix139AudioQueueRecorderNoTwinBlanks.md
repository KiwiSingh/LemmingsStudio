# Buildfix139 — AudioQueue recorder / no twin blank takes

This buildfix replaces the previous AVAudioEngine-input-node recorder with an AudioQueue input capture path.

Why:
- AVAudioEngine's input node was still behaving like the current/default input stream on some macOS/device combinations.
- Multi-channel devices such as Revelator Dynamic could show the chosen device/channel in UI while the capture callback never delivered useful input.
- The provisional recording region could therefore appear as tiny twin blank clips.

Changes:
- Recording now creates a dedicated AudioQueue input stream.
- The queue is bound to the selected CoreAudio input device UID when possible.
- The queue captures the device's advertised input channel layout and copies only the manually selected channel into the take.
- Starting a new take removes stale empty provisional recording clips near the current beat.
- The active provisional clip is the only recording region for the take; stopping commits that same clip instead of creating a second blank one.
- If the stream opens but no callbacks arrive, Lemmings reopens the capture queue once and reports a warning.

Untouched:
- Splice MCP/download/preview
- Sound Agent
- Demucs/stems
- AU hosting
- Piano Roll
- Browser drag/drop
- Monitor modes
- Mixer FX
- Warp controls
- Metronome/count-in timing
