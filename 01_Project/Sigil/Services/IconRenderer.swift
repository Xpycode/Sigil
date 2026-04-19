import Foundation
import AppKit

/// Orchestrates the source-image → `.icns` pipeline.
///
/// - **Passthrough path:** if the source is already a `.icns` file, return its
///   bytes directly. Preserves any hand-crafted multi-resolution `.icns` the
///   user imported.
/// - **Render path:** ImageNormalizer → IconsetWriter → IconutilRunner.
///   Operates in a temp `.iconset/` directory that is removed on exit.
enum IconRenderer {

    /// Produce `.icns` data from the given source image.
    static func render(source: URL, mode: FitMode) async throws -> Data {
        // Passthrough: user dropped an existing .icns.
        if source.pathExtension.lowercased() == "icns" {
            return try Data(contentsOf: source)
        }

        // Full pipeline.
        let image = try ImageNormalizer.normalize(source: source, mode: mode)
        return try await renderInternal(image: image)
    }

    /// Produce `.icns` data directly from an in-memory `NSImage` — used for
    /// Wave 5's manual smoke test and any future programmatic-icon cases.
    /// Assumes the image is already square (1024×1024 preferred).
    static func render(image: NSImage) async throws -> Data {
        try await renderInternal(image: image)
    }

    private static func renderInternal(image: NSImage) async throws -> Data {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("Sigil-render-\(UUID().uuidString)", isDirectory: true)
        let iconsetDir = tempDir.appendingPathComponent("icon.iconset", isDirectory: true)

        try FileManager.default.createDirectory(at: iconsetDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try IconsetWriter.write(from: image, to: iconsetDir)
        return try await IconutilRunner.convert(iconsetDir: iconsetDir)
    }
}
