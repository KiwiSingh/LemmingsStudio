# Buildfix156 — selected-clip stem splitting, empty-area Finder drops, BPM metadata

Scope guard: this patch does not touch recording, code signing, Splice, Serum/Serum 2/plugin hosting, RVC/build.sh, Demucs packaging, Piano Roll editing, mixer clipping, warp controls, or metronome/count-in.

## Stem Splitter workflow

- Stem Splitter no longer opens a file browser by default.
- The Studio stem splitter now operates on the currently selected Arrangement audio clip.
- The audio-clip context menu now exposes **Stem Split Selected Clip**.
- If the selected clip still has its source file, that file is sent to the stem backend.
- If the source file is unavailable, LemmingsStudio writes the selected clip's active audio buffer to a temporary WAV and separates that instead.
- Selected stems are imported automatically to new audio tracks after extraction.
- The existing Merge-to-single-track and Submix-group options are now grouped under the stem/output routing menus.
- Stem extraction progress is visible in the Studio panel and compact transport area.

## Finder drop on empty Arrangement space

- Root Arrangement Finder drops now create a new track instead of silently importing onto the selected track.
- The bottom new-track drop zone now accepts drops across the entire row, not only the lane rectangle.
- Dropping on an existing track still imports to that track.

## BPM/key metadata on export

- WAV export writes RIFF INFO metadata including `IBPM`, `IKEY`, project title, and a tempo/key comment.
- MP3 export via ffmpeg/lame writes BPM/key metadata during transcoding.
- LemmingsStudio's own tempo detector now checks exported WAV `IBPM` metadata before falling back to onset guessing.
