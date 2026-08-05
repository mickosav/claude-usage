import AppKit

enum StatusItemRenderer {
    static let barWidth: CGFloat = 44
    static let barHeight: CGFloat = 5
    static let gap: CGFloat = 2
    static let radius: CGFloat = 1.5
    static let minNub: CGFloat = 2
    static let imageHeight: CGFloat = barHeight * 2 + gap

    /// Two stacked progress bars: top = session, bottom = weekly all-models.
    /// Drawn via a handler so it re-renders crisply at the display's scale, and
    /// flagged as a template so the menu bar tints it black/white. `muted` dims
    /// the whole glyph to signal the numbers are stale / offline.
    static func image(session: UsageLimit, weekly: UsageLimit, muted: Bool = false) -> NSImage {
        let alpha: CGFloat = muted ? 0.5 : 1
        let img = NSImage(size: NSSize(width: barWidth, height: imageHeight), flipped: false) { _ in
            drawBar(rect: NSRect(x: 0, y: barHeight + gap, width: barWidth, height: barHeight),
                    percent: session.percent, alpha: alpha)
            drawBar(rect: NSRect(x: 0, y: 0, width: barWidth, height: barHeight),
                    percent: weekly.percent, alpha: alpha)
            return true
        }
        img.isTemplate = true
        return img
    }

    /// Placeholder shown when there's no key / no data yet.
    static func placeholderImage() -> NSImage {
        let img = NSImage(size: NSSize(width: barWidth, height: imageHeight), flipped: false) { _ in
            drawTrack(NSRect(x: 0, y: barHeight + gap, width: barWidth, height: barHeight))
            drawTrack(NSRect(x: 0, y: 0, width: barWidth, height: barHeight))
            return true
        }
        img.isTemplate = true
        return img
    }

    private static func drawBar(rect: NSRect, percent: Double, alpha: CGFloat) {
        drawTrack(rect, alpha: alpha)
        let clamped = max(0, min(100, percent)) / 100.0
        guard percent > 0 else { return }
        let fillWidth = max(rect.width * clamped, minNub)   // keep a visible nub at low %
        let fillRect = NSRect(x: rect.minX, y: rect.minY, width: fillWidth, height: rect.height)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: fillRect, xRadius: radius, yRadius: radius).addClip()
        NSColor.black.withAlphaComponent(alpha).setFill()   // alpha only; template tinting picks color
        fillRect.fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func drawTrack(_ rect: NSRect, alpha: CGFloat = 1) {
        NSColor.black.withAlphaComponent(0.35 * alpha).setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
    }
}
