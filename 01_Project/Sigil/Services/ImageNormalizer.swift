import Foundation
import AppKit

/// Loads a source image and returns a 1024×1024 `NSImage` ready to be
/// rasterized at smaller sizes by `IconsetWriter`. Applies Fit (transparent
/// letterbox) or Fill (center-crop) depending on the selected `FitMode`.
enum ImageNormalizer {

    static let canonicalSize: CGFloat = 1024

    enum Error: LocalizedError {
        case unreadable(URL)
        case invalidDimensions(NSSize)

        var errorDescription: String? {
            switch self {
            case .unreadable(let url):
                return "Could not decode image at \(url.lastPathComponent)."
            case .invalidDimensions(let size):
                return "Source image has invalid dimensions (\(Int(size.width))×\(Int(size.height)))."
            }
        }
    }

    /// Load the source image and draw it into a square 1024-pt canvas.
    static func normalize(source: URL, mode: FitMode) throws -> NSImage {
        guard let source = NSImage(contentsOf: source) else {
            throw Error.unreadable(source)
        }
        let sourceSize = source.size
        guard sourceSize.width > 0, sourceSize.height > 0 else {
            throw Error.invalidDimensions(sourceSize)
        }

        let canvas = NSSize(width: canonicalSize, height: canonicalSize)
        let drawRect = computeDrawRect(sourceSize: sourceSize, canvasSize: canvas, mode: mode)

        let image = NSImage(size: canvas, flipped: false) { _ in
            source.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1.0)
            return true
        }
        return image
    }

    /// Compute the destination rect inside the square canvas for the chosen mode.
    /// - Fit: scale so the longer edge matches the canvas; padding is transparent.
    /// - Fill: scale so the shorter edge matches the canvas; excess is cropped by the canvas bounds.
    static func computeDrawRect(
        sourceSize: NSSize,
        canvasSize: NSSize,
        mode: FitMode
    ) -> NSRect {
        let scale: CGFloat = switch mode {
        case .fit:
            min(canvasSize.width / sourceSize.width, canvasSize.height / sourceSize.height)
        case .fill:
            max(canvasSize.width / sourceSize.width, canvasSize.height / sourceSize.height)
        }
        let w = sourceSize.width * scale
        let h = sourceSize.height * scale
        return NSRect(
            x: (canvasSize.width - w) / 2,
            y: (canvasSize.height - h) / 2,
            width: w,
            height: h
        )
    }
}
