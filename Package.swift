// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Switcher",
    platforms: [
        // ScreenCaptureKit window screenshots need macOS 14
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "Switcher",
            targets: ["Switcher"]
        )
    ],
    targets: [
        .executableTarget(
            name: "Switcher",
            path: "Sources/Switcher"
        )
    ]
)
