import SwiftUI

struct GainReductionReadout: View {
    var label: String = "GR"
    let value: () -> Double
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 30)) { _ in
            let reduction = max(0, value())
            VStack(spacing: 2) {
                Text(String(format: "\(label) %.1f dB", reduction)).monospacedDigit().font(.caption.bold()).foregroundStyle(.orange)
                ProgressView(value: min(36, reduction), total: 36).tint(.orange)
            }
            .accessibilityLabel("Gain reduction").accessibilityValue(String(format: "%.1f decibels", reduction))
        }
    }
}

struct MasterChannelStrip: View {
    @Environment(AppState.self) private var app
    @State private var showInserts = false
    var body: some View {
        VStack(spacing: 7) {
            Text("MASTER").font(.caption.bold())
            TimelineView(.periodic(from: .now, by: 1.0 / 30)) { _ in
                MeterColumn(level: app.engine.masterMeterPeak(), color: .orange, clipped: app.engine.masterMeterIsClipping()).frame(width: 14, height: 72)
            }
            Slider(value: Binding(get: { Double(app.engine.masterVolume) }, set: { app.engine.masterVolume = Float($0) }), in: 0...1)
            Text(app.engine.masterVolume > 0 ? String(format: "%.1f dB", 20 * log10(app.engine.masterVolume)) : "−∞ dB").font(.caption2).monospacedDigit()
            GainReductionReadout(label: "Stock GR") { app.engine.isRunning ? app.engine.masterGainReductionDB() : 0 }
            Button("Inserts (\(app.project.masterDevices.count + app.project.masterExternalPluginSlots.count))") { showInserts = true }.controlSize(.small)
            MixerFXDropSlot(label: "Drop Master FX", perform: app.handleMasterDrop)
        }
        .padding(10).frame(width: 124).background(.orange.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 7))
        .sheet(isPresented: $showInserts) { MasterInsertRack().environment(app) }
    }
}

struct MasterInsertRack: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Master Inserts").font(.title2.bold())
                Spacer()
                Menu("Add Stock FX") {
                    ForEach(DeviceKind.categorizedBrowserSections.filter { $0.role == .audioEffect || $0.role == .analyzer }) { section in
                        Section(section.title) { ForEach(section.devices) { kind in Button(kind.rawValue) { app.addMasterEffect(kind) } } }
                    }
                }
                Menu("Add Plugin") {
                    ForEach(app.discoveredPlugins.filter { $0.role == .effect && ($0.format == .audioUnit || $0.format == .vst3) }) { plugin in
                        Button("\(plugin.name) · \(plugin.format.rawValue)") { if app.addMasterPlugin(plugin), let slot = app.project.masterExternalPluginSlots.last { app.openPluginGUI(slot) } }
                    }
                    Divider(); Button("Rescan Plugins") { app.scanPlugins() }
                }
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            GainReductionReadout(label: "Stock GR") { app.engine.isRunning ? app.engine.masterGainReductionDB() : 0 }
            Text("Signal flow: plugin inserts → stock inserts → Master fader. Stock GR excludes makeup gain; third-party GR is shown in the plugin’s own editor.")
                .font(.caption).foregroundStyle(.secondary)
            if let error = app.engine.masterProcessingError { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(app.project.masterExternalPluginSlots.enumerated()), id: \.element.id) { index, slot in
                        HStack {
                            Text("\(index + 1). \(slot.name)")
                            if !slot.hosted { Text("Unavailable").foregroundStyle(.red) }
                            Spacer()
                            Button(slot.bypassed ? "Enable" : "Bypass") { app.project.masterExternalPluginSlots[index].bypassed.toggle(); app.engine.rebuild() }
                            Button("Open") { app.openPluginGUI(slot) }
                            Button("↑") { if index > 0 { app.project.masterExternalPluginSlots.swapAt(index, index - 1); app.engine.rebuild() } }.disabled(index == 0)
                            Button("Remove") { app.project.masterExternalPluginSlots.removeAll { $0.id == slot.id }; app.engine.rebuild() }
                        }.padding(8).background(.secondary.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    ForEach(Array(app.project.masterDevices.enumerated()), id: \.element.id) { index, device in
                        MasterStockInsert(device: device, index: index)
                    }
                    MixerFXDropSlot(label: "Drop an audio effect here", perform: app.handleMasterDrop).frame(height: 24)
                }
            }
        }.padding(20).frame(minWidth: 740, minHeight: 580)
        .onAppear { if app.discoveredPlugins.isEmpty { app.scanPlugins() } }
    }
}

private struct MasterStockInsert: View {
    @Environment(AppState.self) private var app
    @Bindable var device: DeviceModel
    let index: Int
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text(device.kind.rawValue).bold(); Spacer()
                Button(device.bypassed ? "Enable" : "Bypass") { device.bypassed.toggle(); app.engine.masterEffect(for: device)?.bypassed = device.bypassed }
                Button("↑") { if index > 0 { app.project.masterDevices.swapAt(index, index - 1); app.engine.rebuild() } }.disabled(index == 0)
                Button("Remove") { app.project.masterDevices.removeAll { $0.id == device.id }; app.engine.rebuild() }
            }
            if app.engine.masterEffect(for: device) is GainReductionMetering {
                GainReductionReadout { app.engine.isRunning ? (app.engine.masterEffect(for: device) as? GainReductionMetering)?.gainReductionDB ?? 0 : 0 }
            }
            ForEach((app.engine.masterEffect(for: device) ?? DeviceFactory.make(device.kind)).automatableParams) { param in
                HStack {
                    Text(param.name).frame(width: 100, alignment: .leading)
                    Slider(value: Binding(get: { param.normalize(device.params[param.id] ?? app.engine.masterEffect(for: device)?.getParam(param.id) ?? param.min) }, set: { device.params[param.id] = param.denormalize($0); app.engine.masterEffect(for: device)?.setParam(param.id, param.denormalize($0)) }))
                    Text(String(format: "%.2f %@", device.params[param.id] ?? app.engine.masterEffect(for: device)?.getParam(param.id) ?? param.min, param.unit)).font(.caption).monospacedDigit().frame(width: 100)
                }
            }
        }.padding(10).background(.secondary.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
