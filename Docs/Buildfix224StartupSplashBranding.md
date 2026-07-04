# Buildfix224 Startup Splash Branding

Adds a branded MagmaVance pre-splash before the existing LemmingsStudio startup splash on both macOS and Windows.

## macOS
- Bundles `Sources/LemmingsStudio/Resources/MagmaVancePreSplash.mp4`.
- Shows the upscaled, bloom-polished startup video in a borderless SwiftUI/AVKit panel before the normal LemmingsStudio splash.
- Adds `© MagmaVance LLC. All rights reserved.` to the bottom of the LemmingsStudio splash panel.

## Windows
- Adds `StartupSplashForm.cs`.
- Shows a lightweight animated frame sequence generated from the polished pre-splash video before the LemmingsStudio splash.
- Adds the MagmaVance copyright text to the Windows LemmingsStudio splash.
- Adds the startup splash assets to the Windows project as copied content so they are included in publish/installer outputs.

## Media processing
- The uploaded vertical startup video was upscaled to 1080x1920, lightly sharpened, and given a subtle bloom/glare pass to reduce the compressed look.
- The Windows port uses a short 15 fps frame sequence to avoid fragile media-player/WebView runtime dependencies.
