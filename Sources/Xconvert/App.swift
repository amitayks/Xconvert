import SwiftUI

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

struct XconvertApp: App {
    @StateObject private var converter = Converter()

    var body: some Scene {
        WindowGroup("Xconvert") {
            ContentView()
                .environmentObject(converter)
                .frame(width: 460, height: 360)
                .preferredColorScheme(.dark)
        }
        .windowResizability(.contentSize)
    }
}
