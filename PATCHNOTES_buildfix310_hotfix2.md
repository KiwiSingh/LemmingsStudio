# buildfix310 hotfix 2

Release-blocker fixes:

1. visionOS app icon metadata
   - Removed malformed hand-authored `CFBundleIcons` / string-valued `CFBundlePrimaryIcon` entries from both `project.yml` and `Info.plist`.
   - The target continues to use `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon` and the layered `AppIcon.imagestack`.
   - Xcode/actool now owns generated primary-icon bundle metadata instead of being overridden by an incompatible manual plist shape.

2. Spatial keyboard stuck-note lifecycle
   - Added `SpatialEventGesture.onEnded` cleanup.
   - Reconciles currently ongoing event IDs on every update and releases notes whose touch IDs disappeared.
   - Preserves independent multi-touch chord voices and glissando transitions while preventing orphaned sustained notes.
