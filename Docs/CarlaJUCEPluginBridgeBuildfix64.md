# Buildfix 64 — Carla/JUCE-style plug-in bridge path

LemmingsStudio now treats AU/VST/VST3 hosting as a layered system:

1. Native Swift/AVAudioUnit hosting for Audio Units where possible.
2. RestorerX-style AU vendor UI where the SDK exposes one.
3. Generic AU parameter fallback when vendor UI is unavailable.
4. Carla-style external process bridge for VST/VST3 and awkward plug-ins.
5. Future JUCE helper can replace the Carla launcher with a bundled first-party bridge.

Carla is GPL-2.0-or-later, so bundling a Carla binary means shipping the required
license/source obligations. For beta, the app can cache an installed Carla.app in
Application Support or start `brew install carla` in Terminal when the user presses
Prepare Carla Bridge. A packaging script is provided at `Scripts/bundle_carla.sh`
for builds where the licensing/source bundle is prepared.

The main DAW process no longer reveals VST/VST3 plug-ins in Finder as the first
UX path. It tries the bridge boundary instead, which also improves crash isolation.
