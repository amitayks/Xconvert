import Foundation

/// Finds the ffmpeg binary: prefer the one bundled in the .app, fall back to a
/// system install (handy during `swift run` development).
enum FFmpegLocator {
    static func resolve() -> URL? {
        if let bundled = Bundle.main.url(forResource: "ffmpeg", withExtension: nil),
           FileManager.default.isExecutableFile(atPath: bundled.path) {
            return bundled
        }
        for path in ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/usr/bin/ffmpeg"]
        where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    /// True when the resolved binary is the one inside our app bundle.
    static func isBundled(_ url: URL) -> Bool {
        guard let bundled = Bundle.main.url(forResource: "ffmpeg", withExtension: nil) else { return false }
        return url.standardizedFileURL == bundled.standardizedFileURL
    }
}

/// Queries (and caches) which filters a given ffmpeg binary supports, so we can
/// degrade gracefully when a build lacks an optional filter (e.g. `zscale`,
/// which needs libzimg and is required by the HDR tonemap chain).
enum FFmpegCapabilities {
    private static let lock = NSLock()
    private static var cache: [String: Set<String>] = [:]

    static func supports(filter: String, ffmpeg: URL) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if let filters = cache[ffmpeg.path] {
            return filters.contains(filter)
        }
        let filters = queryFilters(ffmpeg)
        cache[ffmpeg.path] = filters
        return filters.contains(filter)
    }

    private static func queryFilters(_ ffmpeg: URL) -> Set<String> {
        let process = Process()
        process.executableURL = ffmpeg
        process.arguments = ["-hide_banner", "-filters"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        guard (try? process.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard let text = String(data: data, encoding: .utf8) else { return [] }

        var names = Set<String>()
        for line in text.split(separator: "\n") {
            // Each filter line looks like: " T.. name  in->out  description"
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            if parts.count >= 2 { names.insert(String(parts[1])) }
        }
        return names
    }
}

/// The exact ffmpeg invocation, derived from the source's inspected properties.
struct FFmpegPlan {
    let executable: URL
    let arguments: [String]
    let outputURL: URL

    /// - Parameter canTonemap: whether the chosen ffmpeg supports `zscale`
    ///   (libzimg). When an HDR source meets a build without it, we fall back to
    ///   a plain SDR conversion — still in-spec/postable, just not tonemapped.
    static func build(input: URL, info: SourceInfo, ffmpeg: URL, canTonemap: Bool) -> FFmpegPlan {
        let dir = input.deletingLastPathComponent()
        let base = input.deletingPathExtension().lastPathComponent
        let output = dir.appendingPathComponent("\(base)-x.mp4")

        // Cap the LONGEST edge to 1280 (handles landscape *and* portrait),
        // preserve aspect, keep dimensions even (required for yuv420p / H.264).
        let scale = "scale=w=1280:h=1280:force_original_aspect_ratio=decrease:force_divisible_by=2"

        let vf: String
        if info.isHDR && canTonemap {
            // Tonemap HDR (HLG/PQ) -> SDR BT.709 before yuv420p. Requires an
            // ffmpeg built with libzimg (zscale).
            vf = "fps=30,"
                + "zscale=t=linear:npl=100,format=gbrpf32le,zscale=p=bt709,"
                + "tonemap=tonemap=hable:desat=0,zscale=t=bt709:m=bt709:r=tv,"
                + "\(scale),format=yuv420p"
        } else {
            vf = "fps=30,\(scale),format=yuv420p"
        }

        var args = ["-y", "-i", input.path]

        // X requires an audio track: inject a silent one when the source has none.
        if !info.hasAudio {
            args += ["-f", "lavfi", "-i", "anullsrc=channel_layout=stereo:sample_rate=44100"]
        }

        args += ["-vf", vf]

        if info.hasAudio {
            args += ["-map", "0:v:0", "-map", "0:a:0"]
        } else {
            args += ["-map", "0:v:0", "-map", "1:a:0", "-shortest"]
        }

        args += [
            "-c:v", "libx264", "-profile:v", "high", "-preset", "veryfast",
            "-b:v", "5M", "-maxrate", "6M", "-bufsize", "8M",
            "-c:a", "aac", "-b:a", "128k",
            "-movflags", "+faststart",
            "-progress", "pipe:1", "-nostats",
            output.path,
        ]

        return FFmpegPlan(executable: ffmpeg, arguments: args, outputURL: output)
    }
}

enum FFmpegError: LocalizedError {
    case launchFailed(String)
    case nonZeroExit(Int32, String)

    var errorDescription: String? {
        switch self {
        case .launchFailed(let message):
            return "Couldn't start the converter: \(message)"
        case .nonZeroExit(let code, let tail):
            let detail = tail.isEmpty ? "" : "\n\n\(tail)"
            return "Conversion failed (ffmpeg exit \(code)).\(detail)"
        }
    }
}

/// Thread-safe collector for ffmpeg's stdout (progress) and stderr (error tail).
private final class ProcessOutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var stdoutBuffer = Data()
    private var stderrTail = Data()
    private let maxStderr = 8192
    private let duration: Double
    private let onProgress: (Double) -> Void

    init(duration: Double, onProgress: @escaping (Double) -> Void) {
        self.duration = duration
        self.onProgress = onProgress
    }

    func appendStdout(_ data: Data) {
        var fractions: [Double] = []
        lock.lock()
        stdoutBuffer.append(data)
        while let newline = stdoutBuffer.firstIndex(of: 0x0A) {
            let lineData = stdoutBuffer.subdata(in: stdoutBuffer.startIndex..<newline)
            stdoutBuffer.removeSubrange(stdoutBuffer.startIndex...newline)
            guard let line = String(data: lineData, encoding: .utf8),
                  line.hasPrefix("out_time_us=") else { continue }
            let raw = line.dropFirst("out_time_us=".count).trimmingCharacters(in: .whitespaces)
            if let micros = Double(raw), duration > 0 {
                fractions.append(min(max(micros / (duration * 1_000_000), 0), 1))
            }
        }
        lock.unlock()
        for fraction in fractions { onProgress(fraction) }
    }

    func appendStderr(_ data: Data) {
        lock.lock()
        stderrTail.append(data)
        if stderrTail.count > maxStderr {
            stderrTail = stderrTail.suffix(maxStderr)
        }
        lock.unlock()
    }

    func stderrString() -> String {
        lock.lock()
        defer { lock.unlock() }
        return String(data: stderrTail, encoding: .utf8) ?? ""
    }
}

enum FFmpegRunner {
    static func run(
        plan: FFmpegPlan,
        duration: Double,
        onProgress: @escaping (Double) -> Void
    ) async throws {
        let collector = ProcessOutputCollector(duration: duration, onProgress: onProgress)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            process.executableURL = plan.executable
            process.arguments = plan.arguments

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            outPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty { collector.appendStdout(data) }
            }
            errPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty { collector.appendStderr(data) }
            }

            process.terminationHandler = { proc in
                outPipe.fileHandleForReading.readabilityHandler = nil
                errPipe.fileHandleForReading.readabilityHandler = nil
                if proc.terminationStatus == 0 {
                    onProgress(1.0)
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(
                        throwing: FFmpegError.nonZeroExit(proc.terminationStatus, collector.stderrString())
                    )
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: FFmpegError.launchFailed(error.localizedDescription))
            }
        }
    }
}
