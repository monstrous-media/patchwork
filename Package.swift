// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Patchwork",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "PatchworkCore", targets: ["PatchworkCore"]),
        .library(name: "PatchworkMIDI", targets: ["PatchworkMIDI"]),
        .executable(name: "patchwork", targets: ["patchwork"]),
        .executable(name: "PatchworkApp", targets: ["PatchworkApp"]),
    ],
    targets: [
        // Pure Swift, no Apple-only imports: the SynthDefinition protocol, generic codec/model/generator
        // code, and the Korg M1 definition. Tests run on macOS and Linux.
        .target(name: "PatchworkCore", path: "Sources/PatchworkCore"),
        // CoreMIDI wrapper (macOS); compiles to a stub elsewhere.
        .target(name: "PatchworkMIDI", dependencies: ["PatchworkCore"], path: "Sources/PatchworkMIDI"),
        // Command-line tool.
        .executableTarget(name: "patchwork", dependencies: ["PatchworkCore", "PatchworkMIDI"], path: "Sources/patchwork"),
        // SwiftUI editor app.
        .executableTarget(name: "PatchworkApp", dependencies: ["PatchworkCore", "PatchworkMIDI"], path: "Sources/PatchworkApp",
                          resources: [.copy("Resources")]),
        .testTarget(
            name: "PatchworkCoreTests",
            dependencies: ["PatchworkCore"],
            path: "Tests/PatchworkCoreTests",
            resources: [.copy("Vectors")]
        ),
    ]
)
