# Splice drag/drop and filtering

LemmingsStudio treats Splice samples as draggable browser items, not one-click import buttons.

- Drag a result to Arrangement to create/import an audio clip.
- Drag a result to a Step Sequencer cell to replace that lane/slot with the one-shot and enable that step.
- Drag a result to a Step Sequencer row label to replace the lane sound without enabling a step.

The browser exposes key, BPM, and genre fields. These are appended to the MCP search query and then applied locally when Splice returns structured metadata such as `bpm`, `key`, `tags`, `instrument`, `sound_type`, `pack`, or creator fields. BPM filtering uses a small tolerance because sample metadata often differs by a few BPM.
