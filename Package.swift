// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "DayNight",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "DayNight", targets: ["DayNight"]),
        .executable(name: "daynight-hardware-check", targets: ["DayNightHardwareCheck"]),
        .library(name: "DayNightCore", targets: ["DayNightCore"]),
    ],
    targets: [
        .target(name: "DayNightPrivateAPI", publicHeadersPath: "include"),
        .target(name: "DayNightCore", dependencies: ["DayNightPrivateAPI"]),
        .executableTarget(name: "DayNight", dependencies: ["DayNightCore"]),
        .executableTarget(name: "DayNightHardwareCheck", dependencies: ["DayNightCore"]),
        .testTarget(name: "DayNightTests", dependencies: ["DayNight", "DayNightCore"]),
    ],
    swiftLanguageModes: [.v6]
)
