# Buildfix 110 — Browser, Groups/Buses, FX Chains, Drag-Drop Routing

Scope: browser/workflow/mixer/group routing only. Splice MCP/download/preview code was intentionally not modified.

## Browser

- User Library browsing now treats local samples, loops, and MIDI as first-class browser assets.
- MIDI files can be dragged/dropped or inserted from the browser into a MIDI/instrument track.
- A small Standard MIDI File importer converts note on/off events into Piano Roll clips.
- FX/Plugins browser continues to expose stock MIDI effects, stock audio effects, stock instruments/racks, and scanned AU/VST/VST3 plug-ins with search and categorized grouping.
- Arrangement has a bottom drop zone: dragging a sample/MIDI/plugin below existing tracks creates a new target track instead of forcing the selected track.

## Track selection and grouping

- Shift-select tracks in the track list/mixer.
- Cmd+G groups all selected tracks.
- Shift+Cmd+G ungroups selected tracks.
- Deleting with multiple selected tracks deletes the selected set.

## Groups and buses

- Track groups have their own devices, volume, pan, mute, solo, and automation lanes in the data model.
- Group FX are rendered after member track inserts and before the member track hits the master/returns.
- Return buses already supported FX; buildfix110 surfaces Add FX in the compact mixer bus strips too.

## Mixer FX workflow

- Compact mixer strips show the track insert chain.
- Drag FX/plugins from the browser directly onto mixer strips.
- Shift-select multiple FX pills on a strip, then use the context menu to create an FX Rack/chain.
- FX pills have context-menu ordering actions for quick Move Earlier / Move Later.

## Caveats

- Third-party plug-in display/SysEx protocols remain vendor-specific.
- MIDI import handles normal SMF note events. Exotic controller-only MIDI files may import as an empty/editable clip.
