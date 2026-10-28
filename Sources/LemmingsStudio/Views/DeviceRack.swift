import SwiftUI
import UniformTypeIdentifiers

// MARK: - Device rack (Ableton-style insert chain per track)

struct DeviceRackView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let track = app.selectedTrack {
                    header(track)
                        .onAppear { app.ensureVisibleInstrumentDevice(on: track) }
                    if !track.externalPluginSlots.isEmpty {
                        ForEach(track.externalPluginSlots) { slot in
                            ExternalPluginCard(track: track, slot: slot)
                        }
                    }
                    if track.devices.isEmpty && track.externalPluginSlots.isEmpty {
                        Text("No devices on this track yet. Drag a plugin/effect here or add one above.")
                            .font(.caption).foregroundStyle(.secondary).padding(.top, 8)
                    }
                    ForEach(Swift.Array(0..<track.devices.count), id: \.self) { index in
                        let device = track.devices[index]
                        DeviceCard(track: track, device: device, index: index)
                    }
                } else {
                    Text("Select a track to edit its device chain.").foregroundStyle(.secondary).padding()
                }
            }
            .padding(14)
            .onDrop(of: [UTType.text], isTargeted: nil) { providers in
                guard let track = app.selectedTrack, let provider = providers.first else { return false }
                provider.loadObject(ofClass: NSString.self) { object, _ in
                    guard let text = object as? String else { return }
                    DispatchQueue.main.async { _ = app.handlePluginDropText(text, on: track) }
                }
                return true
            }
        }
    }

    private func header(_ track: Track) -> some View {
        HStack {
            Circle().fill(track.color).frame(width: 10, height: 10)
            Text(track.name).font(.headline)
            Spacer()
            Menu {
                ForEach(DeviceKind.categorizedBrowserSections) { section in
                    Section("\(section.title) · \(section.role.rawValue)") {
                        ForEach(section.devices) { kind in
                            Button("\(kind.rawValue) → \(track.name)") {
                                app.addEffect(kind, to: track)
                            }
                        }
                    }
                }
            } label: { Label("Add Device", systemImage: "plus.circle") }
            .menuStyle(.borderlessButton).fixedSize()
        }
    }
}


