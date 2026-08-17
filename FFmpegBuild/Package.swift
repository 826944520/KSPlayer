// swift-tools-version:5.9
import PackageDescription

// Minimal self-contained package whose only purpose is to host the BuildFFmpeg
// command plugin. `swift package --disable-sandbox BuildFFmpeg platforms=ios,isimulator ...`
// rebuilds FFmpeg 9.0 + its dependencies into xcframeworks under Sources/, which
// the rebuild-ffmpeg workflow then stages into the main package's Sources/.
//
// tools-version stays 5.9 because the rebuild runs on a macos-14 (Xcode 15.4 /
// Swift 5.10) runner, which cannot parse tools-version 6.x manifests.
let package = Package(
    name: "FFmpegBuild",
    platforms: [.macOS(.v10_15)],
    products: [
        .plugin(name: "BuildFFmpeg", targets: ["BuildFFmpeg"]),
    ],
    targets: [
        .plugin(
            // No explicit `path:` — a plugin target resolves by default to
            // `Plugins/<name>` (tools-5.9, matching the upstream fork's declaration;
            // passing `path:` here breaks manifest parsing with "argument 'capability'
            // must precede argument 'path'").
            name: "BuildFFmpeg",
            capability: .command(
                intent: .custom(
                    verb: "BuildFFmpeg",
                    description: "Rebuild FFmpeg 9.0 xcframeworks for iOS (device + simulator)"
                ),
                // No declared permissions: the workflow invokes the plugin with
                // `--disable-sandbox`, which lifts all write restrictions. Declaring
                // `.writeToPackageDirectory` here instead makes SwiftPM demand an
                // explicit `--allow-writing-to-package-directory`, which would fail
                // (matching the upstream fork, which keeps this list empty).
                permissions: []
            )
        )
    ]
)
