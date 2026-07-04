# Buildfix 63 — RestorerX-style AU hosting

RestorerX showed the right macOS AU hosting pattern: instantiate an `AVAudioUnit` with `AVAudioUnit.instantiate(...)`, keep the AV node alive, then ask `unit.auAudioUnit.requestViewController` for the vendor editor.

This replaces the previous direct `AUAudioUnit(componentDescription:)` generic-only path. LemmingsStudio now:

- Instantiates AU plug-ins via `AVAudioUnit.instantiate(with:options:)`.
- Requests the vendor editor from the hosted AV node.
- Opens the vendor editor in an NSWindow when the plug-in provides one.
- Falls back to the generic parameter panel only when no vendor UI is returned.
- Keeps VST/VST3 as Finder-reveal only until a VST bridge exists.
