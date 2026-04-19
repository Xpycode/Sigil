import XCTest
import AppKit
@testable import Sigil

final class IconRendererTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SigilIconRenderTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - Fixture helpers

    private func makeSolidColorPNG(size: NSSize, color: NSColor, name: String = "fixture") throws -> URL {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width),
            pixelsHigh: Int(size.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: [],
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw XCTSkip("could not allocate fixture bitmap")
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        color.setFill()
        NSRect(origin: .zero, size: size).fill()
        NSGraphicsContext.restoreGraphicsState()

        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw XCTSkip("could not encode fixture PNG")
        }
        let url = tempDir.appendingPathComponent("\(name)-\(UUID().uuidString.prefix(8)).png")
        try data.write(to: url)
        return url
    }

    // MARK: - Tests

    /// Valid .icns files start with the four-byte magic "icns".
    func testRenderProducesValidIcns() async throws {
        let source = try makeSolidColorPNG(
            size: NSSize(width: 512, height: 512), color: .systemBlue
        )
        let data = try await IconRenderer.render(source: source, mode: .fit)

        XCTAssertGreaterThan(data.count, 512, "icns output suspiciously small: \(data.count) bytes")

        let magic = data.prefix(4)
        XCTAssertEqual(String(data: magic, encoding: .ascii), "icns",
                       "missing icns magic bytes; got \(magic.map { String(format: "%02x", $0) }.joined())")
    }

    /// Fit-mode with a wide non-square source and Fill-mode with the same source
    /// should produce different .icns data (different pixel composition).
    func testFitAndFillProduceDifferentOutput() async throws {
        let source = try makeHalfSplitPNG(size: NSSize(width: 2000, height: 800))

        let fitData = try await IconRenderer.render(source: source, mode: .fit)
        let fillData = try await IconRenderer.render(source: source, mode: .fill)

        XCTAssertNotEqual(
            fitData, fillData,
            "fit and fill should produce distinct .icns for non-square input"
        )
    }

    /// If user imports an existing .icns, passthrough returns its bytes verbatim.
    func testPassthroughPreservesIcnsBytes() async throws {
        // First, generate a real .icns via the pipeline.
        let source = try makeSolidColorPNG(
            size: NSSize(width: 256, height: 256), color: .systemGreen
        )
        let original = try await IconRenderer.render(source: source, mode: .fit)

        let icnsURL = tempDir.appendingPathComponent("hand-crafted.icns")
        try original.write(to: icnsURL)

        let passthrough = try await IconRenderer.render(source: icnsURL, mode: .fill /* ignored */)
        XCTAssertEqual(passthrough, original,
                       "passthrough must return .icns bytes unmodified")
    }

    func testNonexistentSourceThrows() async {
        let bogus = tempDir.appendingPathComponent("does-not-exist.png")
        do {
            _ = try await IconRenderer.render(source: bogus, mode: .fit)
            XCTFail("expected render() to throw for missing file")
        } catch {
            // expected
        }
    }

    func testInvalidImageDataThrows() async throws {
        let bogus = tempDir.appendingPathComponent("not-an-image.png")
        try Data("this is not a valid PNG".utf8).write(to: bogus)
        do {
            _ = try await IconRenderer.render(source: bogus, mode: .fit)
            XCTFail("expected render() to throw for garbage PNG")
        } catch {
            // expected
        }
    }

    /// IconsetWriter produces the correct pixel dimensions per spec.
    func testIconsetWriterPixelSizes() throws {
        let source = try makeSolidColorPNG(
            size: NSSize(width: 1024, height: 1024), color: .systemOrange
        )
        guard let image = NSImage(contentsOf: source) else {
            XCTFail("fixture PNG could not be loaded back as NSImage")
            return
        }
        let iconsetDir = tempDir.appendingPathComponent("test.iconset", isDirectory: true)
        try FileManager.default.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

        try IconsetWriter.write(from: image, to: iconsetDir)

        for spec in IconsetWriter.specs {
            let fileURL = iconsetDir.appendingPathComponent(spec.filename)
            XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path),
                          "missing \(spec.filename)")
            guard let rep = NSBitmapImageRep.imageReps(withContentsOf: fileURL)?.first
                    as? NSBitmapImageRep else {
                XCTFail("could not read back \(spec.filename) as bitmap")
                continue
            }
            XCTAssertEqual(rep.pixelsWide, spec.pixelSize, "wrong width for \(spec.filename)")
            XCTAssertEqual(rep.pixelsHigh, spec.pixelSize, "wrong height for \(spec.filename)")
        }
    }

    // MARK: - More specific fixtures

    /// A 2:1 wide image split half-red / half-blue — gives fit and fill
    /// visibly different outputs.
    private func makeHalfSplitPNG(size: NSSize) throws -> URL {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width),
            pixelsHigh: Int(size.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: [],
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw XCTSkip("could not allocate half-split fixture bitmap")
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.systemRed.setFill()
        NSRect(x: 0, y: 0, width: size.width / 2, height: size.height).fill()
        NSColor.systemBlue.setFill()
        NSRect(x: size.width / 2, y: 0, width: size.width / 2, height: size.height).fill()
        NSGraphicsContext.restoreGraphicsState()

        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw XCTSkip("could not encode half-split fixture PNG")
        }
        let url = tempDir.appendingPathComponent("half-split-\(UUID().uuidString.prefix(8)).png")
        try data.write(to: url)
        return url
    }
}
