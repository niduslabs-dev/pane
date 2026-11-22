// swift-tools-version:6.2
import PackageDescription

/// Pane: mirrors a running Android emulator in a native Mac window, inside a device frame we draw,
/// and forwards clicks and frame-button presses back to it over the emulator's own gRPC interface.
///
/// - `PaneCore`: no UI. Discovery of running emulators, the gRPC client (generated code committed
///   in `Generated/`), coordinate mapping and frame geometry.
/// - `Pane` (product `Pane`): the AppKit + SwiftUI app, assembled into `build/Pane.app` by
///   `scripts/build-app.sh`.
/// - `PaneEmulatorHelper` (product `PaneEmulator`): the background-only "Pane Emulator" app in
///   `Pane.app/Contents/Helpers`, which execs the emulators Pane starts and, as the takeover's
///   launch agent, repairs the wrapper after emulator updates.
/// - `PaneTakeover`: the takeover's wrapper script, repair routine and launch agent plist
///   (Foundation only), shared by PaneCore and the helper.
///
/// Updates come through Sparkle with Pane's own surfaces (`Sources/Pane/Updates`).
///
/// Direct dependencies are pinned exactly; `Package.resolved` (committed) pins the rest.
let package = Package(
    name: "Pane",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "PaneCore", targets: ["PaneCore"]),
        .executable(name: "Pane", targets: ["Pane"]),
        // "Pane Emulator", bundled inside Pane.app: the emulator runs as this app, outside Pane's
        // process coalition (`EmulatorLauncher.launch`).
        .executable(name: "PaneEmulator", targets: ["PaneEmulatorHelper"]),
    ],
    dependencies: [
        .package(url: "https://github.com/grpc/grpc-swift-2.git", exact: "2.4.4"),
        // 2.12.0, not 2.13.0: 2.13.0 shipped on 2026-11-16, the day this was pinned.
        .package(url: "https://github.com/grpc/grpc-swift-nio-transport.git", exact: "2.12.0"),
        .package(url: "https://github.com/grpc/grpc-swift-protobuf.git", exact: "2.5.0"),
        // 1.39.0: 1.40.0 and 1.41.0 were under two weeks old when pinned.
        .package(url: "https://github.com/apple/swift-protobuf.git", exact: "1.39.0"),
        // Updates (Developer ID builds from GitHub Releases), with Pane's own surfaces. The same
        // version Drop ships (pinned there 2026-11-17): a new Sparkle is a deliberate change,
        // checked against its changelog and `UpdateDriver`.
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1"),
    ],
    targets: [
        // The takeover's wrapper, repair and launch agent, with no dependencies, so the helper
        // can run a repair without linking PaneCore.
        .target(name: "PaneTakeover"),
        .target(
            name: "PaneCore",
            dependencies: [
                "PaneTakeover",
                .product(name: "GRPCCore", package: "grpc-swift-2"),
                .product(name: "GRPCNIOTransportHTTP2Posix", package: "grpc-swift-nio-transport"),
                .product(name: "GRPCProtobuf", package: "grpc-swift-protobuf"),
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
            ]
        ),
        .executableTarget(
            name: "Pane",
            dependencies: ["PaneCore", "PaneTakeover", .product(name: "Sparkle", package: "Sparkle")],
            linkerSettings: [.linkedFramework("AppKit"), .linkedFramework("SwiftUI")]
        ),
        // Redirects its output and execs the emulator; `--repair` runs the takeover repair.
        .executableTarget(name: "PaneEmulatorHelper", dependencies: ["PaneTakeover"]),
        .testTarget(
            name: "PaneCoreTests",
            dependencies: [
                "PaneCore",
                "PaneTakeover",
                // A fake emulator on loopback, for the stream tests.
                .product(name: "GRPCCore", package: "grpc-swift-2"),
                .product(name: "GRPCNIOTransportHTTP2Posix", package: "grpc-swift-nio-transport"),
                .product(name: "GRPCProtobuf", package: "grpc-swift-protobuf"),
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
            ],
            resources: [.copy("Fixtures")]
        ),
        // The app's theme-driven layout, tested through `@testable import` of the executable target.
        .testTarget(name: "PaneTests", dependencies: ["Pane", "PaneCore", "PaneTakeover"]),
    ]
)
