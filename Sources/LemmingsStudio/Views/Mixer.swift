import SwiftUI

// MARK: - Mixer (Logic Pro-style channel strips)
//
// A horizontal rack of channel strips with a pinned master strip on the right.
// Each strip carries: a colour-coded header, a pan control, solo/mute, a long
// vertical fader, and a live peak meter pulled from the audio engine. The look
// is deliberately Logic-flavoured — tall faders, meters hugging the fader, a
// distinct master strip — without trying to clone its chrome pixel-for-pixel.

struct MixerView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView(.horizontal, showsIndicators: true) {
                HStack(alignment: .top, spacing: 1) {
                    ForEach(app.project.tracks) { track in
                        ChannelStrip(track: track)
                    }
                    ForEach(app.project.returnBuses) { bus in
                        ReturnStrip(bus: bus)
                    }
                    MasterStrip()
                        .padding(.leading, 6)
                }
                .padding(12)
            }
            .background(Color(nsColor: .underPageBackgroundColor))
        }
    }

    private var header: some View {
        HStack {
            Text("Mixer").font(.system(size: 13, weight: .semibold))
            Text("\(app.project.tracks.count) channels")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            Menu {
                ForEach(InstrumentKind.allCases) { kind in
                    Button(kind.rawValue) { app.addTrack(kind: kind) }
                }
                Divider()
                Button("Return Bus") { app.addReturnBus() }
                Button("Group Selected") { app.groupSelectedTracks() }
                Button("Ungroup Selected") { app.ungroupSelectedTracks() }
                Button("Delete Selected Tracks", role: .destructive) { app.deleteSelectedTracks() }
                Button("Duplicate Selected") { app.duplicateSelectedTrack() }
            } label: {
                Label("Add Channel", systemImage: "plus")
            }
            .menuStyle(.borderlessButton).fixedSize()
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }
}

// MARK: - Channel strip

private struct ChannelStrip: View {
    @Environment(AppState.self) private var app
    @Bindable var track: Track

    private var anySolo: Bool { app.project.tracks.contains { $0.solo } }
    private var audible: Bool { !track.mute && (!anySolo || track.solo) }

    var body: some View {
        let selected = app.selectedTrackID == track.id || app.selectedTrackIDs.contains(track.id)
        VStack(spacing: 8) {
            // Colour + name header
            Text(track.name)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1).truncationMode(.tail)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .background(track.color.opacity(selected ? 0.9 : 0.55))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            Text(track.kind.rawValue)
                .font(.system(size: 8)).foregroundStyle(.secondary)
                .lineLimit(1)

            PanControl(pan: $track.pan)

            VStack(spacing: 3) {
                ForEach(app.project.returnBuses) { bus in
                    SendKnob(track: track, bus: bus)
                }
            }
            .frame(height: max(22, CGFloat(app.project.returnBuses.count) * 18))

            mixerDeviceStack

            // Fader + meter side by side
            HStack(alignment: .center, spacing: 6) {
                VerticalFader(value: $track.volume)
                ChannelMeter(track: track, audible: audible)
            }
            .frame(height: 200)

            Text(gainLabel(track.volume))
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)

            HStack(spacing: 4) {
                StripButton(label: "M", active: track.mute, activeColor: .orange) {
                    app.toggleMute(track)
                }
                StripButton(label: "S", active: track.solo, activeColor: .yellow) {
                    app.toggleSolo(track)
                }
            }
        }
        .padding(8)
        .frame(width: 88)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: .controlBackgroundColor))
                .opacity(selected ? 1 : 0.6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 1.5)
        )
        .contentShape(Rectangle())
        .onTapGesture { app.selectTrack(track, extending: NSEvent.modifierFlags.contains(.shift)) }
    }

    private var mixerDeviceStack: some View {
        VStack(spacing: 2) {
            MixerFXDropSlot(label: track.devices.isEmpty ? "Drop FX" : "") { text in
                app.handleMixerDeviceDropText(text, on: track, at: 0)
            }
            ForEach(Array(track.devices.enumerated()), id: \.element.id) { index, device in
                mixerDevicePill(device, index: index)
                MixerFXDropSlot(label: "") { text in
                    app.handleMixerDeviceDropText(text, on: track, at: index + 1)
                }
            }
        }
        .frame(width: 72)
    }

    private func mixerDevicePill(_ device: DeviceModel, index: Int) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "line.3.horizontal").font(.system(size: 7, weight: .bold)).foregroundStyle(.secondary)
            Text(device.kind.rawValue).lineLimit(1)
            Spacer(minLength: 0)
        }
        .font(.system(size: 8, weight: .medium))
        .padding(.horizontal, 5).padding(.vertical, 3)
        .background(Color.black.opacity(0.18))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .contentShape(Rectangle())
        .contextMenu {
            if index > 0 { Button("Move Earlier") { app.moveDevice(on: track, from: IndexSet(integer: index), to: index - 1) } }
            if index < track.devices.count - 1 { Button("Move Later") { app.moveDevice(on: track, from: IndexSet(integer: index), to: index + 2) } }
        }
        .onDrag { NSItemProvider(object: PluginDragPasteboard.encodeMixerDevice(ownerKind: "track", ownerID: track.id, deviceID: device.id) as NSString) }
    }

    private func gainLabel(_ v: Float) -> String {
        guard v > 0.0001 else { return "-∞" }
        let db = 20 * log10(v)
        return String(format: "%+.1f", db)
    }
}


