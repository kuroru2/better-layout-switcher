// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FnSwitchLight",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "FnSwitchLight",
            path: "Sources/FnSwitchLight",
            exclude: ["Resources"],
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("Cocoa"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("AVKit"),
                .linkedFramework("CoreVideo"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("QuartzCore")
            ]
        )
    ]
)
