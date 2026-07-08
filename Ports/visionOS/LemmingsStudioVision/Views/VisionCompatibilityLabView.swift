import SwiftUI
import UniformTypeIdentifiers

struct VisionCompatibilityLabView: View {
    @Environment(VisionStudioModel.self) private var model
    @State private var showingImporter = false
    @State private var selectedCandidateID: UUID?

    private var selectedCandidate: VisionCompatibilityCandidate? {
        model.compatibilityLab.candidates.first { $0.id == selectedCandidateID } ?? model.compatibilityLab.candidates.first
    }

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(selection: $selectedCandidateID) {
                Section("Runtime Mode") {
                    Toggle("Gojira mode", isOn: $model.compatibilityLab.gojiraModeEnabled)
                    Toggle("Prefer local chaos", isOn: $model.compatibilityLab.preferLocalChaos)
                    Toggle("Allow unsigned probes", isOn: $model.compatibilityLab.allowUnsignedRuntimeProbes)
                }
                Section("Candidates") {
                    ForEach(model.compatibilityLab.candidates) { candidate in
                        CandidateRow(candidate: candidate)
                            .tag(candidate.id)
                    }
                }
            }
            .navigationTitle("Gojira Lab")
            .toolbar {
                Button("Add Plugin", systemImage: "plus") { showingImporter = true }
            }
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    runtimeRoots
                    backendCapabilities
                    if let selectedCandidate {
                        candidateDetail(selectedCandidate)
                    }
                    metadataReports
                    backendPlans
                    wineBringUpReports
                    experiments
                    parityNextSteps
                }
                .padding(24)
            }
            .background(VisionThemeBackground(theme: model.visualTheme))
        }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                for url in urls { model.addCompatibilityCandidate(from: url) }
            case .failure(let error):
                model.compatibilityLab.status = "Import failed: \(error.localizedDescription)"
            }
        }
        .onAppear {
            if selectedCandidateID == nil { selectedCandidateID = model.compatibilityLab.candidates.first?.id }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Experimental Plugin Compatibility Lab", systemImage: "flame.fill")
                .font(.largeTitle.bold())
            Text("Sideload-first sandbox for local macOS component probes, Wine experiments, and Wine + FEX chaos. Stable paths stay native AUv3 and Integrated Mac Host Mode.")
                .foregroundStyle(.secondary)
            Text(model.compatibilityLab.status)
                .font(.callout.monospaced())
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
        .lemmingsGlass(cornerRadius: 28)
    }

    private var runtimeRoots: some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: 12) {
            Text("Runtime Roots").font(.title2.bold())
            TextField("Wine root", text: $model.compatibilityLab.wineRootHint)
                .textFieldStyle(.roundedBorder)
            TextField("FEX root", text: $model.compatibilityLab.fexRootHint)
                .textFieldStyle(.roundedBorder)
            TextField("macOS component staging root", text: $model.compatibilityLab.macComponentRootHint)
                .textFieldStyle(.roundedBorder)
            Picker("Preferred backend", selection: $model.compatibilityLab.selectedBackend) {
                ForEach(VisionCompatibilityBackend.allCases) { backend in
                    Label(backend.rawValue, systemImage: backend.glyph).tag(backend)
                }
            }
            .pickerStyle(.segmented)
        }
        .lemmingsGlass(cornerRadius: 24)
    }

    private func candidateDetail(_ candidate: VisionCompatibilityCandidate) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(candidate.displayName, systemImage: candidate.preferredBackend.glyph)
                    .font(.title2.bold())
                Spacer()
                Text(candidate.preferredBackend.stability)
                    .font(.caption.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.thinMaterial, in: Capsule())
            }
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                GridRow { Text("Kind").foregroundStyle(.secondary); Text(candidate.kind.rawValue) }
                GridRow { Text("Backend").foregroundStyle(.secondary); Text(candidate.preferredBackend.rawValue) }
                GridRow { Text("Path").foregroundStyle(.secondary); Text(candidate.pathHint).lineLimit(2) }
                GridRow { Text("Local probe").foregroundStyle(.secondary); Text(candidate.canAttemptLocalLoad ? "Allowed" : "Route elsewhere") }
                GridRow { Text("Sideload").foregroundStyle(.secondary); Text(candidate.requiresSideloading ? "Required" : "Not required") }
            }
            ForEach(candidate.notes, id: \.self) { note in
                Label(note, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
            }
            Text(model.compatibilityDryRunScript(for: candidate))
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 14))
            HStack {
                Button("Scan Metadata", systemImage: "doc.text.magnifyingglass") { model.scanCompatibilityMetadata(for: candidate) }
                    .buttonStyle(.borderedProminent)
                Button("Backend Plan", systemImage: "point.3.connected.trianglepath.dotted") { model.generateBackendPlan(for: candidate) }
                Button("Metadata Dry Run", systemImage: "play.circle") { model.runCompatibilityDryRun(for: candidate) }
                Button("Route to Mac Host Mode", systemImage: "desktopcomputer.and.arrow.down") {
                    model.compatibilityLab.status = "Routed \(candidate.displayName) to Integrated Mac Host Mode compatibility path."
                }
                if candidate.preferredBackend == .experimentalWine {
                    Button("Run Full ARM64 Bring-Up", systemImage: "flame.fill") {
                        model.runWineARM64BringUp(for: candidate)
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Enumerate VST3", systemImage: "list.bullet.rectangle") {
                        model.runWineVST3Enumeration(for: candidate)
                    }
                    Button("DSP Transport Probe", systemImage: "waveform.path.ecg") {
                        model.runWineDSPTransportExperiment(for: candidate)
                    }
                    Button("Editor Bridge Probe", systemImage: "rectangle.on.rectangle") {
                        model.runWineEditorBridgeExperiment(for: candidate)
                    }
                }
            }
        }
        .lemmingsGlass(cornerRadius: 24)
    }

    private var backendCapabilities: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Shared Backend Protocol").font(.title2.bold())
            Text("Buildfix257 makes all plug-in paths describe the same capabilities before anything executes: local runtime, editor surface, audio return, and parameter tree.")
                .foregroundStyle(.secondary)
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
                GridRow {
                    Text("Backend").font(.caption.bold())
                    Text("Local").font(.caption.bold())
                    Text("Editor").font(.caption.bold())
                    Text("Audio").font(.caption.bold())
                    Text("Params").font(.caption.bold())
                }
                ForEach(model.compatibilityLab.backendCapabilities, id: \.backend) { caps in
                    GridRow {
                        Label(caps.backend.rawValue, systemImage: caps.backend.glyph)
                        Text(caps.localExecution ? "Yes" : "No")
                        Text(caps.editorSurface ? "Yes" : "No")
                        Text(caps.audioReturn ? "Yes" : "No")
                        Text(caps.parameterTree ? "Yes" : "No")
                    }
                }
            }
        }
        .lemmingsGlass(cornerRadius: 24)
    }

    private var metadataReports: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Metadata Scanner Reports").font(.title2.bold())
            if model.compatibilityLab.metadataReports.isEmpty {
                Text("No scans yet. Select a candidate and hit Scan Metadata. Scans are metadata-only: no dlopen, no Bundle.load, no plug-in execution.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.compatibilityLab.metadataReports) { report in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(report.displayName).font(.headline)
                            Spacer()
                            Text(report.shortSummary).font(.caption).foregroundStyle(.secondary)
                        }
                        if let bundleIdentifier = report.bundleIdentifier { Text("Bundle: \(bundleIdentifier)").font(.caption.monospaced()) }
                        if let version = report.version { Text("Version: \(version)").font(.caption.monospaced()) }
                        if !report.importedFrameworkHints.isEmpty { Text("Hints: \(report.importedFrameworkHints.joined(separator: ", "))").font(.caption) }
                        if !report.desktopOnlySignals.isEmpty { Text("Desktop-only signals: \(report.desktopOnlySignals.joined(separator: ", "))").font(.caption).foregroundStyle(.orange) }
                        ForEach(report.notes, id: \.self) { note in Text("• \(note)").font(.caption).foregroundStyle(.secondary) }
                    }
                    .padding(12)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
        }
        .lemmingsGlass(cornerRadius: 24)
    }

    private var backendPlans: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Backend Plans").font(.title2.bold())
            if model.compatibilityLab.backendPlans.isEmpty {
                Text("No backend plans yet. Plans convert scanner findings into one of: native AUv3, Mac Companion, macOS component lab, Wine ARM64, or Wine+FEX.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.compatibilityLab.backendPlans) { plan in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label(plan.title, systemImage: plan.backend.glyph).font(.headline)
                            Spacer()
                            Text(plan.isExecutableToday ? "Smoke-test ready" : "Blocked")
                                .font(.caption.bold())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.thinMaterial, in: Capsule())
                        }
                        Text(plan.summary).foregroundStyle(.secondary)
                        Text(plan.commandPreview)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                        if !plan.blockedBy.isEmpty {
                            ForEach(plan.blockedBy, id: \.self) { blocker in
                                Label(blocker, systemImage: "lock.trianglebadge.exclamationmark")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                        Text("Next: \(plan.nextStep)").font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(14)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
                }
            }
        }
        .lemmingsGlass(cornerRadius: 24)
    }


    private var wineBringUpReports: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Wine ARM64 Bring-Up Reports").font(.title2.bold())
            if model.compatibilityLab.wineReports.isEmpty {
                Text("No ARM64 bring-up reports yet. Stage a Wine ARM64 runtime and vsthost-probe.exe, select a PE/COFF arm64 VST3 candidate, then run the full bring-up pipeline.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.compatibilityLab.wineReports) { report in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(report.candidateName).font(.headline)
                            Spacer()
                            Text(report.summary).font(.caption.bold())
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(.thinMaterial, in: Capsule())
                        }
                        Text(report.runtimeRoot).font(.caption.monospaced()).foregroundStyle(.secondary)
                        ForEach(report.findings) { finding in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Image(systemName: finding.passed ? "checkmark.circle.fill" : "xmark.octagon.fill")
                                        .foregroundStyle(finding.passed ? .green : .orange)
                                    Text(finding.phase.rawValue).font(.subheadline.bold())
                                    Spacer()
                                    if let exitCode = finding.exitCode { Text("exit \(exitCode)").font(.caption.monospaced()) }
                                }
                                Text(finding.headline).font(.caption.bold())
                                Text(finding.detail).font(.caption.monospaced()).textSelection(.enabled).lineLimit(10)
                                if let command = finding.command {
                                    Text(command).font(.caption2.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                                }
                            }
                            .padding(10)
                            .background(.black.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                        }
                        if !report.capturedLog.isEmpty {
                            DisclosureGroup("Captured runtime log") {
                                Text(report.capturedLog)
                                    .font(.caption2.monospaced())
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(8)
                            }
                        }
                    }
                    .padding(14)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
                }
            }
        }
        .lemmingsGlass(cornerRadius: 24)
    }

    private var experiments: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Experiment Queue").font(.title2.bold())
            ForEach(model.compatibilityLab.experiments) { experiment in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label(experiment.title, systemImage: experiment.backend.glyph).font(.headline)
                        Spacer()
                        Text(experiment.backend.rawValue).font(.caption).foregroundStyle(.secondary)
                    }
                    Text(experiment.commandPreview)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                    Text("Risk: \(experiment.risk)").foregroundStyle(.secondary)
                    Text("Next: \(experiment.nextStep)").foregroundStyle(.secondary)
                }
                .padding(14)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
            }
        }
        .lemmingsGlass(cornerRadius: 24)
    }

    private var parityNextSteps: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Next steps for full macOS parity").font(.title2.bold())
            Label("Recording parity landed in buildfix267: punch in/out, count-in, pre-roll, take lanes, region slicing, take reassignment, and comp consolidation.", systemImage: "1.circle")
            Label("Automation parity landed in buildfix268: persistent lanes, Write/Touch/Latch, curve handles, and spatial gesture recording.", systemImage: "2.circle")
            Label("MLX runtime integration landed in buildfix269; hardware-test local model loading, multimodal context, and constrained tool execution.", systemImage: "3.circle")
            Label("Wine ARM64 bring-up landed in buildfix270: staged runtime validation, architecture gates, loader/DLL/memory diagnostics, VST3 enumeration, DSP transport, editor bridge probes, captured logs, and timeout/crash isolation.", systemImage: "4.circle")
            Label("Finish the full visionOS/macOS parity audit, performance pass, and public-build hardening.", systemImage: "5.circle")
        }
        .lemmingsGlass(cornerRadius: 24)
    }
}

private struct CandidateRow: View {
    let candidate: VisionCompatibilityCandidate

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(candidate.displayName, systemImage: candidate.preferredBackend.glyph)
                .font(.headline)
            Text(candidate.kind.rawValue)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(candidate.preferredBackend.rawValue)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
