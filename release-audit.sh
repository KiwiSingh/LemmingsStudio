#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

failures=0
check() { local label="$1"; shift; if "$@" >/dev/null 2>&1; then printf 'PASS  %s\n' "$label"; else printf 'FAIL  %s\n' "$label"; failures=$((failures+1)); fi; }
contains() { grep -Fq "$2" "$1"; }

echo 'LemmingsStudio buildfix272 release audit'
echo '==========================================='
check 'macOS public version is 2.0' contains build.sh 'APP_VERSION_SHORT="${APP_VERSION_SHORT:-2.0}"'
check 'macOS build metadata is 2.0.0' contains build.sh 'APP_BUILD_VERSION="${APP_BUILD_VERSION:-2.0.0}"'
check 'Windows app version is 2.0.0' contains Ports/Windows/src/LemmingsStudio.Windows/LemmingsStudio.Windows.csproj '<Version>2.0.0</Version>'
check 'Windows assembly version is 2.0.0.0' contains Ports/Windows/src/LemmingsStudio.Windows/LemmingsStudio.Windows.csproj '<AssemblyVersion>2.0.0.0</AssemblyVersion>'
check 'Windows installer version is 2.0.0' contains Ports/Windows/installer/LemmingsStudio.iss '#define AppVersion "2.0.0"'
check 'visionOS marketing version is 1.0' contains Ports/visionOS/project.yml 'MARKETING_VERSION: 1.0'
check 'visionOS build version is 1.0.0' contains Ports/visionOS/project.yml 'CURRENT_PROJECT_VERSION: 1.0.0'
check 'visionOS simulator artifact name is versioned' contains Ports/visionOS/build-visionos.sh 'LemmingsStudio-visionOS-v1.0-Simulator.zip'
check 'visionOS IPA artifact name is versioned' contains Ports/visionOS/build-visionos.sh 'LemmingsStudio-visionOS-v1.0.ipa'
check 'visionOS public IPA disables builder-side code signing' contains Ports/visionOS/build-visionos.sh 'CODE_SIGNING_ALLOWED=NO'
check 'visionOS public IPA uses Payload packaging' contains Ports/visionOS/build-visionos.sh 'Payload/LemmingsStudio.app'
check 'visionOS sideloading guide exists' test -f Ports/visionOS/SIDELOADING.md
check 'Linux is source-only in version matrix' contains VERSION_MATRIX.md 'Linux: source-only distribution'
check 'Splice MCP client source exists' test -f Ports/visionOS/LemmingsStudioVision/Agentic/VisionSpliceMCP.swift
check 'Mac Host Mode server source exists' test -f Sources/LemmingsStudio/Bridge/DesktopPluginBridgeServer.swift
check 'visionOS bridge client source exists' test -f Ports/visionOS/LemmingsStudioVision/Bridge/VisionDesktopBridgeClient.swift
check 'Semantic Project Graph source exists' test -f Sources/LemmingsStudio/Semantic/SemanticProjectGraph.swift
check 'Living Project Memory source exists' test -f Ports/visionOS/LemmingsStudioVision/Memory/VisionLivingProjectMemory.swift
check 'MLX package is pinned' contains Ports/visionOS/project.yml 'version: 3.31.4'
check 'Wine staging guide exists' test -f Ports/visionOS/WINE_ARM64_STAGING.md

if [[ "$failures" -ne 0 ]]; then
  echo
  echo "Release audit FAILED with $failures failing gate(s)." >&2
  exit 1
fi

echo
echo 'Release audit PASSED.'
