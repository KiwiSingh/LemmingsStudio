# Mac plugin, recording and sequencer repair

This branch preserves the latest locally built Mac source in addition to the targeted repairs. The root Mac working tree and Windows rewrite branch remain unchanged. The installed app will be version 2026.10.29.2.

Repairs: real in-app VST3 hosting using a single processor for audio/editor/state; exact AU bundle metadata and live-instance editors; per-track arm/input menus and source filtering; Piano Roll Cmd+A/Shift-arrow key handling; file-URL-first one-shot drops with stable imported copies and replacement audio.

VST3 integration validation uses Serum 2 and Neutron 5 from Zweidrive: audio rendering, actual editor open/reopen, state restore, project persistence, synthetic armed MIDI source filtering, audio input selection metadata, actual Piano Roll key events and one-shot replacement audio. Physical microphone/MIDI and native hardware latency remain untested. In-process VST3 crash isolation and plugin delay compensation are not certified by these checks. Third-party plugin binaries are not distributed.

See Native/PluginHost/README.md for dependency pin and build instructions. Matching application source and pinned JUCE source are also supplied in the app's BuildInformation/Matching-Mac-Source.zip.
