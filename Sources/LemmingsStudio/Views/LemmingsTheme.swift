import SwiftUI

enum LemmingsVisualTheme: String, CaseIterable, Identifiable, Codable {
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

    var displayName: String { rawValue }

    var subtitle: String {
        switch self {
        case .liquidGlass: return "Default translucent cyan/purple glass."
        case .worldCup2026: return "Pitch green, trophy gold, stadium-glass energy."
        case .cyberpunkNightCity: return "Neon yellow, cyan, magenta, chrome, and dark city glass."
        case .hotPink: return "High-gloss pink panels, candy bloom, and club highlights."
        case .animeRacing: return "Idol-racing anime vibes with ribbons, stars, and speedy glass."
        case .elementalAnime: return "Elemental fantasy anime palette: teal, gold, violet, sky."
        case .alienClub: return "Alien-club glyph language, UV green, cosmic violet, bass-cave glass."
        case .spatialFuture: return "Vision-style spatial glass, airy blue-white depth, and soft chrome."
        case .lemmingsBurrow: return "Cute rodent burrow glass: moss, mint, warm dirt, and tiny paw glyphs."
        case .hamsterAfterDark: return "Black-and-orange hamster-nightclub glass, cheeky but original."
        case .kittyAndBuds: return "Pastel kitty-island glass with flowers, bows, leaves, and soft candy bloom."
        }
    }

    var primaryGlyph: String {
        switch self {
        case .liquidGlass: return "sparkles"
        case .worldCup2026: return "soccerball"
        case .cyberpunkNightCity: return "bolt.fill"
        case .hotPink: return "heart.fill"
        case .animeRacing: return "flag.checkered"
        case .elementalAnime: return "sparkle.magnifyingglass"
        case .alienClub: return "antenna.radiowaves.left.and.right"
        case .spatialFuture: return "visionpro"
        case .lemmingsBurrow: return "pawprint.fill"
        case .hamsterAfterDark: return "circle.grid.cross.fill"
        case .kittyAndBuds: return "cat.fill"
        }
    }

    var logoGlyph: String {
        switch self {
        case .liquidGlass: return "🐾"
        case .worldCup2026: return "⚽️"
        case .cyberpunkNightCity: return "⚡️"
        case .hotPink: return "💗"
        case .animeRacing: return "🏁"
        case .elementalAnime: return "✨"
        case .alienClub: return "👽"
        case .spatialFuture: return "◌"
        case .lemmingsBurrow: return "🐭"
        case .hamsterAfterDark: return "🐹"
        case .kittyAndBuds: return "🐱"
        }
    }

    var motifGlyphs: [String] {
        switch self {
        case .liquidGlass: return ["sparkles", "circle.hexagongrid", "waveform"]
        case .worldCup2026: return ["soccerball", "trophy.fill", "sportscourt.fill"]
        case .cyberpunkNightCity: return ["bolt.fill", "cpu.fill", "opticid"]
        case .hotPink: return ["heart.fill", "sparkles", "music.note"]
        case .animeRacing: return ["flag.checkered", "star.fill", "hare.fill"]
        case .elementalAnime: return ["sparkles", "wind", "flame.fill"]
        case .alienClub: return ["antenna.radiowaves.left.and.right", "moon.stars.fill", "waveform.path"]
        case .spatialFuture: return ["visionpro", "circle.dotted", "cube.transparent"]
        case .lemmingsBurrow: return ["pawprint.fill", "leaf.fill", "circle.hexagongrid.fill"]
        case .hamsterAfterDark: return ["circle.grid.cross.fill", "play.rectangle.fill", "bolt.heart.fill"]
        case .kittyAndBuds: return ["cat.fill", "camera.macro", "leaf.fill"]
        }
    }
}

struct LemmingsThemePalette {
    let backgroundA: Color
    let backgroundB: Color
    let backgroundC: Color
    let glowA: Color
    let glowB: Color
    let panel: Color
    let panel2: Color
    let grid: Color
    let text: Color
    let dim: Color
    let play: Color
    let record: Color
    let focus: Color
    let glassStroke: Color
    let glassHighlight: Color
}

enum LSTheme {
    static var current: LemmingsVisualTheme {
        LemmingsVisualTheme(rawValue: UserDefaults.standard.string(forKey: "visualTheme") ?? "") ?? .liquidGlass
    }

    static var logoGlyph: String { current.logoGlyph }

    static var palette: LemmingsThemePalette { palette(for: current) }

