// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "RNNoiseKit",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
        .watchOS(.v9),
        .visionOS(.v1),
    ],
    products: [
        .library(name: "RNNoiseKit", targets: ["RNNoiseKit"]),
    ],
    targets: [
        // Vendored xiph/rnnoise C sources. Re-vendor with
        // scripts/update.sh; do not edit by hand.
        .target(
            name: "CRNNoise",
            cSettings: [
                // Weights come from the bundled blob, not from
                // the 78 MB generated C arrays.
                .define("USE_WEIGHTS_FILE"),
                .define("RNNOISE_BUILD"),
            ]
        ),
        .target(
            name: "RNNoiseKit",
            dependencies: ["CRNNoise"],
            resources: [.copy("Resources/rnnoise_weights.bin")]
        ),
        .testTarget(
            name: "RNNoiseKitTests",
            dependencies: ["RNNoiseKit"]
        ),
    ]
)
