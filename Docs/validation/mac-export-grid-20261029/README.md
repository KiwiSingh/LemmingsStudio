# Mac export, snapping and loop-tempo repair

The offline audio renderer always excludes the metronome, regardless of the live toggle. The click source also refuses to render in manual/offline mode. Playback scope and click preferences restore on success and failure. Incomplete offline rendering reports an error rather than returning a truncated successful render.

WAV metadata is appended only after AVAudioFile has closed and finalized its audio header. All encoders use explicit float processing buffers. MP3 uses a unique temporary WAV so it cannot overwrite an adjacent user WAV.

Audio imports snap clip placement and region ends to the selected grid. Internal audio transients and MIDI note timing are retained. Loop playback/preview uses musical beat lengths, and time-stretch overlap padding no longer extends the source duration. Manual source BPM correction updates an unextended clip and preserves extended arrangement endpoints. Repeated edge extensions retain the original musical source unit. MIDI imports initialize their full phrase length; legacy four-beat defaults are checked against the actual phrase once at the start of a drag. Duplicate MIDI clips retain loop and tempo metadata.

Validation command: `LemmingsStudio --validate-export-grid OUTPUT_DIRECTORY`. The diagnostic suppresses physical hardware output and tests actual offline renders, exports, import functions, manual tempo/project restore, MIDI/audio repeats and Apple AVURLAsset playback. Quick Look preview generation, RIFF chunk validation and decoded waveform timing are checked separately. Existing AU/VST3 regression diagnostics are also rerun.

This fixes the macOS application. No Windows release or physical audio-device performance is certified by these checks. The project document format is unchanged.
