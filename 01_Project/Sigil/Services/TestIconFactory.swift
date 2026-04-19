import Foundation
import AppKit

/// Renders a simple labeled icon for the Wave 5 smoke test. Removed / replaced
/// by the real user-driven icon import in Wave 7.
enum TestIconFactory {

    /// Orange rounded-rect 1024×1024 with up-to-3-letter label centered.
    static func makeIcon(label: String) -> NSImage {
        let size = NSSize(width: 1024, height: 1024)
        let text = String(label.uppercased().prefix(3))

        return NSImage(size: size, flipped: false) { _ in
            // Background: rounded orange rect
            let bgRect = NSRect(origin: .zero, size: size)
            let bg = NSBezierPath(roundedRect: bgRect, xRadius: 180, yRadius: 180)
            NSColor(red: 0.9, green: 0.5, blue: 0.2, alpha: 1.0).setFill()
            bg.fill()

            // Subtle inner stroke
            NSColor.white.withAlphaComponent(0.2).setStroke()
            bg.lineWidth = 6
            bg.stroke()

            // Centered label
            let font = NSFont.systemFont(ofSize: 380, weight: .bold)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.white,
                .kern: 0.0
            ]
            let attributed = NSAttributedString(string: text, attributes: attrs)
            let textSize = attributed.size()
            let origin = NSPoint(
                x: (size.width - textSize.width) / 2,
                y: (size.height - textSize.height) / 2 - 20 // slight optical center
            )
            attributed.draw(at: origin)
            return true
        }
    }
}
