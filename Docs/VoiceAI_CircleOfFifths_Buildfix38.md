# Buildfix 38 — Voice AI surface + Circle of Fifths key picker

This build surfaces the consent-first singing voice workflow directly in the main DAW UI and makes project-key selection available from both the compact transport dropdowns and the Circle of Fifths.

## Voice AI UI

The right dock now includes a **Voices** tab with:

- voice-to-voice / singing conversion input selection
- model selection from the built-in ethical starter catalogue plus imported models
- output-folder selection
- render-and-import action
- voice cloning prep with explicit consent / dataset-guidance gates
- manual model import

The renderer still uses the existing bundled Python voice transform service path. If the runtime or service script is missing, the UI reports that through the status line instead of hiding the feature in Settings.

## Project key workflow

The transport key selectors now route through `AppState.applyProjectKey(...)`, so changing the root or scale updates the project, rebuilds the engine graph, and refreshes Discord/key-aware status.

The Circle of Fifths is also available from the transport via the circle button. Choosing a root/scale on the circle immediately updates the same project fields used by the top dropdowns, so both controls stay synchronized.

