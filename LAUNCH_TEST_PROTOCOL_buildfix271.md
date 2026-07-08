# LemmingsStudio buildfix271 — Launch Test Protocol

Use this as the final human test pass after platform-native builds succeed.

## macOS v2.0 smoke test

1. Launch on a clean user account.
2. Create a project, add audio and MIDI, save, quit, reopen.
3. Open the Chat pane and verify Ollama chat-model discovery/generation.
4. Run the Sound Agent path separately from Chat and verify the model lanes do not collide.
5. Test Replicate Sonic Signature with Stock Analog.
6. Test Replicate Sonic Signature with a third-party instrument; verify inaccessible parameters produce explicit manual knob instructions rather than false success claims.
7. Start Integrated Host Mode and record the pairing/status details.
8. Pair visionOS, instantiate a known AU, move a parameter from visionOS, and verify round trip.
9. Test streamed editor frame updates and pointer/drag input.
10. Render a project master and stems through Host Mode and compare duration/sample rate/channel count.

## Windows v2.0 smoke test

1. Install on a clean Windows VM or machine.
2. Launch without developer tools in PATH.
3. Verify the Chat model selector and the Agent model selector are distinct.
4. Pull/run the chat model through Ollama.
5. Test Replicate Signature using a loaded VST3 target.
6. Verify inaccessible plugin controls produce manual instructions.
7. Open/close VST3 editors repeatedly and scan the diagnostics bundle for crashes.
8. Record audio and MIDI, save, quit, reopen.
9. Export audio and verify installer/uninstaller behavior.

## visionOS v1.0 Simulator smoke test

1. Build/package the Simulator ZIP.
2. Move the ZIP to a clean test Mac/Xcode environment.
3. Extract and launch through the expected simulator workflow.
4. Open Arrangement, Mixer, Piano Roll, Step Sequencer, Automation, Takes & Comping, Splice MCP, MLX Runtime, Plugin Parity, Compatibility Lab.
5. Create/save/reopen a project.
6. Verify no hardware-only code path crashes merely because the Simulator lacks the corresponding device capability.

## visionOS v1.0 hardware smoke test

1. Sign or re-sign the public IPA with the tester's own Apple identity/provisioning workflow, then install it on Apple Vision Pro.
2. Launch, grant permissions, create/save/reopen a project.
3. Pair a Bluetooth MIDI controller and record notes.
4. Record audio with count-in, pre-roll, and punch range.
5. Create multiple takes, split comp regions, swipe/cycle takes, consolidate comp.
6. Record mixer automation in Touch mode and spatial X/Y/Z automation in Latch mode; release latches and replay.
7. Pair Mac Host Mode, instantiate one AU, test parameter sync and editor surface input.
8. Render master and stems on Mac; verify returned WAVs in visionOS Exports.
9. Authenticate Splice MCP, search, preview, Fetch-on-Drop to Arrangement, and map one sample to the Step Sequencer.
10. Load one supported MLX model, run text-only inference, then plugin-editor image inference; cancel one run and unload the model.
11. Leave a project open for an extended session while playing, editing automation, and opening/closing spatial windows; inspect memory and thermals.

## Pass criteria

A public build should not ship if it:

- corrupts or cannot reopen a newly saved project,
- crashes during ordinary first-run navigation,
- cannot complete its platform's advertised basic audio/MIDI workflow,
- falsely reports completed AI parameter edits that were not actually applied,
- silently mutates a project through AI without the configured confirmation gate,
- produces an invalid release artifact or mismatched version metadata.
