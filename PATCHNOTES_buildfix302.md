# buildfix302 — visionOS project persistence

This build adds the first complete visionOS project persistence workflow.

## Added

- `.lemmingsproject` package document format.
- Versioned `project.json` manifest (`version: 3`).
- Embedded `Audio/`, `Samples/`, `Takes/`, `Analysis/`, `Metadata/`, and `Recovery/` package folders.
- Asset-path rewriting so audio clips, Step Sequencer samples, takes, and consolidated comps reopen from package-relative paths.
- Save, Save As, Open, Recent Projects, 45-second recovery autosave, and Recover Autosave.
- Staged package replacement with rollback backup for save-in-place operations.
- Previous manifest preservation in `Recovery/project.recovery.json` during save-in-place.
- Legacy JSON/`.lemmings` opening compatibility; legacy projects are migrated through Save As rather than overwritten as packages in place.
- Package-aware audio and Step Sequencer sample path resolution.
- Package-aware Splice sample storage path resolution.

## Release version

Public visionOS version remains 1.0 (`MARKETING_VERSION 1.0`, build `1.0.0`).
