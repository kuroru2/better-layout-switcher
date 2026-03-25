// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FnSwitch",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "FnSwitch",
            path: "Sources/FnSwitch",
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("Cocoa")
            ]
        )
    ]
)
