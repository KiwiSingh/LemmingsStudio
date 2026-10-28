# Native Windows recording — first live-I/O slice

This phase implements dry input capture, not the complete streaming playback
transport or synchronized overdubbing. `main`, Mac synthesis/UI and upstream
VoxGarden are unchanged. Windows remains Python/Qt with native real-time I/O.

## Implemented

- Active Windows capture endpoint enumeration and explicit selection, with a
  Windows-default option. Endpoint identity is stored in local preferences, never
  in the portable musical document.
- Native event-driven WASAPI shared-mode capture, using the endpoint's mix rate
  and channel format. Float32 and PCM16/24/32 decode into float samples. Windows
  `Audio` multimedia scheduling is requested. COM and capture client ownership
  stay on one native thread; buffers are allocated before capture starts.
- An eight-second preallocated single-producer/single-consumer ring with lock-free
  positions and diagnostic counters. No Python callbacks, decoding, disk writes
  or buffer allocation occur while draining WASAPI packets. A separate Python
  disk worker drains the ring. Overflow stops the take and reports dropped frames;
  device errors and nonfinite input preserve source rather than reporting success.
- Native sample rate/channels, endpoint stream latency, peak, received/dropped
  frames and discontinuities are recorded. Endpoint latency is a driver report,
  **not measured round-trip latency**. Windows may mark the first packet as
  discontinuous; only subsequent discontinuities mark a take for manual review.
- Record/Stop, input selection, elapsed time and input peak in the existing
  transport. Select an **Audio (Recorded)** track and enable **Arm** first.
- Full-channel float WAV dry sources and atomic JSON take manifests. The worker
  flushes the WAV/header and updates recovery metadata every second. Normal Stop
  joins capture, drains queued samples, then closes the file before insertion.
  An abrupt process/power failure can still lose the most recent unflushed data.
- One undoable recorded-clip insertion at the chosen playhead. The existing shared
  Mac AudioClip is mono: the project embeds a channel average; the full-channel
  dry WAV remains available. Save/reopen is still `.lemmingsproject`, with no
  platform-specific project format. Undo never deletes the retained source.
- Session mutation, playback and close are guarded during capture/finalization.
  Close stops recording and asks the user to wait for insertion before closing.
  Failed/discontinuous takes are retained for explicit inspection/import, never
  silently committed. File → **Recover Recording…** opens the retained-take folder.
- Recording storage follows the configured external diagnostics location during
  development; installed Windows defaults to local application-data Recordings.
  No external content/dependencies or licensing changes were introduced.

## Exact boundary and next gates

This is **capture-only dry recording**. Playback is stopped before capture starts.
There is no input monitoring, count-in, punch, loop recording, simultaneous armed
tracks, synchronized overdubbing or latency compensation yet. Input monitoring
must not be enabled until native duplex transport and a shared device clock exist.
The take starts at the selected playhead; no hardware clock alignment claim is made.

The existing full-project worker renderer remains in use for playback/export.
Its Python blocking output worker and full-song PCM preparation are unchanged.
Native streaming graph/output, live parameter/event queues, WASAPI exclusive/ASIO,
MIDI/MPE, PDC, isolated VST3 hosting and app-bound VoxGarden remain subsequent work.
VoxGarden stays bound to LemmingsStudio; upstream repository remains untouched and
no external-host installers will be produced.

Takes are limited to ten minutes to match the current embedded-audio/render limits.
Long-session streaming and large-document memory behavior remain release gates.
There is no disk-quota guarantee; disk errors retain whatever was successfully
written and report failure. OS power-loss guarantees are outside atomic manifest
replacement. Existing Mac tempo-dependent recorded-clip playback rules remain.

## Validation

Tests use the **same native producer ring and format conversion** as WASAPI:
44.1/48/96 kHz, mono/stereo/eight channels, wrapping, concurrent producer/consumer,
exact sample order, silence, overflow, nonfinite values, discontinuity and integer
format sign boundaries. Tests also cover stop/drain, full-channel dry retention,
portable mono insertion, save/reopen, undo/redo, blocked session replacement,
input-open failure, recovery manifests and the actual Qt recording commands.

Installed/bundled checks synthesize packets into the native input backend and run
the real disk/take/project pipeline. They **do not open a microphone** and do not
certify WASAPI driver behavior. Windows CI compiles the actual WASAPI implementation.
Native Windows device/privacy/hot-unplug/listening tests and a hardware latency/soak
matrix remain required; UTM is installation/compatibility evidence only.

Implementation follows [Microsoft's capture packet contract](https://learn.microsoft.com/en-us/windows/win32/api/audioclient/nf-audioclient-iaudiocaptureclient-getbuffer)
and [event-driven stream initialization](https://learn.microsoft.com/en-us/windows/win32/api/audioclient/nf-audioclient-iaudioclient-initialize).
