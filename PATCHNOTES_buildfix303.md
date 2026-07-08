# buildfix303 — visionOS export, AI backend abstraction, Claude, and Splice OAuth

This build changes only the visionOS target.

## Native local export
- Adds a Local Export window accessible from Project and Workspaces.
- Adds native stereo master export to WAV 24-bit, WAV 32-bit float, AIFF 24-bit, and M4A/AAC.
- Adds local post-fader stem export, one file per non-muted track.
- Adds sample-rate selection, normalization, beat-range selection, and tail duration.
- Exports are written under Documents/LemmingsStudio Exports and can be shared through the system share sheet.
- The stable native renderer handles project audio clips and stock MIDI/drum voices locally. Desktop plug-in return rendering remains deferred.

## Agent backend abstraction
- Adds `VisionAgentProviderKind`, `VisionAgentRequest`, `VisionAgentResponse`, and `VisionAgentBackend`.
- Providers now normalize into the existing shared tool-plan parser and confirmation/execution layer.
- Claude API is the default provider for the stable minimal-build workflow.
- Local MLX remains available for experimental full-fat builds.
- Mac AI Bridge is represented as a Coming Soon provider stub only; no macOS code is changed.

## Claude API backend
- Adds direct Messages API integration through `https://api.anthropic.com/v1/messages`.
- API keys are stored in Keychain, not UserDefaults or project files.
- Model and max-output-token controls are exposed in the Agent panel.
- Claude responses are normalized into the same constrained tool-plan schema used by the existing local agentic layer.
- Tool plans still require confirmation before DAW mutations are executed.

## Splice OAuth / MCP login
- Adds OAuth protected-resource and authorization-server metadata discovery.
- Adds dynamic client registration when advertised by the authorization server.
- Adds PKCE S256 authorization flow.
- Opens the system browser for Splice authorization.
- Adds `lemmingsstudio://splice/callback` handling.
- Exchanges the authorization code, stores access/refresh credentials in Keychain, adds Bearer authorization to MCP requests, and reconnects automatically after callback completion.

## Notes
- The Splice OAuth flow is implemented against standards-based OAuth metadata and requires live endpoint validation on Vision Pro/Safari.
- Native export parity for third-party desktop plug-in returns remains deferred with Mac Host Mode.
