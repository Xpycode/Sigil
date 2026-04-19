import XCTest
@testable import Sigil

/// Unit tests for the smart-silent decision logic. Uses a real `VolumeStore`
/// backed by a temp directory, and the real `IconApplier` against a temp dir
/// that pretends to be a volume root. The `loadIcns` dependency is injected
/// so we can control cache presence without touching real App Support.
final class SmartSilentApplierTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SigilSmartSilent-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - Fixtures

    private func makeStore() -> VolumeStore {
        VolumeStore(
            storeURL: tempDir.appendingPathComponent("volumes.json"),
            backupURL: tempDir.appendingPathComponent("volumes.json.bak")
        )
    }

    private func makeVolumeDir(name: String) throws -> URL {
        let dir = tempDir.appendingPathComponent("Volumes/\(name)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeInfo(name: String, identity: String?) throws -> VolumeInfo {
        let url = try makeVolumeDir(name: name)
        return VolumeInfo(
            identity: identity.map { VolumeIdentity($0) },
            url: url,
            name: name,
            capacityBytes: 1_000_000_000,
            isRemovable: false,
            isInternal: false,
            isEjectable: false,
            isRootFileSystem: false,
            format: "APFS"
        )
    }

    private func makeRecord(
        identity: VolumeIdentity,
        name: String,
        lastAppliedHash: String? = nil
    ) -> VolumeRecord {
        VolumeRecord(
            identity: identity,
            name: name,
            note: "",
            lastSeen: Date(),
            lastApplied: lastAppliedHash == nil ? nil : Date(),
            lastAppliedHash: lastAppliedHash,
            fitMode: .fit,
            sourceFilename: nil
        )
    }

    /// Minimal bytes that look like a real .icns — four bytes "icns" + length
    /// + some padding. IconApplier doesn't parse this; it just writes bytes.
    private func makeFakeIcns(size: Int = 256) -> Data {
        var data = Data()
        data.append(contentsOf: [0x69, 0x63, 0x6e, 0x73])  // "icns"
        data.append(contentsOf: withUnsafeBytes(of: UInt32(size).bigEndian) { Array($0) })
        while data.count < size { data.append(UInt8.random(in: 0...255)) }
        return data
    }

    // MARK: - Tests

    func testNothingToDoWhenVolumeHasNoIdentity() async throws {
        let store = makeStore()
        try await store.load()
        let applier = IconApplier()
        let smart = SmartSilentApplier(store: store, applier: applier, loadIcns: { _ in nil })

        let info = try makeInfo(name: "Blankie", identity: nil)
        let outcome = try await smart.handle(mount: info)

        XCTAssertEqual(outcome.reasonIfNothing, .volumeHasNoIdentity)
    }

    func testNothingToDoWhenNotRemembered() async throws {
        let store = makeStore()
        try await store.load()
        let applier = IconApplier()
        let smart = SmartSilentApplier(store: store, applier: applier, loadIcns: { _ in nil })

        let info = try makeInfo(name: "Newbie", identity: "NEW-1111")
        let outcome = try await smart.handle(mount: info)

        XCTAssertEqual(outcome.reasonIfNothing, .notRemembered)
    }

    func testNothingToDoWhenCachedIcnsMissing() async throws {
        let store = makeStore()
        try await store.load()
        try await store.upsert(makeRecord(
            identity: VolumeIdentity("CACHE-MISS"),
            name: "CacheMiss",
            lastAppliedHash: "a" + String(repeating: "0", count: 63)
        ))
        let applier = IconApplier()
        let smart = SmartSilentApplier(store: store, applier: applier, loadIcns: { _ in nil })

        let info = try makeInfo(name: "CacheMiss", identity: "CACHE-MISS")
        let outcome = try await smart.handle(mount: info)

        XCTAssertEqual(outcome.reasonIfNothing, .cachedIcnsMissing)
    }

    func testSilentApplyWhenNoIconOnDisk() async throws {
        let store = makeStore()
        try await store.load()
        let identity = VolumeIdentity("HAPPY-1234")
        let icns = makeFakeIcns()
        try await store.upsert(makeRecord(
            identity: identity,
            name: "Happy",
            lastAppliedHash: Hashing.sha256Hex(icns)
        ))

        let applier = IconApplier()
        let smart = SmartSilentApplier(store: store, applier: applier) { id in
            id == identity ? icns : nil
        }

        let info = try makeInfo(name: "Happy", identity: "HAPPY-1234")
        let outcome = try await smart.handle(mount: info)

        switch outcome {
        case .applied(let hash): XCTAssertEqual(hash, Hashing.sha256Hex(icns))
        default: XCTFail("expected .applied, got \(outcome)")
        }
        // Side effect: file should now exist on the "volume".
        let writtenIcon = info.url.appendingPathComponent(IconApplier.iconFilename)
        XCTAssertTrue(FileManager.default.fileExists(atPath: writtenIcon.path))
    }

    func testSilentApplyWhenHashMatches() async throws {
        let store = makeStore()
        try await store.load()
        let identity = VolumeIdentity("MATCH-5678")
        let icns = makeFakeIcns()
        let hash = Hashing.sha256Hex(icns)
        try await store.upsert(makeRecord(
            identity: identity,
            name: "Match",
            lastAppliedHash: hash
        ))

        // Pre-place the same bytes on the "volume" to simulate unchanged icon.
        let info = try makeInfo(name: "Match", identity: "MATCH-5678")
        try icns.write(to: info.url.appendingPathComponent(IconApplier.iconFilename))

        let applier = IconApplier()
        let smart = SmartSilentApplier(store: store, applier: applier) { _ in icns }
        let outcome = try await smart.handle(mount: info)

        switch outcome {
        case .applied(let h): XCTAssertEqual(h, hash)
        default: XCTFail("expected .applied, got \(outcome)")
        }
    }

    func testConflictWhenOnDiskHashDiffers() async throws {
        let store = makeStore()
        try await store.load()
        let identity = VolumeIdentity("CONFLICT-9")
        let originalIcns = makeFakeIcns(size: 256)
        let tamperedIcns = makeFakeIcns(size: 256)
        XCTAssertNotEqual(originalIcns, tamperedIcns)
        try await store.upsert(makeRecord(
            identity: identity,
            name: "Conflict",
            lastAppliedHash: Hashing.sha256Hex(originalIcns)
        ))

        // Place DIFFERENT bytes on the "volume" — the tampered version.
        let info = try makeInfo(name: "Conflict", identity: "CONFLICT-9")
        try tamperedIcns.write(to: info.url.appendingPathComponent(IconApplier.iconFilename))

        let applier = IconApplier()
        let smart = SmartSilentApplier(store: store, applier: applier) { _ in originalIcns }
        let outcome = try await smart.handle(mount: info)

        switch outcome {
        case .conflict(let c):
            XCTAssertEqual(c.expectedHash, Hashing.sha256Hex(originalIcns))
            XCTAssertEqual(c.currentHash, Hashing.sha256Hex(tamperedIcns))
            XCTAssertEqual(c.identity, identity)
        default:
            XCTFail("expected .conflict, got \(outcome)")
        }
    }

    func testApplyWhenRecordExistsButNeverApplied() async throws {
        // Edge case: record exists (volume remembered) but lastAppliedHash is nil
        // — means user added the record but never pushed it. On mount we should
        // apply the cached bytes silently.
        let store = makeStore()
        try await store.load()
        let identity = VolumeIdentity("NEVER-APPLIED")
        try await store.upsert(makeRecord(identity: identity, name: "NeverApplied", lastAppliedHash: nil))
        let icns = makeFakeIcns()

        let applier = IconApplier()
        let smart = SmartSilentApplier(store: store, applier: applier) { _ in icns }
        let info = try makeInfo(name: "NeverApplied", identity: "NEVER-APPLIED")

        let outcome = try await smart.handle(mount: info)
        switch outcome {
        case .applied(let h): XCTAssertEqual(h, Hashing.sha256Hex(icns))
        default: XCTFail("expected .applied, got \(outcome)")
        }
    }
}

// MARK: - Outcome testing helpers

extension SmartSilentApplier.Outcome {
    var reasonIfNothing: NothingToDoReason? {
        if case .nothingToDo(let r) = self { return r }
        return nil
    }
}
