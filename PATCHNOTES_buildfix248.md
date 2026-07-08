# Buildfix248 — visionOS Native Audio, MIDI, Liquid Glass, and Skins

## Native audio engine

- Adds a native AVAudioEngine graph.
- Adds polyphonic stock Oscillatron and LemmingBass voice generation.
- Adds project MIDI-note playback into the selected stock instrument.
- Adds project audio-clip scheduling, clip source offsets, clip-length cropping, per-track volume, and pan.
- Adds stock 3-band EQ, delay, and reverb nodes.
- Adds panic/all-notes-off behavior.

## MIDI

- Adds CoreMIDI client/input-port setup.
- Discovers and connects available MIDI sources.
- Routes live note-on/note-off into the native stock instrument.
- Receives CC and pitch-bend messages; CC1 is currently wired as a simple expressive reverb modulation proof-of-path.

## Audio recording

- Adds native microphone recording through the AVAudioEngine input node.
- Adds microphone usage description.
- Writes takes to `Documents/LemmingsStudio/Recordings` as CAF files.
- Adds a detachable Audio Control window with record/stop controls and status.

## Liquid Glass and skins

- Ports all current LemmingsStudio visual skins to visionOS.
- Adds persistent skin selection.
- Adds themed background/glow palettes and themed Arrangement clip/grid accents.
- Adds Liquid Glass-aware custom control surfaces.
- Uses `glassEffect` on current SDKs and `glassBackgroundEffect` fallback on older toolchains/targets.
- Adds detachable Skin Gallery window.

## README

- Replaces the root README with the user-provided current README as the source of truth.
- Updates platform status and repository layout.
- Adds visionOS build instructions and direct `xcodebuild` examples.
- Documents native visionOS audio/MIDI/recording and skin status.

## Validation note

Source structure, shell syntax, plist validity, and delimiter balance were checked in the Linux environment. A real visionOS build still requires Xcode and the visionOS SDK on macOS.
