import Libavcodec
import Libavfilter
import Libavformat
import Libavutil
import XCTest

/// Runtime gate that proves the linked FFmpeg is really 8.x.
///
/// The FFmpegKit fork carries an `"n8.1"` version label, but that label only tells the
/// `BuildFFmpeg` plugin which branch to clone on the *next* rebuild — it does not reflect
/// the committed xcframework binaries. This test queries the binaries themselves via
/// `avcodec_version()` etc., so a "label says 8.1, binaries are still 6.1" mismatch fails
/// the gate loudly instead of passing silently.
///
/// FFmpeg major→lib-version mapping:
/// - 6.x: avcodec/avformat 60, avfilter 9
/// - 7.x: avcodec/avformat 61, avfilter 10
/// - 8.x: avcodec/avformat 62, avfilter 11   ← target
///
/// `AV_VERSION_INT(major,minor,micro) = (major<<16)|(minor<<8)|micro`, so major = `v >> 16`.
final class FFmpegVersionTest: XCTestCase {
    private func major(_ v: UInt32) -> UInt32 { v >> 16 }

    func testLinkedFFmpegIsVersion8() {
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

        let rebuildHint = "The FFmpegKit fork's committed xcframeworks are likely still 6.1. " +
            "Run on macOS: swift package --disable-sandbox BuildFFmpeg platforms=ios,isimulator enable-gmp enable-nettle enable-gnutls enable-FFmpeg, then re-commit the rebuilt xcframeworks."

        XCTAssertGreaterThanOrEqual(
            major(avcodec), 62,
            "FFmpeg avcodec major must be ≥62 (8.x); got \(major(avcodec)). \(rebuildHint)"
        )
        XCTAssertGreaterThanOrEqual(
            major(avformat), 62,
            "FFmpeg avformat major must be ≥62 (8.x); got \(major(avformat)). \(rebuildHint)"
        )
        XCTAssertGreaterThanOrEqual(
            major(avfilter), 11,
            "FFmpeg avfilter major must be ≥11 (8.x); got \(major(avfilter)). \(rebuildHint)"
        )
    }
}
