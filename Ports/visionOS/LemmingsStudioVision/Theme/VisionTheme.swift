import SwiftUI

enum VisionVisualTheme: String, CaseIterable, Identifiable, Codable {
    case liquidGlass = "Liquid Glass"
    case worldCup2026 = "World Cup 2026"
    case cyberpunkNightCity = "Cyberpunk 2077-ish"
    case hotPink = "Hot Pink"
    case animeRacing = "Anime Racing"
    case elementalAnime = "Elemental Fantasy"
    case alienClub = "Alien Club"
    case spatialFuture = "Spatial Future"
    case lemmingsBurrow = "Lemmings"
    case hamsterAfterDark = "Hamster After Dark"
    case kittyAndBuds = "Kitty and Buds"

    var id: String { rawValue }
    var glyph: String {
        switch self {
        case .liquidGlass: return "sparkles"
        case .worldCup2026: return "soccerball"
        case .cyberpunkNightCity: return "bolt.fill"
        case .hotPink: return "heart.fill"
        case .animeRacing: return "flag.checkered"
        case .elementalAnime: return "sparkles"
        case .alienClub: return "antenna.radiowaves.left.and.right"
        case .spatialFuture: return "visionpro"
        case .lemmingsBurrow: return "pawprint.fill"
        case .hamsterAfterDark: return "circle.grid.cross.fill"
        case .kittyAndBuds: return "cat.fill"
        }
    }
}

struct VisionThemePalette {
    let backgroundA: Color
    let backgroundB: Color
    let glowA: Color
    let glowB: Color
    let accent: Color
    let secondaryAccent: Color
    let grid: Color
}

enum VisionThemeCatalog {
    static func palette(for theme: VisionVisualTheme) -> VisionThemePalette {
        switch theme {
        case .liquidGlass:
            .init(backgroundA: Color(red: 0.045, green: 0.05, blue: 0.07), backgroundB: Color(red: 0.08, green: 0.095, blue: 0.13), glowA: .cyan, glowB: .purple, accent: Color(red: 0.34, green: 0.96, blue: 0.62), secondaryAccent: .cyan, grid: .white.opacity(0.13))
        case .worldCup2026:
            .init(backgroundA: Color(red: 0.025, green: 0.09, blue: 0.06), backgroundB: Color(red: 0.01, green: 0.17, blue: 0.10), glowA: .green, glowB: .yellow, accent: .green, secondaryAccent: .yellow, grid: .white.opacity(0.16))
        case .cyberpunkNightCity:
            .init(backgroundA: Color(red: 0.055, green: 0.03, blue: 0.08), backgroundB: Color(red: 0.12, green: 0.09, blue: 0.015), glowA: .cyan, glowB: .yellow, accent: .cyan, secondaryAccent: .pink, grid: .yellow.opacity(0.16))
        case .hotPink:
            .init(backgroundA: Color(red: 0.12, green: 0.015, blue: 0.075), backgroundB: Color(red: 0.26, green: 0.025, blue: 0.17), glowA: .pink, glowB: .purple, accent: .pink, secondaryAccent: .purple, grid: .white.opacity(0.13))
        case .animeRacing:
            .init(backgroundA: Color(red: 0.08, green: 0.045, blue: 0.10), backgroundB: Color(red: 0.16, green: 0.11, blue: 0.18), glowA: .orange, glowB: .purple, accent: .orange, secondaryAccent: .purple, grid: .white.opacity(0.13))
        case .elementalAnime:
            .init(backgroundA: Color(red: 0.03, green: 0.065, blue: 0.10), backgroundB: Color(red: 0.08, green: 0.12, blue: 0.19), glowA: .cyan, glowB: .purple, accent: .cyan, secondaryAccent: .yellow, grid: .white.opacity(0.14))
        case .alienClub:
            .init(backgroundA: Color(red: 0.025, green: 0.02, blue: 0.06), backgroundB: Color(red: 0.05, green: 0.11, blue: 0.055), glowA: .green, glowB: .purple, accent: .green, secondaryAccent: .purple, grid: .green.opacity(0.14))
        case .spatialFuture:
            .init(backgroundA: Color(red: 0.075, green: 0.09, blue: 0.11), backgroundB: Color(red: 0.125, green: 0.15, blue: 0.19), glowA: .cyan, glowB: .indigo, accent: Color(red: 0.62, green: 0.88, blue: 1), secondaryAccent: .indigo, grid: .white.opacity(0.12))
        case .lemmingsBurrow:
            .init(backgroundA: Color(red: 0.035, green: 0.085, blue: 0.045), backgroundB: Color(red: 0.105, green: 0.165, blue: 0.08), glowA: .green, glowB: .brown, accent: .green, secondaryAccent: .brown, grid: .green.opacity(0.13))
        case .hamsterAfterDark:
            .init(backgroundA: Color(red: 0.025, green: 0.02, blue: 0.018), backgroundB: Color(red: 0.22, green: 0.095, blue: 0.015), glowA: .orange, glowB: .yellow, accent: .orange, secondaryAccent: .yellow, grid: .orange.opacity(0.14))
        case .kittyAndBuds:
            .init(backgroundA: Color(red: 0.145, green: 0.085, blue: 0.13), backgroundB: Color(red: 0.24, green: 0.165, blue: 0.22), glowA: .pink, glowB: .mint, accent: .pink, secondaryAccent: .mint, grid: .white.opacity(0.14))
        }
    }
}

struct VisionThemeBackground: View {
    let theme: VisionVisualTheme
    var body: some View {
        let p = VisionThemeCatalog.palette(for: theme)
        ZStack {
            LinearGradient(colors: [p.backgroundA, p.backgroundB, .black.opacity(0.88)], startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [p.glowA.opacity(0.24), .clear], center: .topTrailing, startRadius: 10, endRadius: 700)
            RadialGradient(colors: [p.glowB.opacity(0.20), .clear], center: .bottomLeading, startRadius: 30, endRadius: 820)
        }
        .ignoresSafeArea()
    }
}

private struct LiquidGlassCard: ViewModifier {
    var cornerRadius: CGFloat = 24
    func body(content: Content) -> some View {
        // `glassEffect(_:in:)` is unavailable on visionOS even in the newest SDKs.
        // `glassBackgroundEffect` is the native visionOS material treatment.
        content.glassBackgroundEffect(
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
    }
}

extension View {
    func lemmingsGlass(cornerRadius: CGFloat = 24) -> some View {
        modifier(LiquidGlassCard(cornerRadius: cornerRadius))
    }
}
