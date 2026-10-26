#!/bin/sh
set -eu
: "${LEMMINGS_TEST_OUTPUT:?Set LEMMINGS_TEST_OUTPUT to an external build directory}"
mkdir -p "$LEMMINGS_TEST_OUTPUT"
export CLANG_MODULE_CACHE_PATH="$LEMMINGS_TEST_OUTPUT/clang-modules"
export SWIFT_MODULECACHE_PATH="$LEMMINGS_TEST_OUTPUT/swift-modules"
swiftc -swift-version 5 -module-cache-path "$SWIFT_MODULECACHE_PATH" \
 Sources/LemmingsStudio/Theory/*.swift \
 Sources/LemmingsStudio/Instruments/*.swift \
 Sources/LemmingsStudio/Effects/*.swift \
 Sources/LemmingsStudio/Sequencing/*.swift \
 Sources/LemmingsStudio/Audio/Automation.swift \
 Sources/LemmingsStudio/Audio/Tempo.swift \
 Sources/LemmingsStudio/Audio/Warp.swift \
 Sources/LemmingsStudio/Audio/DrumPadSupport.swift \
 Sources/LemmingsStudio/Plugins/Plugins.swift \
 Sources/LemmingsStudio/Generative/DeviceTranslationLayer.swift \
 Sources/LemmingsStudio/Integration/CarlaBridgeSupport.swift \
 Sources/LemmingsStudio/App/ProjectDocument.swift \
 Sources/LemmingsStudio/App/DocumentPreservation.swift \
 Tests/ProjectCompatibility/main.swift \
 -o "$LEMMINGS_TEST_OUTPUT/project-contract-check"
"$LEMMINGS_TEST_OUTPUT/project-contract-check" "$LEMMINGS_TEST_OUTPUT/swift.lemmingsproject"