private struct ExternalPluginCard: View {
    @Environment(AppState.self) private var app
    let track: Track
    let slot: ExternalPluginSlot

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: slot.role == .effect ? "slider.horizontal.3" : "pianokeys")
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(slot.name).font(.system(size: 13, weight: .semibold))
                Text("\(slot.format.rawValue) · \(slot.role.rawValue)" + (slot.hosted ? " · hosted" : " · target slot"))
                    .font(.caption2).foregroundStyle(.secondary)
                if let path = slot.path { Text(path).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
            }
            Spacer()
            Button("Open") { app.openPluginGUI(slot) }.controlSize(.small)
            if slot.role != .effect {
                Button("Use") {
                    app.usePluginSlot(slot, on: track)
                }.controlSize(.small)
            }
            Button {
                track.externalPluginSlots.removeAll { $0.id == slot.id }
                if track.pluginTargetID == slot.name { track.pluginTargetID = nil; app.engine.rebuild() }
            } label: { Image(systemName: "trash") }
                .buttonStyle(.plain).foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color.accentColor.opacity(0.10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.accentColor.opacity(0.25), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct DeviceCard: View {
    @Environment(AppState.self) private var app
    let track: Track
    @Bindable var device: DeviceModel
    let index: Int

    private var params: [ParamInfo] {
        (app.engine.liveNode(track: track, nodeID: device.nodeID)
         ?? DeviceFactory.make(device.kind)).automatableParams
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon(device.kind))
                Text(device.kind.rawValue).font(.system(size: 13, weight: .semibold))
                Spacer()
                if device.kind.isBuiltInTrackInstrument {
                    Text("Track Instrument")
                        .font(.caption2.bold())
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.16))
                        .clipShape(Capsule())
                } else {
                    Toggle("M", isOn: $device.mono)
                        .toggleStyle(.button).controlSize(.mini)
                        .help("Mono — collapse to a centered mono signal before this device")
                        .onChange(of: device.mono) { _, _ in app.engine.refreshDevices(for: track) }
                    Toggle("", isOn: $device.bypassed)
                        .toggleStyle(.switch).controlSize(.mini)
                        .help("Bypass")
                        .onChange(of: device.bypassed) { _, v in
                            (app.engine.liveNode(track: track, nodeID: device.nodeID) as? AudioEffect)?.bypassed = v
                        }
                    Button {
                        track.devices.removeAll { $0.id == device.id }
                        app.engine.refreshDevices(for: track)
                    } label: { Image(systemName: "trash") }.buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
            .opacity(device.bypassed ? 0.5 : 1)

            if device.kind == .fxArchitect {
                fxArchitectPresetStrip
            }
            if device.kind == .utility {
                utilityPresetStrip
            }

            ForEach(params) { p in
                DeviceParamSlider(track: track, device: device, param: p)
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }


    private var utilityPresetStrip: some View {
        HStack(spacing: 6) {
            Text("Utility")
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
            Button("Center") { applyUtilityPreset(["gain": 0, "width": 1, "balance": 0, "mono": 0, "invertL": 0, "invertR": 0, "swap": 0]) }
            Button("Hard L") { applyUtilityPreset(["gain": 0, "width": 1, "balance": -1, "mono": 0, "invertL": 0, "invertR": 0, "swap": 0]) }
            Button("Hard R") { applyUtilityPreset(["gain": 0, "width": 1, "balance": 1, "mono": 0, "invertL": 0, "invertR": 0, "swap": 0]) }
            Button("Mono") { applyUtilityPreset(["gain": 0, "width": 0, "balance": 0, "mono": 1, "invertL": 0, "invertR": 0, "swap": 0]) }
            Button("Phase Ø") { applyUtilityPreset(["invertL": 1, "invertR": 1]) }
            Button("Swap") { applyUtilityPreset(["swap": 1]) }
            Spacer()
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .padding(7)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func applyUtilityPreset(_ values: [String: Double]) {
        for (key, value) in values {
            device.params[key] = value
            app.engine.liveNode(track: track, nodeID: device.nodeID)?.setParam(key, value)
        }
    }

    private var fxArchitectPresetStrip: some View {
        HStack(spacing: 6) {
            Text("FX Preset")
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
            Menu(fxArchitectPresetName(device.params["preset"] ?? 0)) {
                Button("Riser") { applyFXArchitectPreset(0) }
                Button("Tonal Riser") { applyFXArchitectPreset(1) }
                Button("Impact") { applyFXArchitectPreset(2) }
                Button("Downlifter") { applyFXArchitectPreset(3) }
                Button("Noise Sweep") { applyFXArchitectPreset(4) }
            }
            .controlSize(.small)
            Spacer()
            Text("self-generating")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(7)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func fxArchitectPresetName(_ value: Double) -> String {
        switch Int(value.rounded()) {
        case 1: return "Tonal Riser"
        case 2: return "Impact"
        case 3: return "Downlifter"
        case 4: return "Noise Sweep"
        default: return "Riser"
        }
    }

    private func applyFXArchitectPreset(_ index: Int) {
        let presets: [[String: Double]] = [
            ["preset": 0, "length": 8, "intensity": 0.74, "root": 130.81, "sweep": 0.84, "tone": 0.62, "stereo": 0.48, "output": -9, "mix": 1],
            ["preset": 1, "length": 8, "intensity": 0.68, "root": 146.83, "sweep": 0.76, "tone": 0.50, "stereo": 0.36, "output": -10, "mix": 1],
            ["preset": 2, "length": 4, "intensity": 0.90, "root": 65.41, "sweep": 0.38, "tone": 0.36, "stereo": 0.24, "output": -7, "mix": 1],
            ["preset": 3, "length": 8, "intensity": 0.70, "root": 196.00, "sweep": 0.82, "tone": 0.48, "stereo": 0.58, "output": -10, "mix": 1],
            ["preset": 4, "length": 8, "intensity": 0.64, "root": 110.00, "sweep": 0.92, "tone": 0.74, "stereo": 0.70, "output": -12, "mix": 1]
        ]
        let values = presets[max(0, min(index, presets.count - 1))]
        for (key, value) in values {
            device.params[key] = value
            app.engine.liveNode(track: track, nodeID: device.nodeID)?.setParam(key, value)
        }
    }

    private func icon(_ k: DeviceKind) -> String {
        switch k {
        case .reverb, .hybridReverb: return "waveform.path.ecg"
        case .delay, .echo, .filterDelay, .grainDelay, .vectorDelay, .alignDelay: return "timelapse"
        case .fxArchitect: return "sparkles"
        case .autoFilter, .shaper, .lfo, .envelopeFollower: return "camera.filters"
        case .eqEight, .channelEQ, .eqThree, .spectrum, .tuner: return "slider.vertical.3"
        case .compressor, .glueCompressor, .multibandDynamics, .gate, .limiter: return "rectangle.compress.vertical"
        case .tune, .pitch, .shifter, .scale, .velocity, .noteLength, .random, .chord, .arpeggiator, .bouncyNotes: return "tuningfork"
        case .amp, .overdrive, .pedal, .dynamicTube, .saturator, .roar, .vinylDistortion, .drumBuss: return "bolt.fill"
        case .autoPan, .beatRepeat, .chorusEnsemble, .phaserFlanger, .erosion, .redux: return "waveform"
        case .drumRack, .impulse, .dsClap, .dsClang, .dsCymbal, .dsHH, .dsKick, .dsSnare, .dsTone: return "square.grid.4x3.fill"
        case .audioEffectRack, .instrumentRack, .midiEffectRack: return "square.stack.3d.up"
        case .sampler, .simpler, .granulator, .spectralResonator, .spectralTime, .resonators, .corpus, .looper, .vocoder: return "waveform.badge.magnifyingglass"
        case .analog, .bass, .collision, .drift, .electric, .emit, .meld, .operatorSynth, .poli, .tension, .treeTone, .vectorFM, .vectorGrain, .wavetable, .oscillatron, .lemmingBass: return "keyboard"
        case .dubstepWrangler: return "waveform.path.ecg.rectangle"
        case .externalAudioEffect, .externalInstrument, .cvInstrument, .cvTriggers: return "cable.connector"
        case .bhangraArchitect: return "circle.grid.cross"
        case .guaracha2C: return "2.circle.fill"
        case .bailaton: return "music.note.house.fill"
        case .cabinet, .utility: return "dial.medium"
        }
    }
}

struct DeviceParamSlider: View {
    @Environment(AppState.self) private var app
    let track: Track
    let device: DeviceModel
    let param: ParamInfo

    var body: some View {
        let value = device.params[param.id] ?? param.min
        VStack(alignment: .leading, spacing: 1) {
            HStack {
                Text(param.name).font(.caption)
                if app.pendingMIDILearnTarget?.trackID == track.id && app.pendingMIDILearnTarget?.nodeID == device.nodeID && app.pendingMIDILearnTarget?.paramID == param.id {
                    Text("LEARN")
                        .font(.caption2.bold())
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.20))
                        .clipShape(Capsule())
                }
                Spacer()
                Text(format(value)).font(.caption2).foregroundStyle(.secondary).monospacedDigit()
            }
            Slider(value: Binding(
                get: { param.normalize(device.params[param.id] ?? param.min) },
                set: { norm in
                    let v = param.denormalize(norm)
                    device.params[param.id] = v
                    app.engine.liveNode(track: track, nodeID: device.nodeID)?.setParam(param.id, v)
                }
            ))
            .contextMenu {
                Button("MIDI Learn…") {
                    app.beginMIDILearn(track: track, nodeID: device.nodeID, paramID: param.id, paramName: param.name)
                }
                Button("Cancel MIDI Learn") { app.cancelMIDILearn() }
            }
            .help("Right-click for MIDI Learn. Move a CC knob, slider, or pitch-bend wheel to bind it.")
        }
    }

    private func format(_ v: Double) -> String {
        if param.id == "preset" {
            switch Int(v.rounded()) {
            case 1: return "Tonal"
            case 2: return "Impact"
            case 3: return "Down"
            case 4: return "Sweep"
            default: return "Riser"
            }
        }
        if param.unit == "Hz" { return v >= 1000 ? String(format: "%.1fk", v/1000) : String(format: "%.0f", v) }
        if param.unit == "dB" || param.unit == "ms" { return String(format: "%.0f%@", v, param.unit) }
        if param.unit == "s" { return String(format: "%.2fs", v) }
        return String(format: "%.2f", v)
    }
}
