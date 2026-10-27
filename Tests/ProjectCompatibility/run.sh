#!/bin/sh
set -eu
: "${LEMMINGS_TEST_OUTPUT:?Set LEMMINGS_TEST_OUTPUT to an external build directory}"
mkdir -p "$LEMMINGS_TEST_OUTPUT"
export CLANG_MODULE_CACHE_PATH="$LEMMINGS_TEST_OUTPUT/clang-modules"
export SWIFT_MODULECACHE_PATH="$LEMMINGS_TEST_OUTPUT/swift-modules"
# Only the unseeded Indian-percussion noise call is instrumented for a
# reproducible numerical oracle. Product sources remain unchanged.
python3 - "$LEMMINGS_TEST_OUTPUT" <<'PYREF'
from pathlib import Path
import sys,hashlib,json
root=Path(sys.argv[1]);source=Path('Sources/LemmingsStudio/Instruments/Instruments.swift')
text=source.read_text();assert text.count('Float.random(in: -1...1)')==1
(root/'Instruments.swift').write_text(text.replace('Float.random(in: -1...1)','parityNoise()')+"\nvar parityNoiseSeed: UInt64 = 0xC0FFEE\nfunc parityNoise() -> Float { parityNoiseSeed = parityNoiseSeed &* 6364136223846793005 &+ 1442695040888963407; return Float(Double(parityNoiseSeed >> 33) / Double((UInt64(1)<<31)-1) * 2 - 1) }\n")
(root/'noise-oracle.json').write_text(json.dumps({'source':str(source),'sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'instrumentation':'Only Float.random in IndianPercussion replaced by seeded LCG; product source untouched'}))
PYREF
swiftc -swift-version 5 -module-cache-path "$SWIFT_MODULECACHE_PATH" \
 Sources/LemmingsStudio/Theory/*.swift \
 Sources/LemmingsStudio/Views/LemmingsTheme.swift \
 Sources/LemmingsStudio/Instruments/DSP.swift \
 Sources/LemmingsStudio/Instruments/Drums.swift \
 "$LEMMINGS_TEST_OUTPUT/Instruments.swift" \
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
