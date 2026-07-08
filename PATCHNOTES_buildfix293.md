# LemmingsStudio buildfix293

## visionOS transport, sequencer UX, and print visibility

This buildfix addresses runtime usability issues found during simulator testing after buildfix292.

### Primary workspace navigation
- The main visionOS window now keeps Arrangement, Piano Roll, Step Sequencer, and Mixer as primary workspaces inside one shared window.
- The primary workspace switcher uses direct buttons backed by shared model state instead of spawning additional windows for those four core editing views.
- The top bar is split into two rows so controls remain legible and hittable at realistic window widths.
- Project commands are grouped under a compact Project menu; transport and metronome state remain directly visible.

### Step Sequencer print behavior
- Print to Arrangement now places newly created SEQ tracks at the top of the Arrangement track list so the printed result is immediately visible.
- Successful print switches the primary workspace to Arrangement and seeks to the print start beat.
- The live sequencer is disabled after a successful print to prevent double-triggering between the live pattern and the newly printed MIDI clips.
- Status text explicitly reports the number of printed lanes, insertion beat, and the live-sequencer disable action.

### Sample-clock metronome
- Metronome scheduling moved from the 16 ms UI transport callback into the real-time audio render clock.
- Click timing is advanced in samples using tempo and sample rate, with bar accents derived from beats-per-bar.
- Starting, pausing, stopping, and toggling the metronome now reconfigure the sample-clock metronome state directly.

### Repeated-note prevention
- The main repeated-note case observed after printing was caused by simultaneous playback of the live Step Sequencer and printed Arrangement clips.
- Successful print now disables live pattern playback, preventing duplicate triggers while preserving the printed tracks.

### Validation
- 59 visionOS Swift source files parse successfully.
- visionOS shell scripts pass `bash -n`.
- Asset catalog JSON parses successfully.
- `release-audit.sh` passes all 20 gates.
- ZIP integrity verified after packaging.
