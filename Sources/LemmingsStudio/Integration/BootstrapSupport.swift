import Foundation

public enum TempoDetector {
    /// Lightweight offline tempo hint. First looks for common filename metadata
    /// like "128bpm" or "_90 BPM_"; then falls back to a simple onset-energy
    /// estimate so imported loops can auto-warp without requiring cloud analysis.
    public static func detectTempoHint(from url: URL, samples: [Float], sampleRate: Double) -> Double? {
        if let fromName = bpmFromFilename(url.lastPathComponent) { return fromName }
        if let fromMetadata = bpmFromWAVInfo(url) { return fromMetadata }
        return bpmFromOnsets(samples: samples, sampleRate: sampleRate)
    }


    private static func bpmFromWAVInfo(_ url: URL) -> Double? {
        guard url.pathExtension.lowercased() == "wav",
              let data = try? Data(contentsOf: url), data.count > 32 else { return nil }
        guard String(data: data[0..<4], encoding: .ascii) == "RIFF",
              String(data: data[8..<12], encoding: .ascii) == "WAVE" else { return nil }
        var offset = 12
        while offset + 8 <= data.count {
            let id = String(data: data[offset..<offset+4], encoding: .ascii) ?? ""
            let size = Int(data[offset+4]) | (Int(data[offset+5]) << 8) | (Int(data[offset+6]) << 16) | (Int(data[offset+7]) << 24)
            let payloadStart = offset + 8
            let payloadEnd = min(data.count, payloadStart + max(0, size))
            if id == "LIST", payloadEnd - payloadStart >= 4,
               String(data: data[payloadStart..<payloadStart+4], encoding: .ascii) == "INFO" {
                var inner = payloadStart + 4
                while inner + 8 <= payloadEnd {
                    let cid = String(data: data[inner..<inner+4], encoding: .ascii) ?? ""
                    let csize = Int(data[inner+4]) | (Int(data[inner+5]) << 8) | (Int(data[inner+6]) << 16) | (Int(data[inner+7]) << 24)
                    let cstart = inner + 8
                    let cend = min(payloadEnd, cstart + max(0, csize))
                    if ["IBPM", "TBPM", "BPM "].contains(cid), cend > cstart {
                        let text = String(data: data[cstart..<cend], encoding: .utf8)?.trimmingCharacters(in: .controlCharacters.union(.whitespacesAndNewlines)) ?? ""
                        if let bpm = Double(text.filter { "0123456789.".contains($0) }), (40...300).contains(bpm) { return bpm }
                    }
                    inner = cstart + csize + (csize % 2)
                }
            }
            offset = payloadStart + size + (size % 2)
        }
        return nil
    }

    private static func bpmFromFilename(_ name: String) -> Double? {
        let lower = name.lowercased()
        let pattern = #"([0-9]{2,3})(?:\s|-|_)?bpm"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(lower.startIndex..<lower.endIndex, in: lower)
        guard let match = regex.firstMatch(in: lower, range: range), match.numberOfRanges > 1,
              let r = Range(match.range(at: 1), in: lower), let bpm = Double(lower[r]), (50...220).contains(bpm) else { return nil }
        return bpm
    }

    private static func bpmFromOnsets(samples: [Float], sampleRate: Double) -> Double? {
        guard samples.count > Int(sampleRate * 2), sampleRate > 0 else { return nil }
        let hop = max(256, Int(sampleRate / 100))
        var env: [Float] = []
        var i = 0
        while i < samples.count {
            let end = min(samples.count, i + hop)
            var e: Float = 0
            for j in i..<end { e += abs(samples[j]) }
            env.append(e / Float(max(1, end - i)))
            i += hop
        }
        guard env.count > 8 else { return nil }
        let mean = env.reduce(0, +) / Float(env.count)
        var peaks: [Int] = []
        for k in 1..<(env.count - 1) where env[k] > mean * 1.6 && env[k] > env[k-1] && env[k] >= env[k+1] {
            if peaks.last.map({ k - $0 > 3 }) ?? true { peaks.append(k) }
        }
        guard peaks.count >= 4 else { return nil }
        let diffs = zip(peaks.dropFirst(), peaks).map { $0.0 - $0.1 }.filter { $0 > 0 }
        guard !diffs.isEmpty else { return nil }
        let median = diffs.sorted()[diffs.count / 2]
        var bpm = 60.0 / (Double(median * hop) / sampleRate)
        while bpm < 70 { bpm *= 2 }
        while bpm > 180 { bpm /= 2 }
        return (60...200).contains(bpm) ? bpm.rounded() : nil
    }
}

public enum BootstrapInstaller {
    @discardableResult public static func ensureHomebrewAndOllama() -> String {
        let brew = commandExists("brew")
        if !brew {
            let script = #"/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)""#
            _ = run("/bin/bash", ["-lc", script])
        }
        let brewNow = commandExists("brew")
        let ollama = commandExists("ollama")
        if brewNow && !ollama {
            _ = run("/bin/bash", ["-lc", "brew install ollama"])
        }
        let finalBrew = commandExists("brew") ? "Homebrew OK" : "Homebrew missing"
        let finalOllama = commandExists("ollama") ? "Ollama OK" : "Ollama missing"
        return "\(finalBrew); \(finalOllama)"
    }

    private static func commandExists(_ name: String) -> Bool {
        run("/usr/bin/env", ["which", name]).status == 0
    }

    private static func run(_ exe: String, _ args: [String]) -> (status: Int32, output: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run(); p.waitUntilExit() } catch { return (-1, error.localizedDescription) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }
}
