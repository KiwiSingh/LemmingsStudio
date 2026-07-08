import SwiftUI

struct VisionAppearanceView: View {
    @Environment(VisionStudioModel.self) private var model
    var body: some View {
        @Bindable var model = model
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 18)], spacing: 18) {
                ForEach(VisionVisualTheme.allCases) { theme in
                    let p = VisionThemeCatalog.palette(for: theme)
                    Button {
                        model.visualTheme = theme
                        model.persistTheme()
                    } label: {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack { Image(systemName: theme.glyph); Text(theme.rawValue).font(.headline); Spacer() }
                            RoundedRectangle(cornerRadius: 18)
                                .fill(LinearGradient(colors: [p.backgroundA, p.backgroundB, p.accent.opacity(0.65)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(height: 120)
                                .overlay(alignment: .bottomLeading) {
                                    HStack { Circle().fill(p.accent).frame(width: 18); Circle().fill(p.secondaryAccent).frame(width: 18); Text("Liquid Glass skin").font(.caption) }
                                        .padding(14)
                                }
                        }
                        .padding(16)
                        .lemmingsGlass()
                        .overlay { if model.visualTheme == theme { RoundedRectangle(cornerRadius: 24).stroke(p.accent, lineWidth: 3) } }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(24)
        }
        .background(VisionThemeBackground(theme: model.visualTheme))
        .navigationTitle("Skins")
    }
}
