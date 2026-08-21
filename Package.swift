// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "KSPlayer",
    defaultLocalization: "en",
    // .macOS(.v10_15) matches FFmpegKit's minimum macOS. SwiftPM validates product
    // dependencies against the platform it plans for (here the macOS host, since
    // CI builds with `swift build --sdk iphonesimulator` without --triple); an
    // undeclared macOS platform defaults to 10.13 < FFmpegKit's 10.15 and fails
    // the deployment-target check even though KSPlayer itself is iOS-only.
    platforms: [.iOS(.v26), .macOS(.v10_15)],
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

// Fork of kingslay/FFmpegKit at tag 6.1.4 with a patched avpriv_tempfile
// (TMPDIR-aware + iOS fallback) so the `cache:` protocol works inside the iOS
// sandbox. Rebuilt via .github/workflows/rebuild-ffmpeg.yml on the fork.
package.dependencies += [
    .package(url: "https://github.com/826944520/FFmpegKit.git", branch: "ksplayer-tmpdir-fix"),
]
