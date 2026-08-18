#if canImport(UIKit)
import UIKit

/// Non-interactive overlay drawn on top of `KSSlider` (touches pass through).
/// Shows the buffered-ahead range as a lighter fill over the unplayed track and
/// chapter markers as ticks, aligned to the slider's track geometry via
/// `trackRect(forBounds:)`. Only the region ahead of the thumb is drawn, so the
/// slider's own played track (theme color) stays untouched.
final class ProgressOverlayView: UIView {
    weak var slider: KSSlider?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        contentMode = .redraw
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ rect: CGRect) {
        guard let slider, !slider.isHidden, slider.maximumValue > 0 else { return }
        let track = slider.trackRect(forBounds: slider.bounds)
        let total = Double(slider.maximumValue)
        guard total > 0 else { return }

        // Buffered-ahead fill from the playhead to bufferedTime. Reads the
        // slider's own value as the playhead so it follows the thumb during
        // scrubbing without extra wiring.
        let currentTime = Double(slider.value)
        if slider.bufferedTime > currentTime {
            let from = min(max(currentTime, 0), total)
            let to = min(slider.bufferedTime, total)
            guard to > from else { return }
            let startX = track.minX + CGFloat(from / total) * track.width
            let width = CGFloat((to - from) / total) * track.width
            let fillPath = UIBezierPath(roundedRect: CGRect(x: startX, y: track.minY, width: width, height: track.height), cornerRadius: track.height / 2)
            UIColor.white.withAlphaComponent(0.3).setFill()
            fillPath.fill()
        }

        // Chapter ticks.
        for chapter in slider.chapters where chapter.start > 0 && chapter.start < total {
            let x = track.minX + CGFloat(chapter.start / total) * track.width
            let tickRect = CGRect(x: x - 0.75, y: track.minY - 2, width: 1.5, height: track.height + 4)
            UIColor.white.withAlphaComponent(0.6).setFill()
            UIBezierPath(rect: tickRect).fill()
        }
    }
}
#endif
