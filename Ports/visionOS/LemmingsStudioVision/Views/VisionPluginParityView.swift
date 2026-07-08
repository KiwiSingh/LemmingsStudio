import SwiftUI

struct VisionPluginParityView: View {
    @Environment(VisionStudioModel.self) private var model

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Desktop Plug-in Parity")
                    .font(.largeTitle.bold())
                Text("Buildfix258 completes the visionOS-side contracts for Mac Companion plug-ins: discovery, instance preview, parameter trees, streamed editor surfaces, automation exposure, and bounce/export planning.")
                    .foregroundStyle(.secondary)

                HStack {
                    Button("Seed Demo Inventory", systemImage: "shippingbox") { model.companionParity.seedDemoInventory() }
                    Button("Expose Selected Parameters", systemImage: "point.3.connected.trianglepath.dotted") { model.exposeSelectedCompanionParametersForAutomation() }
                    Button("Prepare Bounce Dry Run", systemImage: "square.and.arrow.down") { model.prepareVisionBounceDryRun() }
                }
                .buttonStyle(.borderedProminent)

                Text(model.companionParity.status).font(.callout).foregroundStyle(.secondary)

                GroupBox("Companion Inventory") {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(model.companionParity.discovered) { descriptor in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(descriptor.name).font(.headline)
                                    Text("\(descriptor.format) • \(descriptor.vendor ?? "Unknown vendor") • \(descriptor.architecture ?? "unknown arch")")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Instantiate Preview") { model.companionParity.instantiatePreview(descriptor) }
                            }
                            Divider()
                        }
                        if model.companionParity.discovered.isEmpty { Text("No Companion inventory loaded yet.").foregroundStyle(.secondary) }
                    }
                }

                GroupBox("Active Instances") {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(model.companionParity.activeInstances) { instance in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(instance.descriptor.name).font(.headline)
                                    Spacer()
                                    Text("\(instance.latencySamples) samples")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Text(instance.status).font(.caption).foregroundStyle(.secondary)
                                if let surface = instance.editorSurface {
                                    Text("Editor: \(surface.transportKind.rawValue), \(surface.nominalWidth)x\(surface.nominalHeight) @ \(surface.refreshRate)Hz")
                                        .font(.caption)
                                }
                                ForEach(instance.parameters) { parameter in
                                    HStack {
                                        Text(parameter.name)
                                        Spacer()
                                        Text(String(format: "%.2f", parameter.value)).monospacedDigit()
                                    }
                                    .font(.caption)
                                }
                            }
                            .padding(10)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
                            .onTapGesture { model.companionParity.selectedInstanceID = instance.id }
                        }
                        if model.companionParity.activeInstances.isEmpty { Text("No active Companion instances.").foregroundStyle(.secondary) }
                    }
                }

                GroupBox("Automation Lanes") {
                    VStack(alignment: .leading) {
                        ForEach(model.automationParity.lanes) { lane in
                            Text("\(lane.address.displayName) • \(lane.points.count) point(s)")
                                .font(.caption)
                        }
                        if model.automationParity.lanes.isEmpty { Text("Expose a Companion instance to populate shared parameter automation lanes.").foregroundStyle(.secondary) }
                    }
                }

                GroupBox("Mac Host Mode Project Bounce") {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("Scope", selection: $model.bounceParity.request.scope) {
                            ForEach(VisionBounceRequest.Scope.allCases) { Text($0.rawValue).tag($0) }
                        }
                        Picker("Format", selection: $model.bounceParity.request.format) {
                            ForEach(VisionBounceRequest.Format.allCases) { Text($0.rawValue).tag($0) }
                        }
                        Toggle("Include returns", isOn: $model.bounceParity.request.includeReturnBuses)
                        Toggle("Include Companion audio return", isOn: $model.bounceParity.request.includeCompanionReturn)
                        Toggle("Normalize", isOn: $model.bounceParity.request.normalize)
                        HStack {
                            Button("Prepare Plan") { model.prepareVisionBounceDryRun() }
                            Button(model.desktopBridge.projectBounceInFlight ? "Rendering…" : "Render on Mac") { model.renderProjectOnMacHost() }
                                .buttonStyle(.borderedProminent)
                                .disabled(model.desktopBridge.projectBounceInFlight)
                        }
                        Text(model.bounceParity.dryRunPlan.isEmpty ? "No bounce plan yet." : model.bounceParity.dryRunPlan)
                            .font(.system(.caption, design: .monospaced))
                        Text(model.desktopBridge.projectBounceProgress).font(.caption).foregroundStyle(.secondary)
                        ForEach(model.desktopBridge.lastProjectBounceURLs, id: \.self) { url in
                            Label(url.lastPathComponent, systemImage: "waveform.badge.checkmark")
                                .font(.caption)
                        }
                    }
                }

                GroupBox("Next Steps for Full macOS Parity") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("1. Recording parity landed in buildfix267: punch in/out, count-in, pre-roll, take lanes, region slicing, take reassignment, and comp consolidation.")
                        Text("2. Automation parity landed in buildfix268: persistence, Write/Touch/Latch, curves, and spatial gesture recording.")
                        Text("3. MLX runtime integration landed in buildfix269; hardware-test model loading and constrained tool execution.")
                        Text("4. Bring up a staged Wine ARM64 runtime and complete VST3 probe/DSP/editor bridges.")
                        Text("5. Final visionOS/macOS parity audit and launch hardening.")
                    }
                    .font(.callout)
                }
            }
            .padding(24)
        }
        .background(VisionThemeBackground(theme: model.visualTheme))
    }
}
