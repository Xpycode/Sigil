import Foundation
import AppKit
import CoreGraphics

/// Loads a source image and returns a 1024×1024 `NSImage` ready to be
/// rasterized at smaller sizes by `IconsetWriter`. Applies Fit (transparent
/// letterbox) or Fill (center-crop) depending on the selected `FitMode`.
enum ImageNormalizer {

    static let canonicalSize: CGFloat = 1024

    enum Error: LocalizedError {
        case unreadable(URL)
        case invalidDimensions(NSSize)
        case contextAllocationFailed

        var errorDescription: String? {
            switch self {
            case .unreadable(let url):
                return "Could not decode image at \(url.lastPathComponent)."
            case .invalidDimensions(let size):
                return "Source image has invalid dimensions (\(Int(size.width))×\(Int(size.height)))."
            case .contextAllocationFailed:
                return "Could not allocate sRGB drawing context."
            }
        }
    }

    /// Load the source image and draw it into a square 1024-pt canvas.
    ///
    /// **Color-profile note:** `NSImage(size:flipped:drawingHandler:)` builds
    /// a context with an unspecified color space, and on wide-gamut Macs
    /// (Display P3 default since the M-series) the implicit destination ends
    /// up P3-tagged. Drawing an sRGB source into a P3 destination shifts
    /// neutral metallics warm (silver → gold). Build the context explicitly
    /// against `CGColorSpace.sRGB` so the icon round-trips its colours
    /// correctly through `IconsetWriter` → PNG → `iconutil` → Finder.
    static func normalize(source: URL, mode: FitMode, zoom: Double = 1.0) throws -> NSImage {
        guard let nsSource = NSImage(contentsOf: source) else {
            throw Error.unreadable(source)
        }
        let sourceSize = nsSource.size
        guard sourceSize.width > 0, sourceSize.height > 0 else {
            throw Error.invalidDimensions(sourceSize)
        }

        let canvas = NSSize(width: canonicalSize, height: canonicalSize)
        let drawRect = computeDrawRect(sourceSize: sourceSize, canvasSize: canvas, mode: mode, zoom: zoom)

        guard
            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
            let cgContext = CGContext(
                data: nil,
                width: Int(canvas.width),
                height: Int(canvas.height),
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else {
            throw Error.contextAllocationFailed
        }

        let nsContext = NSGraphicsContext(cgContext: cgContext, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsContext
        nsContext.imageInterpolation = .high
        nsSource.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1.0)
        NSGraphicsContext.restoreGraphicsState()

        guard let cgImage = cgContext.makeImage() else {
            throw Error.contextAllocationFailed
        }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        let image = NSImage(size: canvas)
        image.addRepresentation(rep)
        return image
    }

    /// Compute the destination rect inside the square canvas for the chosen mode,
    /// then scale it around the canvas center by `zoom` (1.0 = base framing).
    /// - Fit: scale so the longer edge matches the canvas; padding is transparent.
    /// - Fill: scale so the shorter edge matches the canvas; excess is cropped by the canvas bounds.
    /// - Zoom >1 enlarges the rect (crops further); <1 shrinks it (more letterbox).
    static func computeDrawRect(
        sourceSize: NSSize,
        canvasSize: NSSize,
        mode: FitMode,
        zoom: Double = 1.0
    ) -> NSRect {
        let baseScale: CGFloat = switch mode {
        case .fit:
            min(canvasSize.width / sourceSize.width, canvasSize.height / sourceSize.height)
        case .fill:
            max(canvasSize.width / sourceSize.width, canvasSize.height / sourceSize.height)
        }
        let scale = baseScale * CGFloat(zoom)
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
