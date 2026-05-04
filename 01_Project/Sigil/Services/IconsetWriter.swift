import Foundation
import AppKit
import CoreGraphics

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
        case contextAllocationFailed(pixelSize: Int)

        var errorDescription: String? {
            switch self {
            case .bitmapAllocationFailed(let size):
                return "Could not allocate \(size)×\(size) bitmap."
            case .pngEncodingFailed(let size):
                return "Could not encode \(size)×\(size) PNG."
            case .contextAllocationFailed(let size):
                return "Could not allocate \(size)×\(size) sRGB context."
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

    /// Render `image` into a `pixelSize × pixelSize` PNG.
    ///
    /// Uses an explicit-sRGB `CGContext` instead of an `NSBitmapImageRep`
    /// allocated with `colorSpaceName: .deviceRGB`. `.deviceRGB` is
    /// device-dependent — on a wide-gamut Mac (Display P3 default since the
    /// M-series) it produces a P3-tagged bitmap, which Finder later renders
    /// as visibly warm/over-saturated (silver metallics shift to gold).
    /// Targeting `CGColorSpace.sRGB` makes the PNG's profile match what
    /// `iconutil` and Finder expect, eliminating the colour shift.
    static func renderPNG(image: NSImage, pixelSize: Int) throws -> Data {
        guard
            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
            let cgContext = CGContext(
                data: nil,
                width: pixelSize,
                height: pixelSize,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else {
            throw Error.contextAllocationFailed(pixelSize: pixelSize)
        }

        let nsContext = NSGraphicsContext(cgContext: cgContext, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsContext
        nsContext.imageInterpolation = .high
        image.draw(
            in: NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize),
            from: .zero,
            operation: .sourceOver,
            fraction: 1.0
        )
        NSGraphicsContext.restoreGraphicsState()

        guard let cgImage = cgContext.makeImage() else {
            throw Error.bitmapAllocationFailed(pixelSize: pixelSize)
        }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        rep.size = NSSize(width: pixelSize, height: pixelSize)

        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw Error.pngEncodingFailed(pixelSize: pixelSize)
        }
        return data
    }
}
