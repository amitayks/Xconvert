import SwiftUI
import AppKit

/// Drives the whole lifecycle and publishes the current phase to the UI.
@MainActor
final class Converter: ObservableObject {
    enum Phase: Equatable {
        case idle
        case inspecting
        case converting(Double)   // 0...1
        case done(URL)
        case error(String)
    }

    @Published var phase: Phase = .idle
    @Published var isTargeted = false

    var isBusy: Bool {
        switch phase {
        case .inspecting, .converting: return true
        default: return false
        }
    }

    func handleDropped(_ urls: [URL]) {
        guard let first = urls.first else { return }
        convert(url: first)   // v1: convert the first, ignore the rest
    }

    func convert(url: URL) {
        guard !isBusy else { return }
        Task { await run(url: url) }
    }

    func reset() { phase = .idle }

    private func run(url: URL) async {
        phase = .inspecting

        guard let ffmpeg = FFmpegLocator.resolve() else {
            phase = .error("Couldn't find ffmpeg. This build isn't bundled with a converter and no system ffmpeg was found.")
            return
        }

        do {
            let info = try await VideoInspector.inspect(url: url)
            phase = .converting(0)
            let plan = FFmpegPlan.build(input: url, info: info, ffmpeg: ffmpeg)

            try await FFmpegRunner.run(plan: plan, duration: info.durationSeconds) { [weak self] fraction in
                Task { @MainActor in
                    guard let self else { return }
                    if case .converting = self.phase {
                        self.phase = .converting(fraction)
                    }
                }
            }

            NSWorkspace.shared.activateFileViewerSelecting([plan.outputURL])
            phase = .done(plan.outputURL)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            phase = .error(message)
        }
    }
}
