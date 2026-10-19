import AppKit

/// Menu bar glyph: the app icon's shape, drawn as a vector template image so
/// it follows the menu bar's light/dark appearance and stays sharp.
@MainActor
enum StatusIcon {
    // Built once: the icon is refreshed every access check (2 s).
    static let on = image(filled: true)
    static let off = image(filled: false)

    /// Same vertices as `scripts/make-icon.swift` (source-image pixels, y down).
    private static let shape: [CGPoint] = [
        CGPoint(x: 83, y: 227), CGPoint(x: 339, y: 127),
        CGPoint(x: 375, y: 161), CGPoint(x: 291, y: 423),
    ]

    /// Filled when smooth scrolling is on, outlined when it is paused.
    private static func image(filled: Bool) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: true) { rect in
            let minX = shape.map(\.x).min()!, maxX = shape.map(\.x).max()!
            let minY = shape.map(\.y).min()!, maxY = shape.map(\.y).max()!
            let inset: CGFloat = filled ? 1 : 1.75 // keep the stroke inside the bounds
            let box = rect.insetBy(dx: inset, dy: inset)
            let scale = min(box.width / (maxX - minX), box.height / (maxY - minY))
            let offset = CGPoint(
                x: box.midX - (minX + maxX) / 2 * scale,
                y: box.midY - (minY + maxY) / 2 * scale
            )

            let path = NSBezierPath()
            for (i, p) in shape.enumerated() {
                let point = NSPoint(x: offset.x + p.x * scale, y: offset.y + p.y * scale)
                if i == 0 { path.move(to: point) } else { path.line(to: point) }
            }
            path.close()
            path.lineJoinStyle = .round
            NSColor.black.set()
            if filled {
                path.fill()
            } else {
                path.lineWidth = 1.5
                path.stroke()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "SmoothScroll"
        return image
    }
}
