# LemmingsStudio buildfix250

## visionOS Desktop Plug-in Bridge

- Added Bonjour discovery for `_lemmings-plugin._tcp` desktop bridge hosts.
- Added local-network permission and Bonjour service declarations to visionOS Info.plist.
- Added six-digit pairing workflow; the macOS host presents the code in an NSAlert on connection.
- Added visionOS Desktop Bridge window for host discovery, pairing, plug-in browsing, loading, generic parameter editing, and audio-return toggling.
- Added a macOS bridge server that scans Audio Units, instantiates a requested component in an isolated AVAudioEngine graph, enumerates parameters, accepts MIDI, exposes state messages, and streams stereo PCM chunks.
- Added live CoreMIDI forwarding from visionOS to the active desktop plug-in.
- Added project MIDI clip forwarding from visionOS transport to the active desktop plug-in.
- Added CC and pitch-bend forwarding.
- Added generic normalized parameter control from visionOS.
- Added state request/restore protocol messages.
- Added first experimental live audio return path using 512-frame interleaved Float32 stereo chunks encoded over the JSON/TCP bridge.
- Preserved provider abstraction for future macOS VST3, Windows VST3, and experimental Wine-host providers.

## Deliberate limitations

- buildfix250 Mac host scans native macOS Audio Units only.
- Windows VST3 provider is not connected to this network protocol yet.
- Experimental Wine provider remains a protocol/provider seam, not an embedded Wine runtime.
- Audio return is the first debuggable transport and is not yet optimized for minimum latency/jitter.
- Offline bridge rendering currently returns an explicit not-yet-implemented response; live hosting/control/audio return is the focus of this pass.
- One desktop plug-in instance is the intended validation workflow for the first bridge pass, although the wire protocol and host storage are instance-ID based.