private struct SendKnob: View {
    @Bindable var track: Track
    let bus: ReturnBus
    private var amountBinding: Binding<Float> {
        Binding(get: {
            track.sends.first(where: { $0.returnBusID == bus.id })?.amount ?? 0
        }, set: { newValue in
            if let idx = track.sends.firstIndex(where: { $0.returnBusID == bus.id }) {
                track.sends[idx].amount = newValue
            } else {
                track.sends.append(SendSlot(returnBusID: bus.id, amount: newValue))
            }
        })
    }
    var body: some View {
        HStack(spacing: 4) {
            Text(String(bus.name.prefix(1))).font(.system(size: 8, weight: .bold))
            Slider(value: amountBinding, in: 0...1).controlSize(.mini)
        }
    }
}

private struct ReturnStrip: View {
    @Environment(AppState.self) private var app
    @Bindable var bus: ReturnBus
    var body: some View {
        VStack(spacing: 8) {
            Text(bus.name.uppercased())
                .font(.system(size: 11, weight: .bold))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .background(Color.purple.opacity(0.65))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            Text("Return") .font(.system(size: 8)).foregroundStyle(.secondary)
            PanControl(pan: $bus.pan)
            Color.clear.frame(height: 32)
            HStack(alignment: .center, spacing: 6) { VerticalFader(value: $bus.volume); Capsule().fill(Color.purple.opacity(0.4)).frame(width: 8) }
                .frame(height: 200)
            returnDeviceStack
            Text("FX \(bus.devices.count)").font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
            StripButton(label: "M", active: bus.mute, activeColor: .orange) { bus.mute.toggle() }
        }
        .padding(8)
        .frame(width: 88)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor)).opacity(0.75))
    }

    private var returnDeviceStack: some View {
        VStack(spacing: 2) {
            MixerFXDropSlot(label: bus.devices.isEmpty ? "Drop FX" : "") { text in
                app.handleMixerDeviceDropText(text, on: bus, at: 0)
            }
            ForEach(Array(bus.devices.enumerated()), id: \.element.id) { index, device in
                Text(device.kind.rawValue)
                    .font(.system(size: 8, weight: .medium))
                    .lineLimit(1)
                    .padding(.horizontal, 5).padding(.vertical, 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.black.opacity(0.18))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .onDrag { NSItemProvider(object: PluginDragPasteboard.encodeMixerDevice(ownerKind: "bus", ownerID: bus.id, deviceID: device.id) as NSString) }
                MixerFXDropSlot(label: "") { text in
                    app.handleMixerDeviceDropText(text, on: bus, at: index + 1)
                }
            }
        }
        .frame(width: 72)
    }
}

// MARK: - Master strip

private struct MasterStrip: View {
    @Environment(AppState.self) private var app
    @State private var master: Float = 1.0

    var body: some View {
        VStack(spacing: 8) {
            Text("MASTER")
                .font(.system(size: 11, weight: .bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .background(Color.primary.opacity(0.75))
                .foregroundStyle(Color(nsColor: .windowBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 4))

            Text("Stereo Out")
                .font(.system(size: 8)).foregroundStyle(.secondary)

            // Master has no pan; keep the layout aligned with channel strips.
            Color.clear.frame(height: 22)

            HStack(alignment: .center, spacing: 6) {
                VerticalFader(value: Binding(
                    get: { master },
                    set: { master = $0; app.engine.masterVolume = $0 }
                ))
                MasterMeter()
            }
            .frame(height: 200)

            Text(gainLabel(master))
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)

            Color.clear.frame(height: 20)
        }
        .padding(8)
        .frame(width: 96)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.primary.opacity(0.25), lineWidth: 1)
        )
        .onAppear { master = app.engine.masterVolume }
    }

    private func gainLabel(_ v: Float) -> String {
        guard v > 0.0001 else { return "-∞" }
        let db = 20 * log10(v)
        return String(format: "%+.1f", db)
    }
}

