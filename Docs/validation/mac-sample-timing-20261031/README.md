# Sample-accurate MIDI and sequencer export timing

MIDI note starts/releases previously ran at the beginning of an entire source callback. Large offline blocks therefore shifted starts and shortened notes compared with smaller live buffers. Events are now collected by musical beat, converted to exact sample offsets and dispatched between rendered instrument segments. Releases inside the same block are preserved, short notes are not silently lengthened to 20 ms, and note-off precedes a same-time retrigger. Arpeggiator gates are no longer truncated to the current callback boundary.

Offline transport anchors to the manual-render sample clock. The Master plugin clock uses its actual audio timestamp, not wall-clock elapsed time. AU musical-context/transport callbacks are supplied to hosted instruments and effects. VST3 PPQ, sample position and seconds now agree, including seeks and repeated exports. Tempo-map beat/time inversion accounts for nonzero playback starts.

Arrangement snap controls placement only. Sequencer print duration retains the actual pattern length, even for a half-bar pattern with a one-bar editing grid. Print notes are generated relative to the clip origin.

Validation uses a deterministic gate instrument through the real offline graph, proving identical note-on/off samples at 97, 512 and 4096 frames per block. One-bar snap print onset positions, half-bar print length, AU host clock values and tempo-map restart/inversion are checked. Master AU/VST3 state, gain reduction, bypass and export/grid regressions also pass. A private user project was backed up, repaired without changing notes/audio/presets/manual tempos, and rendered with its real Serum 2 and Kickstart 2 instances. Private project data and rendered audio remain on the user's drive and are not committed.

Commands: `LemmingsStudio --validate-timing OUTPUT --headless-validation`, optionally `--katyusha-project /path/to/private.lemmingsproject`. Native helper and Swift wrapper must be packaged together because the wrapper now requires lp_set_timeline_seconds. The existing C API remains backward-compatible for earlier clients.
