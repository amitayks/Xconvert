import Foundation

/// Hidden headless mode: `Xconvert --convert <path>`.
/// Reuses the exact same inspection + engine the GUI uses, so it's a faithful
/// end-to-end test of the conversion pipeline without driving the UI.
enum CLI {
    static func run(path: String) {
        let url = URL(fileURLWithPath: path)
        var exitCode: Int32 = 0
        let done = DispatchSemaphore(value: 0)

        Task.detached {
            func err(_ s: String) { FileHandle.standardError.write(Data((s + "\n").utf8)) }

            do {
                guard let ffmpeg = FFmpegLocator.resolve() else {
                    err("error: ffmpeg not found (no bundled binary and no system install)")
                    exitCode = 2
                    done.signal()
                    return
                }
                err("ffmpeg: \(ffmpeg.path)\(FFmpegLocator.isBundled(ffmpeg) ? " (bundled)" : " (system fallback)")")

                let info = try await VideoInspector.inspect(url: url)
                err("source: \(info.width)x\(info.height) @ \(Int(info.fps.rounded()))fps  "
                    + "audio=\(info.hasAudio ? "yes" : "no (will inject silent)")  "
                    + "hdr=\(info.isHDR ? "yes (tonemap)" : "no")  "
                    + "duration=\(String(format: "%.1f", info.durationSeconds))s")

                let plan = FFmpegPlan.build(input: url, info: info, ffmpeg: ffmpeg)

                var lastDecile = -1
                try await FFmpegRunner.run(plan: plan, duration: info.durationSeconds) { fraction in
                    let decile = Int(fraction * 10)
                    if decile != lastDecile {
                        lastDecile = decile
                        err("progress: \(decile * 10)%")
                    }
                }

                // stdout = the output path (machine-readable)
                FileHandle.standardOutput.write(Data((plan.outputURL.path + "\n").utf8))
                err("done.")
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                err("error: \(message)")
                exitCode = 1
            }
            done.signal()
        }

        done.wait()
        exit(exitCode)
    }
}
