// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "DayNight",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "DayNight", targets: ["DayNight"]),
        .executable(name: "daynight-hardware-check", targets: ["DayNightHardwareCheck"])
    ],
    targets: [
        .target(
            name: "DayNightPrivateAPI",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedFramework("Foundation")
            ]
        ),
        .target(
            name: "DayNightCore",
            dependencies: ["DayNightPrivateAPI"],
            linkerSettings: [
                .linkedFramework("ApplicationServices")
            ]
        ),
        .executableTarget(
            name: "DayNight",
            dependencies: ["DayNightCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("SwiftUI")
            ]
        ),
        .executableTarget(
            name: "DayNightHardwareCheck",
            dependencies: ["DayNightCore"]
        ),
        .testTarget(
            name: "DayNightCoreTests",
            dependencies: ["DayNightCore"]
        )
    ],
    swiftLanguageModes: [.v5]
)
