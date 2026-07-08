import SwiftUI
import UniformTypeIdentifiers
import AVFoundation

struct VisionSampleBrowserItem: Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
    let localURL: URL
    let durationSeconds: Double
    let sourceLabel: String

    init(name: String, localURL: URL, durationSeconds: Double, sourceLabel: String = "Files") {
        self.id = UUID()
        self.name = name
        self.localURL = localURL
        self.durationSeconds = durationSeconds
        self.sourceLabel = sourceLabel
    }
}

struct VisionSampleBrowserView: View {
    @Environment(VisionStudioModel.self) private var model
    @State private var showingImporter = false
    @State private var query = ""

    private var filteredItems: [VisionSampleBrowserItem] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return model.sampleBrowserItems }
        return model.sampleBrowserItems.filter { $0.name.localizedCaseInsensitiveContains(needle) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Sample Browser", systemImage: "waveform.badge.magnifyingglass")
                    .font(.title2.bold())
                Spacer()
                Button("Import from Files", systemImage: "folder.badge.plus") {
                    showingImporter = true
                }
                .buttonStyle(.borderedProminent)
            }

            HStack(spacing: 12) {
                TextField("Search imported samples", text: $query)
                    .textFieldStyle(.roundedBorder)
                Label("Files / iCloud / File Providers", systemImage: "externaldrive.connected.to.line.below")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if filteredItems.isEmpty {
                ContentUnavailableView(
                    "No Samples Yet",
                    systemImage: "waveform",
                    description: Text("Import audio from the system Files picker. Samples are copied into LemmingsStudio's local sample cache for reliable playback.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filteredItems) { item in
                    HStack(spacing: 14) {
                        Image(systemName: "waveform")
                            .font(.title2)
                            .frame(width: 34)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.name).font(.headline)
                            Text("\(durationText(item.durationSeconds)) • \(item.sourceLabel)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button("Preview", systemImage: "play.fill") {
                            model.previewSampleBrowserItem(item)
                        }
                        Button("Arrangement", systemImage: "rectangle.3.group") {
                            model.insertSampleBrowserItemIntoArrangement(item)
                        }
                        Button("Sequencer", systemImage: "square.grid.4x3.fill") {
                            model.mapSampleBrowserItemToSequencer(item)
                        }
                    }
                    .padding(.vertical, 5)
                }
                .listStyle(.plain)
            }

            HStack {
                Label("Cloud adapter boundary", systemImage: "cloud")
                    .font(.caption.bold())
                Text("The browser model is provider-neutral. A later rclone/WebDAV or rclone RC gateway can feed the same item list without changing Arrangement or Sequencer insertion.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .lemmingsGlass(cornerRadius: 16)
        }
        .padding(22)
        .background(VisionThemeBackground(theme: model.visualTheme))
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                model.importSampleBrowserURLs(urls)
            case .failure(let error):
                model.statusMessage = "Sample import failed: \(error.localizedDescription)"
            }
        }
    }

    private func durationText(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "Unknown length" }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

extension VisionStudioModel {
    func importSampleBrowserURLs(_ urls: [URL]) {
        let fm = FileManager.default
        let cacheRoot = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LemmingsStudio/Samples", isDirectory: true)
        do {
            try fm.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
        } catch {
            statusMessage = "Could not create sample cache: \(error.localizedDescription)"
            return
        }

        var imported = 0
        for sourceURL in urls {
            let accessed = sourceURL.startAccessingSecurityScopedResource()
            defer { if accessed { sourceURL.stopAccessingSecurityScopedResource() } }

            let destination = uniqueSampleDestination(for: sourceURL, in: cacheRoot)
            do {
                try fm.copyItem(at: sourceURL, to: destination)
                let duration = Self.sampleDurationSeconds(at: destination)
                sampleBrowserItems.append(.init(
                    name: destination.deletingPathExtension().lastPathComponent,
                    localURL: destination,
                    durationSeconds: duration,
                    sourceLabel: "Files"
                ))
                imported += 1
            } catch {
                statusMessage = "Sample import failed for \(sourceURL.lastPathComponent): \(error.localizedDescription)"
            }
        }

        if imported > 0 {
            sampleBrowserItems.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            statusMessage = "Imported \(imported) sample\(imported == 1 ? "" : "s")"
        }
    }

    func previewSampleBrowserItem(_ item: VisionSampleBrowserItem) {
        ensureSamplePreviewEngineRunning()
        audioEngine.playOneShotSample(path: item.localURL.path, projectURL: currentProjectURL, volume: 0.95, pan: 0)
        statusMessage = "Previewing \(item.name)"
    }

    func insertSampleBrowserItemIntoArrangement(_ item: VisionSampleBrowserItem) {
        let beats = max(0.25, item.durationSeconds * project.effectiveTempo / 60.0)
        let candidate = VisionSpliceSampleCandidate(
            id: item.id.uuidString,
            title: item.name,
            producer: nil,
            bpm: nil,
            key: nil,
            tags: ["local", "sample-browser"],
            lengthBeats: beats,
            remoteURI: item.localURL.absoluteString,
            previewURI: nil,
            downloadURI: nil,
            pageURI: nil,
            localFilePath: item.localURL.path,
            licenseSummary: "User-imported local sample"
        )
        importSampleCandidateToArrangement(candidate)
    }

    func mapSampleBrowserItemToSequencer(_ item: VisionSampleBrowserItem) {
        let candidate = VisionSpliceSampleCandidate(
            id: item.id.uuidString,
            title: item.name,
            producer: nil,
            bpm: nil,
            key: nil,
            tags: ["local", "sample-browser"],
            lengthBeats: 1,
            remoteURI: item.localURL.absoluteString,
            previewURI: nil,
            downloadURI: nil,
            pageURI: nil,
            localFilePath: item.localURL.path,
            licenseSummary: "User-imported local sample"
        )
        importSampleCandidateToStepSequencer(candidate)
    }

    private func ensureSamplePreviewEngineRunning() {
        guard !audioEngineRunning else { return }
        do {
            try audioEngine.start()
            audioEngineRunning = true
        } catch {
            statusMessage = "Audio unavailable: \(error.localizedDescription)"
        }
    }

    private func uniqueSampleDestination(for source: URL, in directory: URL) -> URL {
        let fm = FileManager.default
        let stem = source.deletingPathExtension().lastPathComponent
        let ext = source.pathExtension
        var candidate = directory.appendingPathComponent(source.lastPathComponent)
        var counter = 2
        while fm.fileExists(atPath: candidate.path) {
            let name = ext.isEmpty ? "\(stem) \(counter)" : "\(stem) \(counter).\(ext)"
            candidate = directory.appendingPathComponent(name)
            counter += 1
        }
        return candidate
    }

    private static func sampleDurationSeconds(at url: URL) -> Double {
        guard let file = try? AVAudioFile(forReading: url), file.processingFormat.sampleRate > 0 else { return 0 }
        return Double(file.length) / file.processingFormat.sampleRate
    }
}
