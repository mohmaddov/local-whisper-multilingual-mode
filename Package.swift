// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LocalWhisper",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "LocalWhisper", targets: ["LocalWhisper"])
    ],
    dependencies: [
        // Argmax Open-Source SDK (WhisperKit v1.0.0+)
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift", from: "1.0.0"),
        // MLX Swift LM for local LLM tag extraction
        .package(url: "https://github.com/ml-explore/mlx-swift-lm.git", exact: "3.31.3"),
        // MLX v3 integration packages (required for downloader/tokenizer)
        .package(url: "https://github.com/DePasqualeOrg/swift-tokenizers-mlx.git", from: "0.2.0"),
        .package(url: "https://github.com/DePasqualeOrg/swift-hf-api-mlx.git", from: "0.2.0"),
    ],
    targets: [
        .executableTarget(
            name: "LocalWhisper",
            dependencies: [
                .product(name: "WhisperKit", package: "argmax-oss-swift"),
                // MLX LLM for tag extraction
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                // MLX v3 integration: downloader + tokenizer adapters
                .product(name: "MLXLMTokenizers", package: "swift-tokenizers-mlx"),
                .product(name: "MLXLMHFAPI", package: "swift-hf-api-mlx"),
            ],
            path: "LocalWhisper",
            exclude: ["LocalWhisper.entitlements"],
            resources: [
                .copy("Resources/AppIcon.icns")
            ],
            swiftSettings: [
                // Disable strict concurrency for compatibility
                .unsafeFlags(["-Xfrontend", "-strict-concurrency=minimal"]),
                // Release-only optimizations: whole-module + LTO (size+speed)
                .unsafeFlags(["-O", "-whole-module-optimization"], .when(configuration: .release)),
            ],
            linkerSettings: [
                // Link-time optimization for smaller, faster release binaries
                .unsafeFlags(["-Xlinker", "-dead_strip"], .when(configuration: .release)),
            ]
        )
    ]
)