    static func palette(for theme: LemmingsVisualTheme) -> LemmingsThemePalette {
        switch theme {
        case .liquidGlass:
            return LemmingsThemePalette(
                backgroundA: Color(red: 0.045, green: 0.050, blue: 0.070),
                backgroundB: Color(red: 0.080, green: 0.095, blue: 0.130),
                backgroundC: Color(red: 0.035, green: 0.038, blue: 0.050),
                glowA: .cyan, glowB: .purple,
                panel: Color(red: 0.135, green: 0.145, blue: 0.170).opacity(0.72),
                panel2: Color(red: 0.235, green: 0.250, blue: 0.290).opacity(0.62),
                grid: Color.white.opacity(0.13), text: Color(red: 0.94, green: 0.96, blue: 0.99),
                dim: Color(red: 0.67, green: 0.70, blue: 0.78), play: Color(red: 0.34, green: 0.96, blue: 0.62),
                record: Color(red: 1.00, green: 0.22, blue: 0.28), focus: Color(red: 0.72, green: 0.88, blue: 1.00),
                glassStroke: Color.white.opacity(0.20), glassHighlight: Color.white.opacity(0.12)
            )
        case .worldCup2026:
            return LemmingsThemePalette(
                backgroundA: Color(red: 0.025, green: 0.090, blue: 0.060), backgroundB: Color(red: 0.010, green: 0.170, blue: 0.100), backgroundC: Color(red: 0.020, green: 0.035, blue: 0.030),
                glowA: Color(red: 0.20, green: 0.95, blue: 0.45), glowB: Color(red: 1.00, green: 0.76, blue: 0.20),
                panel: Color(red: 0.06, green: 0.22, blue: 0.15).opacity(0.74), panel2: Color(red: 0.14, green: 0.33, blue: 0.23).opacity(0.64),
                grid: Color.white.opacity(0.16), text: Color(red: 0.95, green: 1.00, blue: 0.92), dim: Color(red: 0.70, green: 0.86, blue: 0.73),
                play: Color(red: 0.45, green: 1.00, blue: 0.43), record: Color(red: 1.00, green: 0.32, blue: 0.24), focus: Color(red: 1.00, green: 0.82, blue: 0.26),
                glassStroke: Color(red: 0.95, green: 1.00, blue: 0.80).opacity(0.24), glassHighlight: Color.white.opacity(0.15)
            )
        case .cyberpunkNightCity:
            return LemmingsThemePalette(
                backgroundA: Color(red: 0.055, green: 0.030, blue: 0.080), backgroundB: Color(red: 0.120, green: 0.090, blue: 0.015), backgroundC: Color(red: 0.015, green: 0.020, blue: 0.045),
                glowA: Color(red: 0.00, green: 0.95, blue: 1.00), glowB: Color(red: 1.00, green: 0.90, blue: 0.05),
                panel: Color(red: 0.11, green: 0.08, blue: 0.13).opacity(0.76), panel2: Color(red: 0.22, green: 0.14, blue: 0.20).opacity(0.66),
                grid: Color.yellow.opacity(0.16), text: Color(red: 1.00, green: 0.98, blue: 0.72), dim: Color(red: 0.78, green: 0.88, blue: 0.92),
                play: Color(red: 0.00, green: 1.00, blue: 0.92), record: Color(red: 1.00, green: 0.08, blue: 0.42), focus: Color(red: 1.00, green: 0.92, blue: 0.06),
                glassStroke: Color.yellow.opacity(0.28), glassHighlight: Color.cyan.opacity(0.18)
            )
        case .hotPink:
            return LemmingsThemePalette(
                backgroundA: Color(red: 0.120, green: 0.015, blue: 0.075), backgroundB: Color(red: 0.260, green: 0.025, blue: 0.170), backgroundC: Color(red: 0.050, green: 0.012, blue: 0.040),
                glowA: Color(red: 1.00, green: 0.20, blue: 0.72), glowB: Color(red: 1.00, green: 0.68, blue: 0.92),
                panel: Color(red: 0.24, green: 0.05, blue: 0.18).opacity(0.76), panel2: Color(red: 0.42, green: 0.10, blue: 0.32).opacity(0.66),
                grid: Color.white.opacity(0.13), text: Color(red: 1.00, green: 0.92, blue: 0.98), dim: Color(red: 0.95, green: 0.66, blue: 0.86),
                play: Color(red: 1.00, green: 0.58, blue: 0.86), record: Color(red: 1.00, green: 0.10, blue: 0.48), focus: Color(red: 1.00, green: 0.36, blue: 0.82),
                glassStroke: Color(red: 1.00, green: 0.58, blue: 0.94).opacity(0.30), glassHighlight: Color.white.opacity(0.16)
            )
        case .animeRacing:
            return LemmingsThemePalette(
                backgroundA: Color(red: 0.080, green: 0.045, blue: 0.100), backgroundB: Color(red: 0.160, green: 0.110, blue: 0.180), backgroundC: Color(red: 0.030, green: 0.026, blue: 0.045),
                glowA: Color(red: 1.00, green: 0.64, blue: 0.32), glowB: Color(red: 0.70, green: 0.45, blue: 1.00),
                panel: Color(red: 0.18, green: 0.12, blue: 0.22).opacity(0.75), panel2: Color(red: 0.32, green: 0.20, blue: 0.34).opacity(0.65),
                grid: Color.white.opacity(0.13), text: Color(red: 1.00, green: 0.95, blue: 0.90), dim: Color(red: 0.88, green: 0.72, blue: 0.92),
                play: Color(red: 1.00, green: 0.62, blue: 0.24), record: Color(red: 1.00, green: 0.20, blue: 0.36), focus: Color(red: 0.86, green: 0.55, blue: 1.00),
                glassStroke: Color(red: 1.00, green: 0.82, blue: 0.58).opacity(0.25), glassHighlight: Color.white.opacity(0.15)
            )
        case .elementalAnime:
            return LemmingsThemePalette(
                backgroundA: Color(red: 0.030, green: 0.065, blue: 0.100), backgroundB: Color(red: 0.080, green: 0.120, blue: 0.190), backgroundC: Color(red: 0.025, green: 0.030, blue: 0.060),
                glowA: Color(red: 0.35, green: 0.95, blue: 0.95), glowB: Color(red: 0.86, green: 0.62, blue: 1.00),
                panel: Color(red: 0.06, green: 0.12, blue: 0.20).opacity(0.75), panel2: Color(red: 0.15, green: 0.23, blue: 0.33).opacity(0.64),
                grid: Color.white.opacity(0.14), text: Color(red: 0.91, green: 0.98, blue: 1.00), dim: Color(red: 0.68, green: 0.82, blue: 0.92),
                play: Color(red: 0.50, green: 1.00, blue: 0.86), record: Color(red: 1.00, green: 0.42, blue: 0.34), focus: Color(red: 0.95, green: 0.78, blue: 0.40),
                glassStroke: Color(red: 0.70, green: 0.96, blue: 1.00).opacity(0.26), glassHighlight: Color.white.opacity(0.14)
            )
        case .alienClub:
            return LemmingsThemePalette(
                backgroundA: Color(red: 0.025, green: 0.020, blue: 0.060), backgroundB: Color(red: 0.050, green: 0.110, blue: 0.055), backgroundC: Color(red: 0.010, green: 0.012, blue: 0.025),
                glowA: Color(red: 0.55, green: 1.00, blue: 0.16), glowB: Color(red: 0.62, green: 0.30, blue: 1.00),
                panel: Color(red: 0.05, green: 0.11, blue: 0.08).opacity(0.77), panel2: Color(red: 0.11, green: 0.22, blue: 0.13).opacity(0.64),
                grid: Color(red: 0.55, green: 1.00, blue: 0.24).opacity(0.14), text: Color(red: 0.88, green: 1.00, blue: 0.82), dim: Color(red: 0.62, green: 0.84, blue: 0.62),
                play: Color(red: 0.55, green: 1.00, blue: 0.16), record: Color(red: 0.86, green: 0.16, blue: 1.00), focus: Color(red: 0.70, green: 1.00, blue: 0.22),
                glassStroke: Color(red: 0.62, green: 1.00, blue: 0.24).opacity(0.30), glassHighlight: Color(red: 0.84, green: 1.00, blue: 0.60).opacity(0.16)
            )
        case .spatialFuture:
            return LemmingsThemePalette(
                backgroundA: Color(red: 0.075, green: 0.090, blue: 0.110), backgroundB: Color(red: 0.125, green: 0.150, blue: 0.190), backgroundC: Color(red: 0.028, green: 0.034, blue: 0.048),
                glowA: Color(red: 0.72, green: 0.90, blue: 1.00), glowB: Color(red: 0.84, green: 0.82, blue: 1.00),
                panel: Color(red: 0.20, green: 0.24, blue: 0.30).opacity(0.58), panel2: Color(red: 0.42, green: 0.48, blue: 0.56).opacity(0.36),
                grid: Color.white.opacity(0.12), text: Color(red: 0.96, green: 0.98, blue: 1.00), dim: Color(red: 0.73, green: 0.78, blue: 0.86),
                play: Color(red: 0.62, green: 0.88, blue: 1.00), record: Color(red: 1.00, green: 0.33, blue: 0.42), focus: Color(red: 0.82, green: 0.92, blue: 1.00),
                glassStroke: Color.white.opacity(0.26), glassHighlight: Color.white.opacity(0.20)
            )
        case .lemmingsBurrow:
            return LemmingsThemePalette(
                backgroundA: Color(red: 0.035, green: 0.085, blue: 0.045), backgroundB: Color(red: 0.105, green: 0.165, blue: 0.080), backgroundC: Color(red: 0.050, green: 0.035, blue: 0.025),
                glowA: Color(red: 0.52, green: 1.00, blue: 0.46), glowB: Color(red: 0.82, green: 0.55, blue: 0.28),
                panel: Color(red: 0.08, green: 0.16, blue: 0.10).opacity(0.74), panel2: Color(red: 0.22, green: 0.18, blue: 0.10).opacity(0.60),
                grid: Color(red: 0.76, green: 1.00, blue: 0.70).opacity(0.13), text: Color(red: 0.94, green: 1.00, blue: 0.88), dim: Color(red: 0.70, green: 0.83, blue: 0.64),
                play: Color(red: 0.55, green: 1.00, blue: 0.35), record: Color(red: 1.00, green: 0.42, blue: 0.26), focus: Color(red: 0.86, green: 1.00, blue: 0.55),
                glassStroke: Color(red: 0.80, green: 1.00, blue: 0.58).opacity(0.27), glassHighlight: Color(red: 0.95, green: 1.00, blue: 0.78).opacity(0.16)
            )
        case .hamsterAfterDark:
            return LemmingsThemePalette(
                backgroundA: Color(red: 0.025, green: 0.020, blue: 0.018), backgroundB: Color(red: 0.220, green: 0.095, blue: 0.015), backgroundC: Color(red: 0.010, green: 0.010, blue: 0.012),
                glowA: Color(red: 1.00, green: 0.48, blue: 0.06), glowB: Color(red: 1.00, green: 0.74, blue: 0.28),
                panel: Color(red: 0.09, green: 0.07, blue: 0.055).opacity(0.78), panel2: Color(red: 0.28, green: 0.12, blue: 0.035).opacity(0.62),
                grid: Color(red: 1.00, green: 0.56, blue: 0.12).opacity(0.14), text: Color(red: 1.00, green: 0.94, blue: 0.84), dim: Color(red: 0.92, green: 0.66, blue: 0.38),
                play: Color(red: 1.00, green: 0.60, blue: 0.12), record: Color(red: 1.00, green: 0.20, blue: 0.10), focus: Color(red: 1.00, green: 0.48, blue: 0.06),
                glassStroke: Color(red: 1.00, green: 0.54, blue: 0.12).opacity(0.30), glassHighlight: Color(red: 1.00, green: 0.82, blue: 0.42).opacity(0.15)
            )
        case .kittyAndBuds:
            return LemmingsThemePalette(
                backgroundA: Color(red: 0.145, green: 0.085, blue: 0.130), backgroundB: Color(red: 0.240, green: 0.165, blue: 0.220), backgroundC: Color(red: 0.060, green: 0.055, blue: 0.080),
                glowA: Color(red: 1.00, green: 0.62, blue: 0.82), glowB: Color(red: 0.58, green: 0.96, blue: 0.78),
                panel: Color(red: 0.22, green: 0.13, blue: 0.20).opacity(0.70), panel2: Color(red: 0.38, green: 0.24, blue: 0.34).opacity(0.55),
                grid: Color.white.opacity(0.14), text: Color(red: 1.00, green: 0.95, blue: 0.99), dim: Color(red: 0.92, green: 0.74, blue: 0.86),
                play: Color(red: 0.60, green: 1.00, blue: 0.78), record: Color(red: 1.00, green: 0.30, blue: 0.48), focus: Color(red: 1.00, green: 0.66, blue: 0.86),
                glassStroke: Color(red: 1.00, green: 0.74, blue: 0.90).opacity(0.28), glassHighlight: Color.white.opacity(0.18)
            )
        }
    }

    static var window: Color { palette.backgroundC }
    static var panel: Color { palette.panel }
    static var panel2: Color { palette.panel2 }
    static var grid: Color { palette.grid }
    static var text: Color { palette.text }
    static var dim: Color { palette.dim }
    static var play: Color { palette.play }
    static var record: Color { palette.record }
    static var focus: Color { palette.focus }
    static var glassStroke: Color { palette.glassStroke }
    static var glassHighlight: Color { palette.glassHighlight }

    @ViewBuilder static var windowBackground: some View {
        let p = palette
        ZStack {
            LinearGradient(colors: [p.backgroundA, p.backgroundB, p.backgroundC], startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [p.glowA.opacity(0.25), Color.clear], center: .topTrailing, startRadius: 20, endRadius: 620)
            RadialGradient(colors: [p.glowB.opacity(0.20), Color.clear], center: .bottomLeading, startRadius: 40, endRadius: 720)
            RadialGradient(colors: [p.glassHighlight.opacity(0.55), Color.clear], center: .center, startRadius: 120, endRadius: 900)
        }
        .ignoresSafeArea()
    }
}
