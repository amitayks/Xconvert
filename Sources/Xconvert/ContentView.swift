import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var converter: Converter
    @State private var showImporter = false

    private let background = Color(red: 0.07, green: 0.07, blue: 0.09)
    private let accent = Color(red: 0.11, green: 0.63, blue: 0.95)

    var body: some View {
        ZStack {
            background.ignoresSafeArea()
            content.padding(28)
        }
        .dropDestination(for: URL.self) { items, _ in
            converter.handleDropped(items)
            return true
        } isTargeted: { converter.isTargeted = $0 }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.movie, .video, .quickTimeMovie, .mpeg4Movie],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result { converter.handleDropped(urls) }
        }
        .animation(.easeInOut(duration: 0.2), value: converter.phase)
        .animation(.easeInOut(duration: 0.15), value: converter.isTargeted)
    }

    @ViewBuilder private var content: some View {
        switch converter.phase {
        case .idle:
            dropZone
        case .inspecting:
            status(icon: "magnifyingglass", title: "Inspecting…", showSpinner: true)
        case .converting(let fraction):
            converting(fraction)
        case .done(let url):
            done(url)
        case .error(let message):
            errorView(message)
        }
    }

    // MARK: Idle / drop zone

    private var dropZone: some View {
        VStack(spacing: 18) {
            Image(systemName: "arrow.down.doc.fill")
                .font(.system(size: 52, weight: .regular))
                .foregroundStyle(converter.isTargeted ? accent : .secondary)

            VStack(spacing: 6) {
                Text("Drop a video to convert for X")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                Text("Any format → X-ready MP4, saved next to the original")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button("Choose File…") { showImporter = true }
                .buttonStyle(.borderedProminent)
                .tint(accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    style: StrokeStyle(lineWidth: 2, dash: [8, 6])
                )
                .foregroundStyle(converter.isTargeted ? accent : Color.white.opacity(0.15))
        )
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(converter.isTargeted ? accent.opacity(0.08) : Color.white.opacity(0.02))
        )
    }

    // MARK: Status / converting / done / error

    private func status(icon: String, title: String, showSpinner: Bool) -> some View {
        VStack(spacing: 16) {
            if showSpinner {
                ProgressView().controlSize(.large)
            } else {
                Image(systemName: icon).font(.system(size: 44))
            }
            Text(title).font(.title3.weight(.semibold))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func converting(_ fraction: Double) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 44))
                .foregroundStyle(accent)
            Text("Converting…").font(.title3.weight(.semibold))
            ProgressView(value: fraction)
                .progressViewStyle(.linear)
                .tint(accent)
                .frame(maxWidth: 280)
            Text("\(Int(fraction * 100))%")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func done(_ url: URL) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(.green)
            Text("Ready for X").font(.title3.weight(.semibold))
            Text(url.lastPathComponent)
                .font(.callout.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 320)

            HStack(spacing: 12) {
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
                Button("Convert Another") { converter.reset() }
                    .buttonStyle(.borderedProminent)
                    .tint(accent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text("Couldn't convert").font(.title3.weight(.semibold))
            ScrollView {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .frame(maxHeight: 120)
            Button("Try Another") { converter.reset() }
                .buttonStyle(.borderedProminent)
                .tint(accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
