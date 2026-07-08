import SwiftUI
import Darwin

struct VisionMixerView: View {
    @Environment(VisionStudioModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let palette = VisionThemeCatalog.palette(for: model.visualTheme)
        VStack(spacing: 12) {
            VisionWorkspaceQuickSwitcher()
                .padding(.top, 14)
            ScrollView(.horizontal) {
                HStack(alignment: .bottom, spacing: 18) {
                ForEach(Array(model.project.tracks.enumerated()), id: \.offset) { index, track in
                    VisionTrackStrip(index: index, track: track, accent: palette.accent)
                        .environment(model)
                }
                Divider().frame(height: 560)
                ForEach(model.project.returnBuses ?? VisionReturnBus.defaults) { bus in
                    VisionReturnStrip(bus: bus, accent: palette.secondaryAccent)
                        .environment(model)
                }
                if model.desktopBridge.activeInstanceID != nil {
                    VisionBridgeReturnStrip(accent: palette.secondaryAccent).environment(model)
                }
                VisionMasterStrip(accent: palette.accent)
                    .environment(model)
            }
                .padding(28)
            }
        }
        .background(VisionThemeBackground(theme: model.visualTheme))
        .navigationTitle("Spatial Mixer")
    }
}

private struct VisionTrackStrip: View {
    @Environment(VisionStudioModel.self) private var model
    let index: Int
    let track: VisionTrack
    let accent: Color

    var body: some View {
        VStack(spacing: 14) {
            Text(track.name).font(.headline).lineLimit(1)
            Text(track.kind).font(.caption).foregroundStyle(.secondary)
            VisionLevelMeter(key: "track-\(index)", accent: accent).environment(model)
            Slider(value: Binding(
                get: { Double(model.project.tracks[index].volume ?? 1) },
                set: { model.setTrackVolume(index: index, value: Float($0)) }
            ), in: 0...1.5)
            .rotationEffect(.degrees(-90))
            .frame(width: 180, height: 42)
            .padding(.vertical, 68)

            HStack {
                Button("M") { model.toggleTrackMute(index: index) }
                    .buttonStyle(.borderedProminent)
                    .tint(model.project.tracks[index].mute == true ? .red : .gray)
                Button("S") { model.toggleTrackSolo(index: index) }
                    .buttonStyle(.borderedProminent)
                    .tint(model.project.tracks[index].solo == true ? .yellow : .gray)
            }

            Text("Pan").font(.caption2)
            Slider(value: Binding(
                get: { Double(model.project.tracks[index].pan ?? 0) },
                set: { model.setTrackPan(index: index, value: Float($0)) }
            ), in: -1...1)

            Text("Send A").font(.caption2)
            Slider(value: Binding(
                get: { Double(model.project.tracks[index].sends?["return-a"] ?? 0) },
                set: { model.setTrackSend(index: index, busID: "return-a", value: Float($0)) }
            ), in: 0...1)

            Text("Send B").font(.caption2)
            Slider(value: Binding(
                get: { Double(model.project.tracks[index].sends?["return-b"] ?? 0) },
                set: { model.setTrackSend(index: index, busID: "return-b", value: Float($0)) }
            ), in: 0...1)

            Picker("Output", selection: Binding(
                get: { model.project.tracks[index].outputBusId ?? "master" },
                set: { model.setTrackOutput(index: index, busID: $0) }
            )) {
                Text("Master").tag("master")
                Text("Return A").tag("return-a")
                Text("Return B").tag("return-b")
            }
            .pickerStyle(.menu)
        }
        .frame(width: 210, height: 600)
        .padding(20)
        .lemmingsGlass(cornerRadius: 30)
    }
}

private struct VisionReturnStrip: View {
    @Environment(VisionStudioModel.self) private var model
    let bus: VisionReturnBus
    let accent: Color

