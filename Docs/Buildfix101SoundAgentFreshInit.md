# Buildfix101 — Sound Agent starts each AI patch from Init/default

This build changes the Sound Agent launch/apply flow so a new AI sound design no
longer tries to overwrite whatever patch currently lives inside Serum 2 or another
hosted AU instrument.

## Why

Overwriting an arbitrary existing patch is not deterministic: old oscillator state,
FX, modulation, hidden macro assignments, and previously exposed AU parameters can
bleed into the new generated sound. For prompts like “Tiesto-style epic bass”, that
can leave the agent fighting a previous square/noise patch instead of building a
clean saw-body bass.

## Changes

- `DescribeASoundView.design()` now asks the app for a fresh Sound Agent target.
- `LemmingsStudioApp.prepareSoundAgentTarget(resetForNewPatch:)` accepts a reset flag.
- Hosted Audio Unit targets clear their cached live AU instance before a new AI patch.
- The engine rebuilds immediately afterward, causing Serum 2 / AU instruments to be
  instantiated from their vendor Init/default state before the agent applies knobs.
- Built-in Analog also rebuilds before a new AI patch, so stock-synth sound design
  starts from the stock default voice rather than a previously modified live synth.

## Untouched

Splice/MCP integration, arrangement resizing, metronome/count-in, and AU parameter
mapping were not touched in this pass.
