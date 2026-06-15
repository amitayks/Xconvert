import SwiftUI
import AppKit

// Entry point. Supports a hidden headless mode for testing/automation:
//   Xconvert --convert <path-to-video>
// Otherwise launches the SwiftUI app.
@main
struct XconvertEntry {
    static func main() {
        let args = CommandLine.arguments
        if let idx = args.firstIndex(of: "--convert"), idx + 1 < args.count {
            CLI.run(path: args[idx + 1])
            return
        }
        XconvertApp.main()
    }
}

// Xconvert is a single-window utility, so closing the window should quit the
// app rather than leave it resident in the Dock/menu bar (the macOS default).
// On quit we also tear down any in-flight conversion: macOS reparents a child
// process to launchd instead of killing it, so the bundled ffmpeg would
// otherwise be orphaned.
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var converter: Converter?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        converter?.terminateNow()
    }
}

struct XconvertApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var converter = Converter()

    var body: some Scene {
        WindowGroup("Xconvert") {
            ContentView()
                .environmentObject(converter)
                .frame(width: 460, height: 360)
                .preferredColorScheme(.dark)
                .onAppear { appDelegate.converter = converter }
        }
        .windowResizability(.contentSize)
    }
}
