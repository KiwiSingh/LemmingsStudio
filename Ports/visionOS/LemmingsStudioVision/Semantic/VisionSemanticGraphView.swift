import SwiftUI

struct VisionSemanticGraphView: View {
    @Environment(VisionStudioModel.self) private var model
    @State private var selectedKind: VisionSemanticNodeKind? = nil
    @State private var showContextPreview = false

    private var graph: VisionSemanticProjectGraph { model.currentSemanticGraph() }
    private var summary: VisionSemanticGraphSummary { model.semanticGraphSummary() }
    private var nodes: [VisionSemanticNode] { selectedKind.map { kind in graph.nodes.filter { $0.kind == kind } } ?? graph.nodes }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                header
                metricRow
                filters
                HStack(alignment: .top, spacing: 16) {
                    nodeList
                    edgeList
                }
            }
            .padding(20)
            .background(VisionThemeBackground(theme: model.visualTheme))
            .navigationTitle("Semantic Project Graph")
            .toolbar {
                Button("Rebuild", systemImage: "arrow.triangle.2.circlepath") { model.rebuildSemanticGraph() }
                Button("AI Context", systemImage: "text.badge.checkmark") { showContextPreview = true }
            }
            .sheet(isPresented: $showContextPreview) {
                NavigationStack {
                    ScrollView { Text(model.semanticContextPreview(maxNodes: 80)).font(.system(.body, design: .monospaced)).frame(maxWidth: .infinity, alignment: .leading).padding(20) }
                        .navigationTitle("AI Context Preview")
                        .toolbar { Button("Done") { showContextPreview = false } }
                }
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Label("AI-readable backbone", systemImage: "point.3.connected.trianglepath.dotted").font(.headline)
                Text("Metadata-only graph for MLX agents, project memory, workspace restore, Host Mode parity checks, and spatial routing. No DSP or plugin code runs here.").foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing) { Text(graph.projectName).font(.title3.bold()); Text("\(graph.tempo, specifier: "%.1f") BPM").foregroundStyle(.secondary) }
        }.lemmingsGlass(cornerRadius: 24)
    }

    private var metricRow: some View {
        HStack(spacing: 12) {
            metric("Nodes", summary.nodeCount, "circle.hexagongrid")
            metric("Edges", summary.edgeCount, "arrow.triangle.branch")
            metric("Tracks", summary.trackCount, "rectangle.stack")
            metric("Clips", summary.clipCount, "waveform")
            metric("Backends", summary.backendCount, "externaldrive.connected.to.line.below")
        }
    }
    private func metric(_ title: String, _ value: Int, _ icon: String) -> some View { VStack(alignment: .leading) { Label(title, systemImage: icon).font(.caption).foregroundStyle(.secondary); Text("\(value)").font(.largeTitle.bold()).monospacedDigit() }.frame(maxWidth: .infinity, alignment: .leading).padding(16).lemmingsGlass(cornerRadius: 18) }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) { HStack { Button("All") { selectedKind = nil }.buttonStyle(.borderedProminent); ForEach(VisionSemanticNodeKind.allCases) { kind in let count = graph.nodes.filter { $0.kind == kind }.count; if count > 0 { Button { selectedKind = selectedKind == kind ? nil : kind } label: { Label("\(kind.title) · \(count)", systemImage: kind.symbol) }.buttonStyle(.bordered) } } } }
    }

    private var nodeList: some View {
        List(nodes) { node in
            VStack(alignment: .leading, spacing: 5) {
                HStack { Label(node.name, systemImage: node.kind.symbol).font(.headline); Spacer(); Text(node.kind.title).font(.caption).padding(.horizontal, 8).padding(.vertical, 4).background(.thinMaterial, in: Capsule()) }
                if let role = node.role { Text(role).font(.subheadline).foregroundStyle(.secondary) }
                if !node.tags.isEmpty { Text(node.tags.joined(separator: " • ")).font(.caption).foregroundStyle(.tertiary) }
                if !node.properties.isEmpty { Text(node.properties.sorted { $0.key < $1.key }.prefix(4).map { "\($0.key)=\($0.value)" }.joined(separator: "  ")).font(.caption2.monospaced()).foregroundStyle(.secondary) }
            }.padding(.vertical, 5)
        }.scrollContentBackground(.hidden).lemmingsGlass(cornerRadius: 24)
    }

    private var edgeList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Relationships", systemImage: "arrow.triangle.branch").font(.headline)
            ScrollView { VStack(alignment: .leading, spacing: 10) { ForEach(graph.edges.prefix(64)) { edge in VStack(alignment: .leading, spacing: 2) { Text(edge.kind.rawValue).font(.caption.bold()); Text("\(short(edge.sourceKey)) → \(short(edge.targetKey))").font(.caption.monospaced()).foregroundStyle(.secondary); if let label = edge.label { Text(label).font(.caption2).foregroundStyle(.tertiary) } }; Divider().opacity(0.3) } } }
            Divider()
            Text("Next: wire this into MLX Runtime, Living Project Memory, Mac Host Mode telemetry, and full parity audits.").font(.caption).foregroundStyle(.secondary)
        }.padding(18).frame(width: 430).lemmingsGlass(cornerRadius: 24)
    }
    private func short(_ s: String) -> String { s.count > 34 ? String(s.prefix(31)) + "…" : s }
}
