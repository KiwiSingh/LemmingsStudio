import Foundation
import Observation

struct VisionBounceRequest: Codable, Identifiable, Hashable, Sendable {
    enum Scope: String, Codable, CaseIterable, Identifiable, Sendable {
        case master, selectedTrack, stems, selectedClip
        var id: String { rawValue }
        var label: String {
            switch self {
            case .master: return "Master"
            case .selectedTrack: return "Selected Track"
            case .stems: return "Stems"
            case .selectedClip: return "Selected Clip"
            }
        }
    }
    enum Format: String, Codable, CaseIterable, Identifiable, Sendable { case wav24, wav32Float, aiff24, cafFloat; var id: String { rawValue } }
    var id = UUID()
    var scope: Scope
    var format: Format
    var startBeat: Double
    var endBeat: Double
    var includeReturnBuses: Bool
    var includeCompanionReturn: Bool
    var normalize: Bool
    var destinationHint: String
}

@MainActor
@Observable
final class VisionBounceParityState {
    var request = VisionBounceRequest(scope: .master, format: .wav32Float, startBeat: 0, endBeat: 128, includeReturnBuses: true, includeCompanionReturn: true, normalize: false, destinationHint: "Documents/Exports")
    var status = "Project bounce idle"
    var dryRunPlan = ""

    func refreshPlan(project: LemmingsProject) {
        request.endBeat = max(request.endBeat, project.totalBeats)
        dryRunPlan = "mac-host-render --scope \(request.scope.rawValue) --format \(request.format.rawValue) --beats \(request.startBeat)-\(request.endBeat) --returns \(request.includeReturnBuses) --hosted-return \(request.includeCompanionReturn)"
        status = "Prepared Mac Host Mode bounce plan for \(project.name)."
    }
}

extension VisionStudioModel {
    func prepareVisionBounceDryRun() {
        bounceParity.refreshPlan(project: project)
        statusMessage = bounceParity.status
    }

    func renderProjectOnMacHost() {
        bounceParity.refreshPlan(project: project)
        do {
            let request = try makeDesktopProjectBounceRequest()
            desktopBridge.requestProjectBounce(request)
            bounceParity.status = "Sent \(bounceParity.request.scope.label) render to Mac Host Mode."
            statusMessage = bounceParity.status
        } catch {
            bounceParity.status = "Bounce preparation failed: \(error.localizedDescription)"
            statusMessage = bounceParity.status
        }
    }

    private func makeDesktopProjectBounceRequest() throws -> DesktopProjectBounceRequest {
        let bounce = bounceParity.request
        let selectedTrackIDs: [UUID] = {
            guard bounce.scope == .selectedTrack || bounce.scope == .selectedClip else { return [] }
            if let selectedClipID {
                return project.tracks.filter { track in
                    track.clips.contains(where: { $0.id == selectedClipID }) || track.audioClips.contains(where: { $0.id == selectedClipID })
                }.map(\.id)
            }
            return []
        }()

        var assets: [DesktopProjectBounceAsset] = []
        var assetIDsByPath: [String: String] = [:]

        func assetID(for path: String) throws -> String {
            if let existing = assetIDsByPath[path] { return existing }
            let url = URL(fileURLWithPath: path)
            let data = try Data(contentsOf: url)
            let id = UUID().uuidString
            assets.append(.init(assetID: id, filename: url.lastPathComponent, base64: data.base64EncodedString()))
            assetIDsByPath[path] = id
            return id
        }

        let tracks: [DesktopProjectBounceTrack] = try project.tracks.map { track in
            let clips = try track.audioClips.compactMap { clip -> DesktopProjectBounceClip? in
                guard let path = clip.sourcePath, !path.isEmpty else { return nil }
                if bounce.scope == .selectedClip, clip.id != selectedClipID { return nil }
                return try .init(
                    assetID: assetID(for: path),
                    startBeat: clip.startBeat,
                    lengthBeats: clip.lengthBeats,
                    sourceOffsetBeats: clip.sourceOffsetBeats ?? 0,
                    sourceBPM: clip.sourceBPM,
                    playbackRate: clip.playbackRate ?? 1
                )
            }
            return .init(
                id: track.id,
                name: track.name,
                volume: Double(track.volume ?? 1),
                pan: Double(track.pan ?? 0),
                muted: track.mute == true,
                solo: track.solo == true,
                sends: Dictionary(uniqueKeysWithValues: (track.sends ?? [:]).map { ($0.key, Double($0.value)) }),
                clips: clips
            )
        }

        let returns = (project.returnBuses ?? VisionReturnBus.defaults).map {
            DesktopProjectBounceReturnBus(
                id: $0.id,
                name: $0.name,
                volume: Double($0.volume),
                pan: Double($0.pan),
                muted: $0.mute,
                effectKind: $0.effectKind,
                effectMix: Double($0.effectMix ?? 0)
            )
        }

        let scope = bounce.scope == .selectedClip ? "selectedTrack" : bounce.scope.rawValue
        return .init(
            requestID: UUID(),
            projectName: project.name,
            scope: scope,
            bpm: project.effectiveTempo,
            startBeat: bounce.startBeat,
            endBeat: max(bounce.startBeat + 0.25, bounce.endBeat),
            sampleRate: 48_000,
            selectedTrackIDs: selectedTrackIDs,
            includeReturnBuses: bounce.includeReturnBuses,
            includeCompanionReturn: bounce.includeCompanionReturn,
            normalize: bounce.normalize,
            activeHostedInstanceID: desktopBridge.activeInstanceID,
            assets: assets,
            tracks: tracks,
            returnBuses: returns
        )
    }
}
