// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "KSPlayer",
    defaultLocalization: "en",
    platforms: [.iOS(.v26)],
    products: [
        .library(
            name: "KSPlayer",
            targets: ["KSPlayer"]
        ),
    ],
    targets: [
        .target(
            name: "KSPlayer",
            dependencies: [
                .product(name: "FFmpegKit", package: "FFmpegKit"),
                "DisplayCriteria",
            ],
            resources: [.process("Metal/Shaders.metal")],
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        ),
        .target(
            name: "DisplayCriteria"
        ),
        .testTarget(
            name: "KSPlayerTests",
            dependencies: [
                // Links the FFmpegKit binaries only (not KSPlayer), so the runtime
                // version gate in FFmpegVersionTest can run standalone. CI does not
                // execute this test (FFmpeg is iOS-only, so there is no macOS host
                // slice to run `swift test` natively); CI instead enforces the
                // version via the header-level gate in .github/workflows/build.yml.
                // This target remains for local iOS-Simulator runs via xcodebuild.
                .product(name: "Libavcodec", package: "FFmpegKit"),
                .product(name: "Libavformat", package: "FFmpegKit"),
                .product(name: "Libavfilter", package: "FFmpegKit"),
                .product(name: "Libavutil", package: "FFmpegKit"),
            ],
            path: "Tests/KSPlayerTests",
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        ),
    ]
)

// kingslay/FFmpegKit is the upstream source of the prebuilt FFmpeg 6.1.4
// xcframeworks (avcodec/avformat 60, avfilter 9). The binaries live INSIDE the
// package's committed xcframeworks (ios-arm64 + ios-arm64_x86_64-simulator), so
// `swift package resolve` is fully offline once the checkout is available.
package.dependencies += [
    .package(url: "https://github.com/kingslay/FFmpegKit.git", from: "6.1.4"),
]
