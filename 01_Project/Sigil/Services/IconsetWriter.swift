import Foundation
import AppKit

/// Writes the 10 PNG files `iconutil -c icns` requires into a `.iconset`
/// directory. Filenames follow Apple's convention:
///
///     icon_16x16.png         (16 pt @1x =  16 px)
///     icon_16x16@2x.png      (16 pt @2x =  32 px)
///     icon_32x32.png         (32 pt @1x =  32 px)
///     icon_32x32@2x.png      (32 pt @2x =  64 px)
///     icon_128x128.png       (128 pt @1x = 128 px)
///     icon_128x128@2x.png    (128 pt @2x = 256 px)
///     icon_256x256.png       (256 pt @1x = 256 px)
///     icon_256x256@2x.png    (256 pt @2x = 512 px)
///     icon_512x512.png       (512 pt @1x = 512 px)
///     icon_512x512@2x.png    (512 pt @2x = 1024 px)
enum IconsetWriter {

    struct Spec: Sendable {
        let filename: String
        let pixelSize: Int
    }

    static let specs: [Spec] = [
        Spec(filename: "icon_16x16.png",      pixelSize: 16),
        Spec(filename: "icon_16x16@2x.png",   pixelSize: 32),
        Spec(filename: "icon_32x32.png",      pixelSize: 32),
        Spec(filename: "icon_32x32@2x.png",   pixelSize: 64),
        Spec(filename: "icon_128x128.png",    pixelSize: 128),
        Spec(filename: "icon_128x128@2x.png", pixelSize: 256),
        Spec(filename: "icon_256x256.png",    pixelSize: 256),
        Spec(filename: "icon_256x256@2x.png", pixelSize: 512),
        Spec(filename: "icon_512x512.png",    pixelSize: 512),
        Spec(filename: "icon_512x512@2x.png", pixelSize: 1024),
    ]

    enum Error: LocalizedError {
        case bitmapAllocationFailed(pixelSize: Int)
        case pngEncodingFailed(pixelSize: Int)

        var errorDescription: String? {
            switch self {
            case .bitmapAllocationFailed(let size):
                return "Could not allocate \(size)×\(size) bitmap."
            case .pngEncodingFailed(let size):
                return "Could not encode \(size)×\(size) PNG."
            }
        }
    }

    /// Write the 10-file iconset. `iconsetDir` must exist and be empty (or writable).
    static func write(from image: NSImage, to iconsetDir: URL) throws {
        for spec in specs {
            let data = try renderPNG(image: image, pixelSize: spec.pixelSize)
            try data.write(to: iconsetDir.appendingPathComponent(spec.filename))
        }
    }

    /// Render `image` into a `pixelSize × pixelSize` PNG using `NSBitmapImageRep`
    /// with high-quality interpolation.
    static func renderPNG(image: NSImage, pixelSize: Int) throws -> Data {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelSize,
            pixelsHigh: pixelSize,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: [],
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw Error.bitmapAllocationFailed(pixelSize: pixelSize)
        }
        rep.size = NSSize(width: pixelSize, height: pixelSize)

        NSGraphicsContext.saveGraphicsState()
        if let ctx = NSGraphicsContext(bitmapImageRep: rep) {
            NSGraphicsContext.current = ctx
            ctx.imageInterpolation = .high
            image.draw(
                in: NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize),
                from: .zero,
                operation: .sourceOver,
                fraction: 1.0
            )
        }
        NSGraphicsContext.restoreGraphicsState()

        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw Error.pngEncodingFailed(pixelSize: pixelSize)
        }
        return data
    }
}
