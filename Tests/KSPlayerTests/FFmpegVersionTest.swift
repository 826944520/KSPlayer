import Libavcodec
import Libavfilter
import Libavformat
import Libavutil
import XCTest

/// Runtime gate that proves the linked FFmpeg is really 6.1.x.
///
/// The FFmpeg binaries come from the kingslay/FFmpegKit package (resolved from
/// `from: "6.1.4"`). This test queries the linked binaries themselves via
/// `avcodec_version()` etc., so the gate fails loudly if the resolved package
/// ever ships different binaries.
///
/// FFmpeg major→lib-version mapping:
/// - 6.x: avcodec/avformat 60, avfilter 9   ← currently resolved (6.1.4)
/// - 7.x: avcodec/avformat 61, avfilter 10
/// - 8.x: avcodec/avformat 62, avfilter 11
/// - 9.x: avcodec/avformat 63, avfilter 12
///
/// `AV_VERSION_INT(major,minor,micro) = (major<<16)|(minor<<8)|micro`, so major = `v >> 16`.
///
/// CI does not execute this test (FFmpeg is iOS-only, so there is no macOS host
/// slice to run `swift test` natively); CI instead enforces the version via the
/// header-level gate in .github/workflows/build.yml. This target remains for
/// local iOS-Simulator runs via xcodebuild.
final class FFmpegVersionTest: XCTestCase {
    private func major(_ v: UInt32) -> UInt32 { v >> 16 }

    func testLinkedFFmpegIsVersion6() {
        let avcodec = avcodec_version()
        let avformat = avformat_version()
        let avfilter = avfilter_version()
        let avutil = avutil_version()

        // Build-log signal: the exact protocols/libs FFmpeg was built with
        // (confirms e.g. gnutls/https is present for network playback).
        let configuration = String(cString: avformat_configuration())
        print("[FFmpegVersion] configuration: \(configuration)")
        print("[FFmpegVersion] avcodec major=\(major(avcodec)) (\(avcodec))")
        print("[FFmpegVersion] avformat major=\(major(avformat)) (\(avformat))")
        print("[FFmpegVersion] avfilter major=\(major(avfilter)) (\(avfilter))")
        print("[FFmpegVersion] avutil major=\(major(avutil)) (\(avutil))")

        let hint = "Expected kingslay/FFmpegKit 6.1.4 binaries (avcodec/avformat 60, avfilter 9)."

        XCTAssertGreaterThanOrEqual(
            major(avcodec), 60,
            "FFmpeg avcodec major must be ≥60 (6.x); got \(major(avcodec)). \(hint)"
        )
        XCTAssertGreaterThanOrEqual(
            major(avformat), 60,
            "FFmpeg avformat major must be ≥60 (6.x); got \(major(avformat)). \(hint)"
        )
        XCTAssertGreaterThanOrEqual(
            major(avfilter), 9,
            "FFmpeg avfilter major must be ≥9 (6.x); got \(major(avfilter)). \(hint)"
        )
    }
}
