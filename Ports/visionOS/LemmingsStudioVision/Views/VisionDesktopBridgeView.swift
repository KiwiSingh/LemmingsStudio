import SwiftUI
import UIKit

struct VisionDesktopBridgeView: View {
    @Environment(VisionStudioModel.self) private var model

    var body: some View {
        @Bindable var bridge = model.desktopBridge
        NavigationSplitView {
            List {
                Section("LemmingsStudio Mac hosts") {
                    ForEach(Array(bridge.discoveredHostNames.enumerated()), id: \.offset) { index, name in
                        Button(name) { bridge.connect(index: index) }
                    }
                }
                Section("Status") {
                    Label(bridge.status.rawValue.capitalized, systemImage: bridge.status == .connected ? "checkmark.circle.fill" : "network")
                    Text(bridge.statusMessage).font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Mac Host Mode")
            .toolbar { Button("Discover") { bridge.startDiscovery() } }
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if bridge.status == .pairing {
                        GroupBox("Pair this Vision Pro") {
                            HStack {
                                TextField("6-digit code", text: $bridge.pairingCode).textFieldStyle(.roundedBorder)
                                Button("Pair") { bridge.submitPairingCode() }.buttonStyle(.borderedProminent)
                            }
                        }
                    }

                    GroupBox("Desktop plug-ins") {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack { Button("Refresh") { bridge.refreshPlugins() }; Spacer(); Text("\(bridge.plugins.count) found").foregroundStyle(.secondary) }
                            ForEach(bridge.plugins) { plugin in
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(plugin.name).font(.headline)
                                        Text("\(plugin.vendor) • \(plugin.format) • \(plugin.provider.rawValue)").font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button("Load") { bridge.instantiate(plugin) }
                                }
                                .padding(10).lemmingsGlass(cornerRadius: 16)
                            }
                        }
                    }

                    if let active = bridge.activePlugin {
                        GroupBox("Active: \(active.name)") {
                            VStack(alignment: .leading, spacing: 14) {
                                Toggle("Return Mac audio to Vision Pro", isOn: Binding(get: { bridge.audioReturnEnabled }, set: { bridge.setAudioReturnEnabled($0) }))
                                Toggle("Stream plug-in editor", isOn: Binding(get: { bridge.editorStreamingEnabled }, set: { bridge.setEditorStreamingEnabled($0) }))

                                if bridge.editorStreamingEnabled {
                                    VisionRemotePluginEditorSurface(bridge: bridge)
                                        .frame(minHeight: 420)
                                        .clipShape(RoundedRectangle(cornerRadius: 18))
                                }

                                HStack {
                                    Button("Refresh Parameters") { bridge.refreshParameters() }
                                    Spacer()
                                    Text("\(bridge.parameters.count) parameters").foregroundStyle(.secondary)
                                }
                                ForEach(bridge.parameters) { parameter in
                                    VStack(alignment: .leading) {
                                        HStack { Text(parameter.name); Spacer(); Text(parameter.displayValue ?? String(format: "%.3f", parameter.normalizedValue)).monospacedDigit() }
                                        Slider(value: Binding(get: { parameter.normalizedValue }, set: { bridge.setParameter(id: parameter.id, normalizedValue: $0) }), in: 0...1)
                                    }
                                    .padding(.vertical, 6)
                                }
                            }
                        }

                        GroupBox("Mac-rendered bounce") {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text("BPM")
                                    TextField("120", value: $bridge.offlineRenderBPM, format: .number).frame(width: 100)
                                    Text("Length (beats)")
                                    TextField("16", value: $bridge.offlineRenderLengthBeats, format: .number).frame(width: 100)
                                    Spacer()
                                    Button("Render WAV on Mac") { bridge.requestOfflineRender() }.buttonStyle(.borderedProminent)
                                }
                                if let url = bridge.lastOfflineRenderURL {
                                    Text("Saved: \(url.lastPathComponent)").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .padding(24)
            }
        }
        .background(VisionThemeBackground(theme: model.visualTheme))
    }
}

private struct VisionRemotePluginEditorSurface: View {
    @Bindable var bridge: VisionDesktopBridgeClient
    @State private var dragging = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: 18).fill(.black.opacity(0.35))
                if let data = bridge.editorJPEGData, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    let x = value.location.x / max(1, proxy.size.width)
                                    let y = value.location.y / max(1, proxy.size.height)
                                    if !dragging {
                                        dragging = true
                                        bridge.sendEditorInput(kind: "down", x: x, y: y)
                                    } else {
                                        bridge.sendEditorInput(kind: "move", x: x, y: y)
                                    }
                                }
                                .onEnded { value in
                                    let x = value.location.x / max(1, proxy.size.width)
                                    let y = value.location.y / max(1, proxy.size.height)
                                    bridge.sendEditorInput(kind: "up", x: x, y: y)
                                    dragging = false
                                }
                        )
                } else {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Waiting for editor frames from the Mac…")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
