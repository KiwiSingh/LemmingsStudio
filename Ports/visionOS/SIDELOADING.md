# visionOS v1.0 sideload package

`LemmingsStudio-visionOS-v1.0.ipa` is a resignable sideload artifact for Apple Vision Pro.

The public release builder creates the device app with Xcode code signing disabled, packages it as `Payload/LemmingsStudio.app`, and removes stale app-level signature/provisioning metadata. The public artifact is not tied to the release builder's Apple identity.

Before installation, the end user must sign or re-sign the IPA with their own Apple identity and provisioning workflow using a compatible sideloading process. The exact expiry, refresh behavior, device registration requirements, and account limitations depend on the user's signing method and Apple account type, so release documentation should not promise a fixed installation duration unless the chosen workflow is separately verified.

For developer debugging, `./build-visionos.sh archive` remains available as a separate Xcode archive workflow. The public IPA path is `./build-visionos.sh ipa` or `./release-visionos.sh hardware`.
