import SwiftUI
import AVKit
import UIKit

/// buildfix254: visionOS-native startup branding.
///
/// The macOS build already carries the MagmaVance pre-splash and the
/// LemmingsStudio splash assets. This view brings the same brand sequence to
/// the visionOS target while keeping it lightweight and immersive-friendly.
struct VisionStartupBrandingView: View {
    @Environment(VisionStudioModel.self) private var model
    @State private var player: AVPlayer?
    @State private var showSplash = false

    private let preSplashName = "MagmaVancePreSplash"
    private let splashName = "LemmingsSplash"

    var body: some View {
        ZStack {
            VisionThemeBackground(theme: model.visualTheme)
                .ignoresSafeArea()

            RoundedRectangle(cornerRadius: 44, style: .continuous)
                .fill(.thinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 44, style: .continuous)
                        .stroke(.white.opacity(0.20), lineWidth: 1)
                )
                .shadow(radius: 30, y: 18)
                .frame(maxWidth: 880, maxHeight: 520)
                .padding(44)

            VStack(spacing: 22) {
                if showSplash {
                    splashImage
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                } else if let player {
                    VideoPlayer(player: player)
                        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                        .frame(maxWidth: 760, maxHeight: 360)
                        .transition(.opacity)
                } else {
                    fallbackPreSplash
                        .transition(.opacity)
                }

                VStack(spacing: 6) {
                    Text(showSplash ? "LemmingsStudio" : "MagmaVance")
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                    Text(showSplash ? "Spatial audio workstation" : "presents")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(64)
        }
        .task { await runBrandingSequence() }
    }

    private var splashImage: some View {
        Group {
            if let image = UIImage(named: splashName) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 520, maxHeight: 280)
                    .accessibilityLabel("LemmingsStudio splash")
            } else {
                Image(systemName: "waveform.path.ecg.rectangle")
                    .font(.system(size: 96, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
            }
        }
    }

    private var fallbackPreSplash: some View {
        VStack(spacing: 18) {
            Image(systemName: "flame.fill")
                .font(.system(size: 88, weight: .bold))
                .symbolRenderingMode(.hierarchical)
            Text("MagmaVance")
                .font(.largeTitle.bold())
        }
        .frame(maxWidth: 760, maxHeight: 360)
    }

    private func runBrandingSequence() async {
        if let url = Bundle.main.url(forResource: preSplashName, withExtension: "mp4") {
            let p = AVPlayer(url: url)
            player = p
            p.isMuted = true
            p.play()
            try? await Task.sleep(for: .seconds(2.2))
            p.pause()
        } else {
            try? await Task.sleep(for: .seconds(1.0))
        }

        withAnimation(.easeInOut(duration: 0.45)) { showSplash = true }
        try? await Task.sleep(for: .seconds(1.25))
        withAnimation(.easeInOut(duration: 0.35)) { model.completeStartupBranding() }
    }
}
