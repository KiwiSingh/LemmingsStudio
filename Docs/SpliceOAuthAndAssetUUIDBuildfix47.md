# Splice OAuth + Asset UUID Buildfix 47

## OAuth callback behavior

Splice login now starts with `ASWebAuthenticationSession` instead of `NSWorkspace.shared.open(...)`.

The redirect URI can remain `lemmingsstudio://splice-oauth`, but the callback is captured by the authentication session attached to the already-running app. This avoids sending the callback through LaunchServices, which was visibly launching another copied LemmingsStudio bundle when multiple build folders existed on disk.

The older app URL handler and localhost handoff remain as fallback paths only.

## Asset UUID validation

Splice MCP download/fetch tools validate `asset_uuid` as a UUID. Some MCP text responses label a Splice sample page URL as `Asset UUID`, for example:

```text
https://splice.com/sounds/sample/.../frc-909-drum-industrial-techno-dist-124-bpm-wav
```

That is not a UUID and must not be passed to an `asset_uuid` argument.

Buildfix 47 only fills UUID-like tool arguments when the value matches:

```text
xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
```

If the response only contains a Splice page URL, the result stays page-only instead of causing a schema validation error.
