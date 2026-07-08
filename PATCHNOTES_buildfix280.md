# buildfix280

- Avoided a Swift 6/Xcode 27 type-checker diagnostic failure in the visionOS Step Sequencer by applying visionOS-native `glassBackgroundEffect` directly to sequencer cards instead of routing those expressions through the generic `lemmingsGlass` modifier.
- Tightened Spatial Transform slider setter actor annotations and marshalled setter execution through the MainActor to address Swift 6 actor-isolation warnings.
- Public versions unchanged: macOS 2.0, Windows 2.0, visionOS 1.0.
