# LemmingsStudio buildfix288

## visionOS icon and workspace launcher hotfix

- Replaced the incorrect flat `AppIcon.appiconset` with a visionOS `AppIcon.solidimagestack` containing a full-canvas 1024×1024 back layer.
- Reworked the crowded top bar into compact project, transport, snap, Workspaces, and Appearance groups.
- Moved secondary tools into clearly named menu sections instead of compressing more than twenty SF Symbols into one unlabeled row.
- Preserved all existing `openWindow(id:)` destinations while making their labels visible and discoverable.
- Retains buildfix286 audio-route launch hardening and buildfix287 Bash nounset fix.
