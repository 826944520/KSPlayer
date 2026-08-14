// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "KSPlayer",
    defaultLocalization: "en",
    platforms: [.macOS(.v10_15), .macCatalyst(.v14), .iOS(.v26), .tvOS(.v13),
                .visionOS(.v1)],
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
                // Depends on the FFmpegKit binaries only, not on KSPlayer, so the
                // version gate runs and fails cleanly even if KSPlayer itself does
                // not compile for the macOS host. The build-ios job covers KSPlayer
                // compile coverage.
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

package.dependencies += [
    .package(url: "https://github.com/826944520/FFmpegKit.git", branch: "main"),
]
