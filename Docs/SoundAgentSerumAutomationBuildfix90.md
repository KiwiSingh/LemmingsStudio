# Buildfix90 — Sound Agent → Serum 2 live AU automation

Buildfix88 fixed the editor-instance mismatch, but AU parameter writes could still be a no-op for Serum 2-style instruments because Lemmings only mutated `AUParameter.value` / `setValue` on the host-side object. Some Audio Units react to that, but real DAW automation should also be sent through `AUAudioUnit.scheduleParameterBlock` so the plug-in processor and vendor editor receive a host automation event.

This build changes the live AU path so the Sound Agent:

- keeps targeting the same live `HostedAUInstrument` instance used by the editor and audio engine;
- resolves `macro_1`, `macro 1`, `Macro 1`, and similar names to actual AU macro parameters more robustly;
- sends every applied value through `scheduleParameterBlock(AUEventSampleTimeImmediate, ...)`;
- mirrors the value onto the `AUParameter` object so the generic editor and parameter reads stay in sync;
- refuses success if zero AU automation events were delivered;
- includes skipped/unmatched knobs in the result message so Serum's dynamic/non-exposed parameters are not silently ignored.

Important Serum 2 caveat: many internal Serum 2 parameters are dynamic and may not appear to AU hosts until they are explicitly exposed/automated by Serum. The safest automatable surface is therefore the macro controls plus whichever parameters Serum exposes in its current parameter tree. This build does not touch Splice/MCP integration.
