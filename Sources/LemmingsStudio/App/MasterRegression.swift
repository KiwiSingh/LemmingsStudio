import Foundation
import AVFoundation
import AppKit

private final class MasterMeterCapture { var maximum = 0.0 }
private enum MasterRegressionState { static var started = false }
extension AppState {
    @MainActor func runMasterRegression() {
        guard !MasterRegressionState.started else { return }; MasterRegressionState.started = true
        guard let i = CommandLine.arguments.firstIndex(of: "--validate-master"), CommandLine.arguments.count > i + 1 else { return }
        let output = URL(fileURLWithPath: CommandLine.arguments[i + 1], isDirectory: true)
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let quiet = CommandLine.arguments.contains("--headless-validation")
        if quiet { NSApp.hide(nil) }
        var report: [String:Any] = ["status":"running", "physical_audio_output":false]
        func check(_ value: Bool, _ message: String) throws { if !value { throw ExportError.renderFailed(message) } }
        func finish(_ error: Error? = nil) {
            report["status"] = error == nil ? "passed" : "failed"
            if let error { report["error"] = error.localizedDescription }
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted,.sortedKeys]) { try? data.write(to: output.appendingPathComponent("report.json")) }
            engine.stop(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { exit(error == nil ? 0 : 1) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [self] in
            do {
                let compressor = CompressorEffect()
                compressor.setParam("threshold", -24); compressor.setParam("ratio", 4); compressor.setParam("attack", 0.1); compressor.setParam("makeup", 12)
                var left = [Float](repeating: 0.5, count: 4096), right = left
                left.withUnsafeMutableBufferPointer { l in right.withUnsafeMutableBufferPointer { r in compressor.process(l.baseAddress!, r.baseAddress!, frames: 4096) } }
                let expected = (20 * log10(0.5) + 24) * 0.75
                try check(abs(compressor.gainReductionDB - expected) < 0.1, "Compressor GR includes makeup or reports wrong detector gain")
                report["compressor_expected_db"] = expected; report["compressor_measured_db"] = compressor.gainReductionDB
                compressor.bypassed = true; try check(compressor.gainReductionDB == 0, "Bypassed compressor retained GR")
                let limiter = LimiterEffect(); limiter.setParam("threshold", -12)
                left = .init(repeating: 0.5, count: 4096); right = left
                left.withUnsafeMutableBufferPointer { l in right.withUnsafeMutableBufferPointer { r in limiter.process(l.baseAddress!, r.baseAddress!, frames: 4096) } }
                try check(abs(limiter.gainReductionDB - (12 + 20 * log10(0.5))) < 0.2, "Limiter GR incorrect")
                report["limiter_measured_db"] = limiter.gainReductionDB
                project = Project(); project.tempo = 120; project.lengthBars = 1; project.masterDevices = []; project.masterExternalPluginSlots = []
                let track = Track(name:"Master audio test", kind:.audio, color:.blue)
                let audio = AudioClip(startBeat:0, samples:[Float](repeating:0.5,count:Int(engine.sampleRate * 2)), sampleRate:engine.sampleRate)
                audio.loopEnabled = false; track.audioClips = [audio]; project.tracks = [track]
                engine.attach(project:project); engine.masterVolume = 1
                try check(engine.masterProcessingError == nil, engine.masterProcessingError ?? "Master node failed")
                let dry = try offline.renderStereo(project:project)
                try check(dry.peak > 0.01,"Master node outputs silence")
                let model = DeviceModel(kind:.compressor); model.params["threshold"] = -36; model.params["ratio"] = 10; model.params["attack"] = 0.1; model.params["makeup"] = 0
                project.masterDevices = [model]; engine.rebuild()
                let meter = MasterMeterCapture()
                let wet = try offline.renderStereo(project:project, progress: { _ in meter.maximum = max(meter.maximum, self.engine.masterGainReductionDB()) })
                let range = Int(engine.sampleRate * 0.25)..<Int(engine.sampleRate * 1.5)
                let dryLevel = range.reduce(0.0) { $0 + abs(Double(dry.l[$1])) }
                let wetLevel = range.reduce(0.0) { $0 + abs(Double(wet.l[$1])) }
                try check(wetLevel < dryLevel * 0.65,"Master compressor did not affect actual offline audio")
                try check(meter.maximum > 5,"Master GR missing from processing chain")
                report["master_peak_reduction_db"] = meter.maximum
                report["dry_steady_mean"] = dryLevel / Double(range.count)
                report["compressed_steady_mean"] = wetLevel / Double(range.count)
                model.bypassed = true
                let bypass = try offline.renderStereo(project:project)
                try check(abs(bypass.peak - dry.peak) < 0.001 && engine.masterGainReductionDB() == 0,"Master bypass ineffective")
                report["actual_master_render_and_bypass"] = true
                report["dry_peak"] = dry.peak; report["compressed_peak"] = wet.peak
                project.masterDevices = []
                scanPlugins()
                let au = CommandLine.arguments.contains("--format-au")
                let format: PluginFormat = au ? .audioUnit : .vst3
                guard let plugin = discoveredPlugins.first(where: { $0.format == format && $0.role == .effect && AudioUnitCatalog.compact($0.name).hasSuffix("neutron5") }) else { throw ExportError.renderFailed("Neutron 5 unavailable for master insert test") }
                try check(addMasterPlugin(plugin), "Could not insert Neutron on Master: \(engine.masterProcessingError ?? editStatus)")
                let slot = project.masterExternalPluginSlots[0]
                try check(engine.capturedExternalState(for:slot) != nil, "Master plugin has no captured state")
                project.masterExternalPluginSlots[0].presetStateBase64 = engine.capturedExternalState(for:slot)
                if !quiet {
                    if let native = engine.liveNativePlugin(for:slot) {
                        try check(native.showEditor(), "Master VST3 editor failed"); native.hideEditor()
                    } else { openPluginGUI(slot) }
                }
                report["editor_opened_in_this_run"] = !quiet
                let rendered = try offline.renderStereo(project:project)
                try check(rendered.peak > 0.001 && rendered.l.allSatisfy(\.isFinite), "Master plugin render failed")
                engine.masterVolume = 0.6
                project.masterExternalPluginSlots[0].bypassed = true
                let data = try ProjectDocument(project:project).encoded()
                try data.write(to: output.appendingPathComponent("master.lemmingsproject"))
                let restored = try JSONDecoder().decode(ProjectDocument.self,from:data).makeProject()
                try check(restored.masterExternalPluginSlots.count == 1 && restored.masterExternalPluginSlots[0].id == slot.id && restored.masterExternalPluginSlots[0].presetStateBase64 != nil, "Master project state lost")
                engine.attach(project:restored)
                try check(abs(engine.masterVolume - 0.6) < 0.0001 && restored.masterExternalPluginSlots[0].bypassed, "Master gain/bypass lost on reopen")
                report["master_fader_and_bypass_persistence"] = true
                restored.masterExternalPluginSlots[0].bypassed = false
                engine.rebuild()
                try check(engine.liveNativePlugin(for:restored.masterExternalPluginSlots[0]) != nil || engine.liveExternalAU(for:restored.masterExternalPluginSlots[0]) != nil,"Saved master insert did not reload")
                report["master_plugin_format"] = format.rawValue
                report["master_plugin_render_editor_and_restore"] = true
                // A master effect must not reintroduce the offline metronome.
                restored.tracks = []; engine.attach(project:restored); engine.metronomeEnabled = true
                let silence = try offline.renderStereo(project:restored)
                try check(silence.peak < 0.00001,"Master graph exported the click")
                report["metronome_excluded"] = true
                DispatchQueue.main.asyncAfter(deadline:.now()+0.5) { finish() }
            } catch { finish(error) }
        }
    }
}