    var body: some View {
        VStack(spacing: 16) {
            Text(bus.name).font(.title3.bold())
            Text(bus.effectKind ?? "Return").font(.caption).foregroundStyle(.secondary)
            VisionLevelMeter(key: bus.id, accent: accent).environment(model)

            Text("Volume").font(.caption2)
            Slider(value: Binding(
                get: { Double(current.volume) },
                set: { var b = current; b.volume = Float($0); model.updateReturnBus(b) }
            ), in: 0...1.5)

            Text("Pan").font(.caption2)
            Slider(value: Binding(
                get: { Double(current.pan) },
                set: { var b = current; b.pan = Float($0); model.updateReturnBus(b) }
            ), in: -1...1)

            Text("Effect Mix").font(.caption2)
            Slider(value: Binding(
                get: { Double(current.effectMix ?? 30) },
                set: { var b = current; b.effectMix = Float($0); model.updateReturnBus(b) }
            ), in: 0...100)

            HStack {
                Button(current.mute ? "Unmute" : "Mute") { var b = current; b.mute.toggle(); model.updateReturnBus(b) }
                Button(current.solo ? "Unsolo" : "Solo") { var b = current; b.solo.toggle(); model.updateReturnBus(b) }
            }
        }
        .frame(width: 230, height: 600)
        .padding(20)
        .lemmingsGlass(cornerRadius: 30)
    }

    private var current: VisionReturnBus {
        model.project.returnBuses?.first(where: { $0.id == bus.id }) ?? bus
    }
}

private struct VisionMasterStrip: View {
    @Environment(VisionStudioModel.self) private var model
    let accent: Color

    var body: some View {
        VStack(spacing: 18) {
            Text("MASTER").font(.title2.bold())
            VisionLevelMeter(key: "master", accent: accent).environment(model)
            Slider(value: Binding(
                get: { Double(model.project.masterVolume ?? 1) },
                set: { model.setMasterVolume(Float($0)) }
            ), in: 0...1.5)
            .rotationEffect(.degrees(-90))
            .frame(width: 180, height: 42)
            .padding(.vertical, 90)
            Button(model.project.masterMuted == true ? "Unmute Master" : "Mute Master") { model.toggleMasterMute() }
                .buttonStyle(.borderedProminent)
        }
        .frame(width: 230, height: 600)
        .padding(20)
        .lemmingsGlass(cornerRadius: 34)
    }
}

struct VisionLevelMeter: View {
    @Environment(VisionStudioModel.self) private var model
    let key: String
    let accent: Color

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.08)) { _ in
            let meter = model.meterSnapshot(key)
            VStack(spacing: 4) {
                GeometryReader { proxy in
                    ZStack(alignment: .bottom) {
                        Capsule().fill(.white.opacity(0.10))
                        Capsule().fill(meter.peak >= 0.99 ? Color.red : accent)
                            .frame(height: proxy.size.height * CGFloat(min(1, meter.peak)))
                    }
                }
                Text(String(format: "%+.1f dB", 20 * log10(max(0.00001, meter.peak))))
                    .font(.caption2.monospacedDigit())
            }
        }
        .frame(width: 34, height: 150)
    }
}


private struct VisionBridgeReturnStrip: View {
    @Environment(VisionStudioModel.self) private var model
    let accent: Color
    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "desktopcomputer")
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(accent)
            Text("Desktop Bridge").font(.title3.bold())
            Text(model.desktopBridge.activePlugin?.name ?? "Remote Plug-in")
                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            Toggle("Audio Return", isOn: Binding(
                get: { model.desktopBridge.audioReturnEnabled },
                set: { model.desktopBridge.setAudioReturnEnabled($0) }
            ))
            Text("Return Level").font(.caption2)
            Slider(value: Binding(
                get: { Double(model.desktopBridge.audioReturnVolume) },
                set: { model.setBridgeReturnVolume(Float($0)) }
            ), in: 0...1.5)
            Text(model.desktopBridge.status.rawValue).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(width: 230, height: 600)
        .padding(20)
        .lemmingsGlass(cornerRadius: 30)
    }
}
