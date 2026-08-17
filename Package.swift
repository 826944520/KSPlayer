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
        // FFmpeg modules exposed for consumers that call the FFmpeg C API directly.
        .library(name: "FFmpegKit", targets: ["FFmpegKit"]),
        .library(name: "Libavcodec", targets: ["Libavcodec"]),
        .library(name: "Libavfilter", targets: ["Libavfilter"]),
        .library(name: "Libavformat", targets: ["Libavformat"]),
        .library(name: "Libavutil", targets: ["Libavutil"]),
        .library(name: "Libswresample", targets: ["Libswresample"]),
        .library(name: "Libswscale", targets: ["Libswscale"]),
    ],
    targets: [
        .target(
            name: "KSPlayer",
            dependencies: [
                "FFmpegKit",
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
        // Pure linker aggregator (Sources/FFmpegKit/FFmpegKit.c is empty). Its
        // dependency list below is the authoritative set of static libraries
        // linked into any target that imports FFmpegKit, and its linkerSettings
        // carry the system frameworks/libs those binaries depend on. Libavdevice
        // is deliberately absent — KSPlayer never imports it.
        .target(
            name: "FFmpegKit",
            dependencies: [
                "libdav1d",
                "libfreetype", "libfribidi", "libharfbuzz", "libass",
                "gmp", "nettle", "hogweed", "gnutls",
                "Libavcodec", "Libavfilter", "Libavformat", "Libavutil", "Libswresample", "Libswscale",
            ],
            linkerSettings: [
                .linkedFramework("AudioToolbox"),
                .linkedFramework("AVFAudio"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("CoreVideo"),
                .linkedFramework("CoreFoundation"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("Foundation"),
                .linkedFramework("Metal"),
                .linkedFramework("IOKit"),
                .linkedFramework("IOSurface"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("Security"),
                .linkedFramework("UIKit"),
                .linkedFramework("VideoToolbox"),
                .linkedLibrary("bz2"),
                .linkedLibrary("c++"),
                .linkedLibrary("iconv"),
                .linkedLibrary("resolv"),
                .linkedLibrary("xml2"),
                .linkedLibrary("z"),
            ]
        ),
        .testTarget(
            name: "KSPlayerTests",
            dependencies: [
                // Links the FFmpegKit binaries (aggregator) only, not KSPlayer, so
                // the runtime version gate in FFmpegVersionTest can run standalone.
                // CI does not execute this test (FFmpeg is iOS-only, so there is no
                // macOS host slice to run `swift test` natively); CI instead enforces
                // the version via the header-level gate in .github/workflows/build.yml.
                // This target remains for local iOS-Simulator runs via xcodebuild.
                "FFmpegKit",
            ],
            path: "Tests/KSPlayerTests",
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        ),
        // FFmpeg 9.0 ("Lei") prebuilt xcframeworks, ios-arm64 + ios-arm64_x86_64-simulator.
        // Vendored for a fully self-contained package: `swift build` is offline.
        // Rebuilt on CI via .github/workflows/rebuild-ffmpeg.yml (manual dispatch).
        .binaryTarget(
            name: "libdav1d",
            path: "Sources/libdav1d.xcframework"
        ),
        .binaryTarget(
            name: "Libavcodec",
            path: "Sources/Libavcodec.xcframework"
        ),
        .binaryTarget(
            name: "Libavfilter",
            path: "Sources/Libavfilter.xcframework"
        ),
        .binaryTarget(
            name: "Libavformat",
            path: "Sources/Libavformat.xcframework"
        ),
        .binaryTarget(
            name: "Libavutil",
            path: "Sources/Libavutil.xcframework"
        ),
        .binaryTarget(
            name: "Libswresample",
            path: "Sources/Libswresample.xcframework"
        ),
        .binaryTarget(
            name: "Libswscale",
            path: "Sources/Libswscale.xcframework"
        ),
        .binaryTarget(
            name: "libfreetype",
            path: "Sources/libfreetype.xcframework"
        ),
        .binaryTarget(
            name: "libfribidi",
            path: "Sources/libfribidi.xcframework"
        ),
        .binaryTarget(
            name: "libharfbuzz",
            path: "Sources/libharfbuzz.xcframework"
        ),
        .binaryTarget(
            name: "libass",
            path: "Sources/libass.xcframework"
        ),
        .binaryTarget(
            name: "gmp",
            path: "Sources/gmp.xcframework"
        ),
        .binaryTarget(
            name: "nettle",
            path: "Sources/nettle.xcframework"
        ),
        .binaryTarget(
            name: "hogweed",
            path: "Sources/hogweed.xcframework"
        ),
        .binaryTarget(
            name: "gnutls",
            path: "Sources/gnutls.xcframework"
        ),
    ]
)
