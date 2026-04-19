import XCTest
import AppKit
@testable import Sigil

/// Integration tests that create a scratch APFS disk image via `hdiutil`,
/// attach it, run `IconApplier` against its mount point, and assert the
/// on-disk state. Skips cleanly if `hdiutil` is unavailable or DMG creation
/// fails (e.g., in restricted CI environments).
final class IconApplierTests: XCTestCase {

    private var tempDir: URL!
    private var dmgURL: URL?
    private var mountURL: URL?

    override func setUp() async throws {
        try await super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SigilApplierTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        do {
            try await createAndAttachDMG()
        } catch {
            // Leave mountURL nil — tests will XCTSkip.
            print("IconApplierTests setUp: could not create scratch DMG (\(error)); tests will skip.")
            mountURL = nil
        }
    }

    override func tearDown() async throws {
        if let mountURL {
            try? await detachDMG(mountURL)
        }
        if let dmgURL {
            try? FileManager.default.removeItem(at: dmgURL)
        }
        try? FileManager.default.removeItem(at: tempDir)
        try await super.tearDown()
    }

    private func requireMount() throws -> URL {
        guard let mountURL else {
            throw XCTSkip("scratch DMG not available; skipping (is /usr/bin/hdiutil present?)")
        }
        return mountURL
    }

    // MARK: - Tests

    func testApplyWritesIcnsFile() async throws {
        let mount = try requireMount()
        let icns = try await renderTestIcns(color: .systemBlue)

        let applier = IconApplier()
        let hash = try await applier.apply(icns: icns, to: mount)

        let iconURL = mount.appendingPathComponent(IconApplier.iconFilename)
        XCTAssertTrue(FileManager.default.fileExists(atPath: iconURL.path))
        let onDisk = try Data(contentsOf: iconURL)
        XCTAssertEqual(onDisk, icns)
        XCTAssertEqual(hash, Hashing.sha256Hex(icns))
    }

    func testApplySetsCustomIconFlag() async throws {
        let mount = try requireMount()
        let icns = try await renderTestIcns(color: .systemOrange)

        let applier = IconApplier()
        _ = try await applier.apply(icns: icns, to: mount)

        let info = try XAttr.get(name: IconApplier.finderInfoKey, from: mount.path)
        XCTAssertNotNil(info, "FinderInfo xattr should be set after apply")
        guard let info else { return }
        XCTAssertGreaterThanOrEqual(info.count, IconApplier.finderInfoLength)
        let flagByte = info[IconApplier.customIconByteOffset]
        XCTAssertEqual(flagByte & IconApplier.customIconFlag, IconApplier.customIconFlag,
                       "byte 8 of FinderInfo should have the 0x04 bit set")

        let hasFlag = await applier.hasCustomIconFlag(volumeURL: mount)
        XCTAssertTrue(hasFlag)
    }

    func testApplyPreservesOtherFinderInfoBytes() async throws {
        let mount = try requireMount()

        // Seed FinderInfo with a non-zero label color byte (byte 0..1 flags region)
        // before apply, to verify we don't blow it away.
        var seed = Data(count: 32)
        seed[0] = 0xDE
        seed[1] = 0xAD
        seed[12] = 0xBE
        seed[13] = 0xEF
        try XAttr.set(name: IconApplier.finderInfoKey, value: seed, on: mount.path)

        let icns = try await renderTestIcns(color: .systemGreen)
        let applier = IconApplier()
        _ = try await applier.apply(icns: icns, to: mount)

        let after = try XCTUnwrap(try XAttr.get(name: IconApplier.finderInfoKey, from: mount.path))
        XCTAssertEqual(after[0], 0xDE, "unrelated FinderInfo byte was clobbered")
        XCTAssertEqual(after[1], 0xAD, "unrelated FinderInfo byte was clobbered")
        XCTAssertEqual(after[12], 0xBE, "unrelated FinderInfo byte was clobbered")
        XCTAssertEqual(after[13], 0xEF, "unrelated FinderInfo byte was clobbered")
        XCTAssertEqual(after[IconApplier.customIconByteOffset] & IconApplier.customIconFlag,
                       IconApplier.customIconFlag)
    }

