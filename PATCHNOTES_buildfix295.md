# buildfix295

## visionOS workspace switcher compile hotfix

- Removed the remaining conditional concrete `ButtonStyle` ternary in `VisionWorkspaceQuickSwitcher.swift`.
- Uses a stable `.buttonStyle(.bordered)` with explicit tinting for selected/unselected workspace state.
- Preserves buildfix293/294 transport, navigation, print-to-arrangement, metronome-sync, and duplicate-trigger fixes.
