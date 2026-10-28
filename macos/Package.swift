// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Halo",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "Halo", targets: ["Halo"]),
    ],
    targets: [
        // Pure, UI-free logic: model, geometry, interaction state machine, catalog, storage.
        .target(
            name: "HaloCore",
            path: "Sources/HaloCore"
        ),
        // C shims for deprecated system calls Swift can't reach.
        .target(
            name: "HaloShims",
            path: "Sources/HaloShims"
        ),
        // The menu-bar app: trigger, overlay, action runners, configurator.
        .executableTarget(
            name: "Halo",
            dependencies: ["HaloCore", "HaloShims"],
            path: "Sources/Halo",
            swiftSettings: [
                .defaultIsolation(MainActor.self),
            ]
        ),
        .testTarget(
            name: "HaloCoreTests",
            dependencies: ["HaloCore"],
            path: "Tests/HaloCoreTests"
        ),
    ]
)
