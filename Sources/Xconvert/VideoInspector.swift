import AVFoundation
import CoreMedia

/// Everything we need to read off the source to plan the transcode.
struct SourceInfo {
    let durationSeconds: Double
    let width: Int
    let height: Int
    let fps: Double
    let hasAudio: Bool
    let isHDR: Bool
}

enum InspectError: LocalizedError {
    case notAVideo

    var errorDescription: String? {
        switch self {
        case .notAVideo:
            return "That file isn't a video we can read. Drop a .mov, .mp4, .m4v, .mkv, .webm, or .avi."
        }
    }
}

/// Native inspection via AVFoundation — replaces ffprobe.
enum VideoInspector {
    static func inspect(url: URL) async throws -> SourceInfo {
        let asset = AVURLAsset(url: url)

        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = videoTracks.first else { throw InspectError.notAVideo }

        async let durationT = asset.load(.duration)
        async let naturalSizeT = track.load(.naturalSize)
        async let transformT = track.load(.preferredTransform)
        async let fpsT = track.load(.nominalFrameRate)
        async let formatsT = track.load(.formatDescriptions)
        async let audioTracksT = asset.loadTracks(withMediaType: .audio)

        let duration = try await durationT
        let naturalSize = try await naturalSizeT
        let transform = try await transformT
        let fps = try await fpsT
        let formats = try await formatsT
        let audioTracks = try await audioTracksT

        // Apply the preferred transform so rotated / portrait clips report their
        // true *display* dimensions, not the raw encoded size.
        let displaySize = naturalSize.applying(transform)
        let width = Int(abs(displaySize.width).rounded())
        let height = Int(abs(displaySize.height).rounded())

        let isHDR = formats.contains { fd in
            guard let tf = CMFormatDescriptionGetExtension(
                fd, extensionKey: kCMFormatDescriptionExtension_TransferFunction
            ) as? String else { return false }
            return tf == (kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG as String)
                || tf == (kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ as String)
        }

        let durSec = CMTimeGetSeconds(duration)
        return SourceInfo(
            durationSeconds: durSec.isFinite ? durSec : 0,
            width: max(width, 0),
            height: max(height, 0),
            fps: Double(fps),
            hasAudio: !audioTracks.isEmpty,
            isHDR: isHDR
        )
    }
}
