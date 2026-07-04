# Buildfix 65 — build.sh Carla install + bundling

`build.sh` now owns the Carla bridge packaging path instead of leaving it as a separate manual script.

## Defaults

- `EMBED_CARLA=1`: bundle Carla when available.
- `AUTO_INSTALL_CARLA=1`: if Carla is missing and Homebrew is available, try to install it during packaging.
- `CARLA_APP=/path/to/Carla.app`: force a specific Carla build.

## Behaviour

1. Search for Carla in common locations:
   - bundled/cached LemmingsStudio helper paths
   - `/Applications/Carla.app`
   - Homebrew Caskroom/Cellar paths
2. If missing and allowed, try:
   - `brew install --cask carla`
   - `brew install carla`
3. Copy Carla into:
   - `LemmingsStudio.app/Contents/Resources/Helpers/Carla.app`
4. Ad-hoc codesign the bundled helper when possible.
5. Write a GPL license reminder next to the helper.

## Opt-outs

```bash
EMBED_CARLA=0 ./build.sh
AUTO_INSTALL_CARLA=0 ./build.sh
CARLA_APP=/Applications/Carla.app ./build.sh
```

Carla is GPL-2.0-or-later. If shipping the bundled Carla binary, ship the correct license and source offer/source link as required by the GPL.
