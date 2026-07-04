# Buildfix201 — Third-Party Plug-In Automation + Tempo Automation Persistence/Display

## What this fixes

### 1. Third-party plug-in automation now reaches live DSP

Previous automation fixes only guaranteed stock `DeviceModel` DSP nodes received automation after the static rack param sync. Hosted third-party plug-ins could still be visible in racks/editors without an automation lane actually driving the live plug-in instance.

Buildfix201 adds a native automation surface for hosted Audio Units:

- Hosted AU instruments now conform to `Automatable`.
- AU parameter ids are exposed as stable AU parameter-address strings.
- Automation lanes push values using `scheduleParameterBlock`, not just UI-side value mutation.
- AU effect plug-ins, such as iZotope Neutron/Ozone-style insert effects, can be hosted as live insert processors.
- AU effect automation is applied immediately before the plug-in processes the current block.
- Non-AU/VST bridge entries remain pass-through unless/while bridged externally; native automation requires the hosted AU instance.

### 2. Automation lane menus include third-party AU effect params

The automation editor now lists external AU effect slots alongside stock devices. If the live engine already has the AU instance, it reads params from that live node. If not, it probes the AU so the menu can still populate before playback.

### 3. Tempo automation is saved robustly

Project documents already serialized tempo fields in recent builds, but older project files missing tempo automation keys could fail decoding because those fields were non-optional. Buildfix201 adds decode defaults:

- `tempoAutomationEnabled` defaults to `false`.
- `tempoPoints` defaults to `[]`.
- Base tempo still saves as both `tempo` and `bpm` for compatibility.

### 4. Top BPM counter follows tempo automation

The top transport BPM display now shows the audible tempo at the current playhead when tempo automation is enabled. It no longer stays stuck on the base `project.tempo` while the tempo lane pushes playback up/down.

The BPM text field shows an `AUTO` badge when displaying automated live tempo. Clicking/typing still edits the base project tempo.

### 5. Tempo-aware DSP follows tempo automation

Tempo-aware effects now receive the current automated tempo for the block. The metronome also follows the current automated tempo instead of the static project tempo.

## Changed files

- `Sources/LemmingsStudio/Plugins/AUHosting.swift`
- `Sources/LemmingsStudio/Audio/AudioEngine.swift`
- `Sources/LemmingsStudio/Sequencing/Sequencing.swift`
- `Sources/LemmingsStudio/Views/AutomationEditor.swift`
- `Sources/LemmingsStudio/Views/ProDAWShell.swift`
- `Sources/LemmingsStudio/App/App.swift`
- `Sources/LemmingsStudio/App/ProjectDocument.swift`
