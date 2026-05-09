// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FnLightSwitch",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "FnLightSwitch",
            path: "Sources/FnLightSwitch",
            exclude: ["Resources"],
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("Cocoa"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("AVKit"),
                .linkedFramework("CoreVideo"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("QuartzCore"),
                .unsafeFlags([
                    "-F/System/Library/PrivateFrameworks",
                    "-framework", "DisplayServices"
                ])
            ]
        )
    ]
)