    func testResetRemovesIconAndClearsFlag() async throws {
        let mount = try requireMount()
        let icns = try await renderTestIcns(color: .systemRed)

        let applier = IconApplier()
        _ = try await applier.apply(icns: icns, to: mount)
        try await applier.reset(volumeURL: mount)

        let iconURL = mount.appendingPathComponent(IconApplier.iconFilename)
        XCTAssertFalse(FileManager.default.fileExists(atPath: iconURL.path),
                       ".VolumeIcon.icns should be gone after reset")

        let hasFlag = await applier.hasCustomIconFlag(volumeURL: mount)
        XCTAssertFalse(hasFlag, "custom-icon flag should be cleared after reset")
    }

    func testCurrentIconHashMatchesApplyReturn() async throws {
        let mount = try requireMount()
        let icns = try await renderTestIcns(color: .systemPurple)

        let applier = IconApplier()
        let applied = try await applier.apply(icns: icns, to: mount)
        let readBack = await applier.currentIconHash(volumeURL: mount)

        XCTAssertEqual(applied, readBack)
    }

    func testCurrentIconHashNilWhenNothingApplied() async throws {
        let mount = try requireMount()
        let applier = IconApplier()
        let hash = await applier.currentIconHash(volumeURL: mount)
        XCTAssertNil(hash)
    }

    func testResetIsIdempotent() async throws {
        let mount = try requireMount()
        let applier = IconApplier()
        // No apply first — reset should not throw on a clean volume.
        try await applier.reset(volumeURL: mount)
        try await applier.reset(volumeURL: mount)
    }

    // MARK: - Fixtures

    private func renderTestIcns(color: NSColor) async throws -> Data {
        let src = tempDir.appendingPathComponent("src-\(UUID().uuidString.prefix(6)).png")
        let pngData = try makeSolidColorPNG(size: NSSize(width: 256, height: 256), color: color)
        try pngData.write(to: src)
        return try await IconRenderer.render(source: src, mode: .fit)
    }

    private func makeSolidColorPNG(size: NSSize, color: NSColor) throws -> Data {
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
        return data
    }

    // MARK: - DMG lifecycle

    private func createAndAttachDMG() async throws {
        guard FileManager.default.fileExists(atPath: "/usr/bin/hdiutil") else {
            throw NSError(domain: "SigilApplierTests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "hdiutil not available"])
        }

        let volName = "SigilTest\(UUID().uuidString.prefix(8))"
        let dmg = tempDir.appendingPathComponent("scratch.dmg")
        self.dmgURL = dmg

        // Create 40 MB APFS DMG.
        try await runProcess(
            "/usr/bin/hdiutil",
            ["create", "-size", "40m", "-fs", "APFS", "-volname", String(volName), dmg.path]
        )

        // Attach and parse mount URL from output.
        let (_, stdout) = try await runProcess(
            "/usr/bin/hdiutil",
            ["attach", dmg.path],
            captureStdout: true
        )
        for line in stdout.components(separatedBy: .newlines) {
            if let range = line.range(of: "/Volumes/") {
                let mountPath = String(line[range.lowerBound...]).trimmingCharacters(in: .whitespaces)
                self.mountURL = URL(fileURLWithPath: mountPath)
                return
            }
        }
        throw NSError(domain: "SigilApplierTests", code: 2,
                      userInfo: [NSLocalizedDescriptionKey: "could not parse hdiutil attach output: \(stdout)"])
    }

    private func detachDMG(_ mountURL: URL) async throws {
        _ = try await runProcess(
            "/usr/bin/hdiutil",
            ["detach", mountURL.path, "-force"]
        )
    }

    @discardableResult
    private func runProcess(
        _ executablePath: String,
        _ arguments: [String],
        captureStdout: Bool = false
    ) async throws -> (status: Int32, stdout: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Swift.Error>) in
            process.terminationHandler = { _ in cont.resume() }
            do { try process.run() } catch { cont.resume(throwing: error) }
        }

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""

        if process.terminationStatus != 0 {
            let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(),
                                encoding: .utf8) ?? ""
            throw NSError(
                domain: "SigilApplierTests",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey:
                            "\(executablePath) exited \(process.terminationStatus): \(stderr)"]
            )
        }
        return (process.terminationStatus, stdout)
    }
}
