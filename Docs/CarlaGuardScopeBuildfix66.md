# Carla guard scope buildfix 66

Fixes a Swift compile failure in `CarlaBridgeSupport.vendorCopyInstalledCarlaIfPossible()`.

The previous guard statement attempted to return `source` from the `else` branch while `source` may not have been initialized. The function now separates the cases:

- existing vendored Carla -> return vendored URL
- no detected Carla -> return nil
- detected Carla already at vendored path -> return source
- detected external Carla -> copy into LemmingsStudio support folder
