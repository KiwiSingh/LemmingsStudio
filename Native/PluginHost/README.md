# Native plugin host repair

JUCE 8.0.12, pinned revision `29396c22c93392d6738e021b83196283d6e4d850` from https://github.com/juce-framework/JUCE. Open-source AGPLv3 licensing selected; see JUCE-LICENSE.md and upstream module notices. Preserve existing LemmingsStudio and VoxGarden notices. This local test build does not redistribute third-party Serum or Neutron binaries.

Build with CMake 3.24+, C++20 and the pinned JUCE source:

```sh
cmake -S Native/PluginHost -B NativeBuild -DJUCE_SOURCE=/path/to/JUCE -DCMAKE_BUILD_TYPE=Release
cmake --build NativeBuild -j2
swift build -c release
```

Copy liblemmings_plugin_host.dylib into the app Contents/Frameworks directory and the Swift executable/resources into the existing bundle, preserving bundled runtime/media resources; sign the resulting bundle. The host C API is declared in Host.h. Swift uses the exact live processor for audio, MIDI, editor and state. No automatic Finder/Carla handoff.

Validation: app --validate-hosting /path/to/output; add --format-au for AU. Diagnostics use installed Serum 2 and Neutron 5 and suppress physical audio output. They do not certify physical microphone/MIDI hardware or crash isolation. Native VST3 hosting is currently in-process.
