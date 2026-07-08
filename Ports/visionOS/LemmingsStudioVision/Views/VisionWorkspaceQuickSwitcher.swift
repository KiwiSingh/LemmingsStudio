import SwiftUI

struct VisionWorkspaceQuickSwitcher: View {
    @Environment(VisionStudioModel.self) private var model

    var body: some View {
        HStack(spacing: 6) {
            ForEach(VisionStudioModel.PrimaryWorkspace.allCases) { workspace in
                Button {
                    model.activePrimaryWorkspace = workspace
                    model.statusMessage = "Showing \(workspace.rawValue)"
                } label: {
                    Label(workspace.rawValue, systemImage: workspace.symbol)
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.bordered)
                .tint(
                    model.activePrimaryWorkspace == workspace
                        ? Color.accentColor
                        : Color.secondary
                )
                .help(workspace.rawValue)
            }
        }
    }
}
