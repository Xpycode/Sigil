# Color-Managed Icon Pipeline (sRGB CGContext)

**Use when:** rendering raster icons (volume icons, app artwork, exported PNGs)
from a user-supplied source image, where the output needs to look the same on
every Mac regardless of the developer's display profile. Use the explicit-sRGB
`CGContext` pattern instead of `NSImage(size:flipped:drawingHandler:)` and
`NSBitmapImageRep(... colorSpaceName: .deviceRGB ...)`.

**Source:** `1-macOS/Sigil/01_Project/Sigil/Services/ImageNormalizer.swift`,
`IconsetWriter.swift`. Triggered by a real silver-card-rendered-as-gold bug
report on a wide-gamut M-series Mac.

---

## Why this matters

Two AppKit conveniences silently break color management:

1. **`NSImage(size:flipped:drawingHandler:)`** creates a graphics context with
   an **unspecified** color space. Apple's own developer forums confirm this
   ([thread 728687](https://developer.apple.com/forums/thread/728687)): the
   block runs against whatever context AppKit feels like that day. On
   wide-gamut displays (Display P3 default since the M-series, every
   MacBook Pro 14"/16", every Studio Display), the destination ends up
   P3-tagged.

2. **`NSBitmapImageRep(... colorSpaceName: .deviceRGB ...)`** uses
   **device-dependent** RGB. On a wide-gamut Mac this resolves to a P3
   destination too.

The compounding pipeline:

```
sRGB-tagged source (PNG/JPEG)
    │
    ▼
NSImage(drawingHandler:) — implicit P3 context
    │
    ▼
NSBitmapImageRep(.deviceRGB) — explicit P3 destination
    │
    ▼
PNG tagged with the device profile
    │
    ▼
Embedded in .icns
    │
    ▼
Finder reads PNG, renders on a P3 display
    │
    ▼
Visible warm/saturated shift on neutral metallics
(silver chrome → gold cast — diagnostic for this bug class)
```

It's latent: the bug only shows on **wide-gamut Macs**, so a developer testing
on an older sRGB iMac would never see it. Sigil shipped v1.0.0 with this
issue undetected because the dev's screenshots happened to land on a profile
that round-tripped cleanly.

## The fix: explicit `CGContext` with `CGColorSpace.sRGB`

Build a `CGContext` directly against `CGColorSpace.sRGB`, wrap it in
`NSGraphicsContext` for AppKit drawing compatibility, draw, extract a
`CGImage`, wrap in `NSBitmapImageRep` for PNG encoding. No implicit color
space anywhere.

### Pattern A — normalize source image into a square canvas

```swift
import Foundation
import AppKit
import CoreGraphics

enum ImageNormalizer {
    enum Error: LocalizedError {
        case unreadable(URL)
        case invalidDimensions(NSSize)
        case contextAllocationFailed
        // ...
    }

    static func normalize(source: URL, canvasSize: NSSize, drawRect: NSRect) throws -> NSImage {
        guard let nsSource = NSImage(contentsOf: source) else {
            throw Error.unreadable(source)
        }
        let sourceSize = nsSource.size
        guard sourceSize.width > 0, sourceSize.height > 0 else {
            throw Error.invalidDimensions(sourceSize)
        }

        // Explicit sRGB context — NOT NSImage(size:flipped:drawingHandler:),
        // which loses the color space.
        guard
            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
            let cgContext = CGContext(
                data: nil,
                width: Int(canvasSize.width),
                height: Int(canvasSize.height),
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
        let image = NSImage(size: canvasSize)
        image.addRepresentation(rep)
        return image
    }
}
```

### Pattern B — encode an `NSImage` to a sized PNG

```swift
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
```

## Why sRGB and not Display P3 for icons

For Finder/Dock/`.icns` use specifically:

- Finder, Dock, and other system surfaces historically expect sRGB-equivalent
  color when rendering icons. They don't always honor wide-gamut profile tags
  embedded in icon PNGs.
- Most source images (screenshots, JPEGs from cameras, web PNGs) are sRGB.
- `.icns` as a format doesn't carry color-profile metadata in any reliable
  way — Finder treats embedded PNGs as sRGB-like at display time anyway.
- Display P3 in icons gives no perceptible benefit on small UI surfaces and
  risks looking off when the user moves the volume to a non-P3 display.

The trade-off accepted: wide-gamut sources (Display P3 PNGs from a photo
app) get clipped to sRGB gamut at normalize time. Saturated reds/greens
lose ~5% chroma. Acceptable for UI iconography; not acceptable for, say,
photo export pipelines (use Display P3 there).

## Diagnostic: the silver→gold tell

The pathognomonic visual sign of "rendered into a wider gamut than expected
and now displayed in that wider gamut" is a **warm cast on neutral
metallics**. Silver chrome shifts toward gold/champagne. White paper warms
toward cream. This is the exact pattern that surfaced the Sigil bug.

If you see warm shifts on neutral content in your icons / exports / thumbnails
on some Macs but not others, suspect this bug class first.

## Don'ts

- **Don't use `NSImage(size:flipped:drawingHandler:)` for color-managed
  rasterization.** Use only for transient previews where exact color
  doesn't matter.
- **Don't use `colorSpaceName: .deviceRGB`** for `NSBitmapImageRep` if the
  output will be displayed on a different machine than rendered. Use the
  CGContext pattern above and pass the bitmap's color space explicitly.
- **Don't try to "tag" an already-rendered bitmap** by setting
  `NSBitmapImageRep.colorSpace` after the fact — the pixels were drawn
  in the original context's space; retagging just relabels them and
  produces a different visual shift.

## Sources

- [Apple Developer Forums #728687 — How To Resize An Image and Retain Wide Color Gamut](https://developer.apple.com/forums/thread/728687)
- [Apple Developer Forums #679891 — How to create RGBA CGColorSpace / bitmap CGContext](https://developer.apple.com/forums/thread/679891)
- [Apple Developer Documentation — `CGColorSpace.sRGB`](https://developer.apple.com/documentation/coregraphics/cgcolorspace/1408955-srgb)

## Related

- `cookbook/29-disk-space-preflight.md` — the other "tested only on local
  APFS" gap that shipped with v1.0.0.
- `cookbook/31-finder-volume-icon-cache.md` — Finder's icon-services cache,
  the *next* problem in the icon-rendering chain (writes correctly, but
  Finder doesn't always re-read).
