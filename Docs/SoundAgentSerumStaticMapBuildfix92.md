# Buildfix92 — Sound Agent Serum/Serum 2 Static Control Map

Scope: agentic AI + hosted AU parameter matching only. Splice MCP/download/preview integration is intentionally untouched.

## Problem

The Sound Agent could now launch Serum 2 and deliver AU automation events, but the result was musically wrong because the agent layer was still thinking in a small set of generic controls. A prompt like `Create me an '80s style synthwave pluck` should not collapse to a tiny macro patch. It needs to reason in the full Serum/Serum 2 synthesis vocabulary and then write every matching AU parameter that Serum exposes to the host.

## Fix

### DeviceTranslationLayer.swift

- Added a broad static Serum/Serum 2 parameter reference used in the LLM system prompt.
- Added a deterministic Serum recipe layer that expands broad prompts into many concrete Serum-style controls.
- The synthwave/pluck recipe now covers oscillators, sub/noise, filter routing, amp envelope, modulation envelope, width FX, delay, reverb, distortion/saturation, EQ, master volume, and polyphony.
- The original user prompt remains a first-class source, so weak/sparse JSON from a local model cannot erase the user's sound-design intent.

### AUHosting.swift

- Added a broad Serum alias mapper for terse AU labels such as `A Vol`, `A WTPos`, `Fil Cutoff`, `Env1 Dec`, `Cho Mix`, `Dly Wet`, and `Verb Wet`.
- Added a guarded fuzzy fallback for Serum-ish parameters.
- Still refuses false success if zero AU events are scheduled.

## Important limitation

This patch intentionally makes the LemmingsStudio agent layer's Serum map large. However, AU automation can only hit parameters that the Serum AU actually publishes to the host at that moment. Serum 2 has dynamic/exposed-on-demand automation behavior for some controls, especially FX. The agent now tries the large vocabulary and schedules every matched exposed parameter, but it cannot force a proprietary AU to publish hidden internal parameters without plug-in support.
