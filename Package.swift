// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "GearShift",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "GearShiftCore"),
        .executableTarget(name: "GearShift", dependencies: ["GearShiftCore"]),
        // XCTest isn't available with Command Line Tools only, so tests are a plain executable.
        .executableTarget(
            name: "GearShiftCoreTests",
            dependencies: ["GearShiftCore"],
            path: "Tests/GearShiftCoreTests"
        ),
    ]
)
