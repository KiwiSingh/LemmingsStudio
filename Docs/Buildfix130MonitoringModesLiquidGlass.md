# Buildfix130 — Track Monitoring Modes + Liquid Glass Pass

## Audio-track monitoring modes

Audio tracks now expose an Ableton-style monitor selector with three modes:

- **In** — direct/hardware monitoring mode. Lemmings records the selected input channel, but deliberately does **not** create a software loopback route to the main output. This avoids slapback/echo when using microphones/interfaces that already provide monitoring, such as the Revelator Dynamic.
- **Auto** — record-ready automatic mode. In this build, Lemmings still mutes software loopback during record takes so recording does not echo back into the headphones/speakers.
- **Off** — no input monitoring. Armed audio tracks still record the chosen device/channel.

The old boolean `inputMonitor` field remains for backward compatibility with older project files, but new projects also save `audioInputMonitorMode`.

## UI changes

- Audio track headers now show a compact `In` / `Auto` / `Off` monitor menu.
- Track context menus now include `Monitor Mode` alongside `Input Device` and `Input Channel`.
- The Recording panel uses the same monitor-mode picker.
- Duplicating tracks preserves the selected monitor mode.

## Liquid Glass-inspired design pass

The main ProDAWShell received a visual pass inspired by translucent, layered glass UI:

- gradient + subtle cyan/purple bloom window background;
- ultra-thin material shells around Browser, Workspace, Detail Deck, Right Dock, and Transport;
- glass highlight overlays, soft borders, and deeper shadows;
- lighter glass panel palette and brighter focus color.

This is intentionally "inspired by" Liquid Glass rather than a literal clone.

## Not touched

Splice MCP/download/preview, Sound Agent, Demucs/stems, AU hosting, Piano Roll, Mixer FX routing, Browser drag/drop, and count-in/metronome timing were not changed.
