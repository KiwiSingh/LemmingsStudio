# Buildfix169 — Progressive User Library Scanning

Scope guard: this patch only touches the User Library scanner path in `App.swift`.

## What changed

- User Library scans now populate the browser progressively instead of waiting for the entire folder tree to finish.
- First-time scans classify files in background batches and publish each batch to the UI as soon as it is ready.
- Folder groups appear as discovered items are indexed, so large libraries no longer feel like an empty frozen browser.
- If a cached index exists, the browser still loads it immediately while a lightweight metadata check runs in the background.
- If the signature is unchanged, LemmingsStudio keeps the cached index and does not reclassify the entire library.
- If files were added, deleted, or modified, the browser clears stale results and repopulates with fresh indexed batches.

## Untouched

Stem splitter logic, stem backend code, stem packaging, recording, code signing, Splice, Serum/Serum 2/plugin fixes, AU hosting, RVC/build.sh, export, mixer clipping, warp controls, metronome/count-in, Finder import, MIDI learn, and automation were not touched.
