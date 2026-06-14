// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Xconvert",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Xconvert",
            path: "Sources/Xconvert"
        )
    ]
)
