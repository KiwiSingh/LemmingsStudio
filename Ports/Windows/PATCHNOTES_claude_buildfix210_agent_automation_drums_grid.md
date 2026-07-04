# LemmingsStudio Windows — buildfix210 (Claude): agent gains automation, drum grooves & note-grid parsing

Closes the gap between the Windows agent and the Mac build's AIAssistant.

## set_automation (new)
- Op `{"op":"set_automation","track","node":"instrument|<idx>","param":"Cutoff","points":[{"beat","value"}]}`.
- The executor resolves the node to a `DeviceSlot`, finds or creates a track
  `AutomationLane` (Kind = DeviceParameter, DeviceId + ParameterId set), and replaces its
  points — so the agent can draw smooth multi-point parameter curves.

## set_drum_groove (new)
- Op `{"op":"set_drum_groove","track","genre":"Lo-Fi|Tech House|Slap House|EDM|Breakbeat"}`.
- Since the Windows port has no step sequencer, the 16-step grooves from the Mac
  (`DrumKitLibrary.groove`) are voiced to **GM drum MIDI** (kick 36, snare 38, clap 39,
  closed/open hats 42/46, 808 35, crash 49) and written into clip 0 as a one-bar pattern —
  same feel, expressed as notes this engine already plays.

## Note-grid / prose parser (new)
- Ported the Mac's `parseExplicitMIDINotes` + helpers. When a model answers with a grid like
  `Bar 1: C2 - - - | E2 - G2 -` instead of JSON, the agent now extracts bar lines, tokenises
  cells, reads note names (with #/b and octaves), honours `-`/`_`/`~` as holds and
  `r`/`rest`/`0` as rests, and converts it all to MIDI. Parsed notes take priority over the
  deterministic generators, and the clip is sized to fit.

## Honest scope
- Drum grooves render as a single bar in clip 0 (loop it in the arrangement for length);
  velocities are fixed per voice.
- Automation lanes are created on the track model; how each curve is rendered live depends on
  the existing automation engine.
- Authored on Linux without the .NET toolchain — brace-balanced, standard
  System.Text.Json / System.Text.RegularExpressions; expect at most minor fixups on first build.