// MARK: - Pan

private struct PanControl: View {
    @Binding var pan: Float

    var body: some View {
        VStack(spacing: 2) {
            Slider(value: $pan, in: -1...1)
                .controlSize(.mini)
            Text(panLabel)
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .frame(height: 22)
    }

    private var panLabel: String {
        if abs(pan) < 0.02 { return "C" }
        let pct = Int(abs(pan) * 100)
        return pan < 0 ? "L\(pct)" : "R\(pct)"
    }
}

// MARK: - Vertical fader

private struct VerticalFader: View {
    @Binding var value: Float   // 0...1, perceptual taper applied for display

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let knobH: CGFloat = 18
            let travel = h - knobH
            let y = travel * CGFloat(1 - displayPosition)

            ZStack(alignment: .top) {
                // Track groove
                Capsule()
                    .fill(Color.black.opacity(0.35))
                    .frame(width: 4)
                    .frame(maxHeight: .infinity)
                    .frame(maxWidth: .infinity)

                // Knob
                RoundedRectangle(cornerRadius: 3)
                    .fill(LinearGradient(colors: [Color(white: 0.85), Color(white: 0.55)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 28, height: knobH)
                    .overlay(
                        Rectangle().fill(Color.black.opacity(0.5))
                            .frame(width: 22, height: 1.5)
                    )
                    .shadow(radius: 1, y: 1)
                    .offset(y: y)
                    .frame(maxWidth: .infinity)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        let pos = 1 - Double((g.location.y - knobH / 2) / max(1, travel))
                        setDisplayPosition(pos.clamped(to: 0...1))
                    }
            )
        }
        .frame(width: 30)
    }

    // Map a 0..1 fader position to amplitude with a roughly perceptual taper:
    // top of the fader is unity (1.0), and travel feels even in dB terms.
    private var displayPosition: Double {
        // invert the taper used in setDisplayPosition
        let v = Double(value)
        guard v > 0.0001 else { return 0 }
        let db = 20 * log10(v)          // ... -60 ... 0
        return ((db + 60) / 60).clamped(to: 0...1)
    }

    private func setDisplayPosition(_ pos: Double) {
        if pos <= 0.0001 { value = 0; return }
        let db = pos * 60 - 60          // 0 -> -60dB, 1 -> 0dB
        value = Float(pow(10, db / 20))
    }
}

// MARK: - Meters

private struct ChannelMeter: View {
    @Environment(AppState.self) private var app
    let track: Track
    let audible: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { _ in
            let peak = audible ? app.engine.meterPeak(for: track) : 0
            let clipped = audible && app.engine.meterIsClipping(for: track)
            MeterBar(level: peak, clipped: clipped)
        }
        .frame(width: 8)
    }
}

private struct MasterMeter: View {
    @Environment(AppState.self) private var app
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { _ in
            MeterBar(level: app.engine.masterMeterPeak(), clipped: app.engine.masterMeterIsClipping())
        }
        .frame(width: 8)
    }
}

private struct MeterBar: View {
    let level: Float   // 0...1 linear peak
    var clipped: Bool = false

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let frac = CGFloat(displayFraction)
            ZStack(alignment: .bottom) {
                Capsule().fill(Color.black.opacity(0.4))
                Capsule()
                    .fill(meterGradient)
                    .frame(height: h * frac)
                if clipped {
                    VStack {
                        Text("CLIP")
                            .font(.system(size: 6, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 2)
                            .background(Color.red)
                            .clipShape(RoundedRectangle(cornerRadius: 2))
                        Spacer()
                    }
                }
            }
        }
    }

    // Convert linear peak to a dB-ish meter fill so quiet signals are visible.
    private var displayFraction: Double {
        guard level > 0.0001 else { return 0 }
        let db = 20 * log10(Double(level))
        return ((db + 54) / 54).clamped(to: 0...1)
    }

    private var meterGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: .green, location: 0.0),
                .init(color: .green, location: 0.7),
                .init(color: .yellow, location: 0.85),
                .init(color: .red, location: 1.0)
            ],
            startPoint: .bottom, endPoint: .top)
    }
}

// MARK: - Small button

private struct StripButton: View {
    let label: String
    let active: Bool
    let activeColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .frame(width: 24, height: 18)
                .background(active ? activeColor : Color.secondary.opacity(0.2))
                .foregroundStyle(active ? Color.black : Color.secondary)
                .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Util

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
