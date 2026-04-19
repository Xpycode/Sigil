import XCTest
@testable import Sigil

final class VolumeStoreTests: XCTestCase {

    private var tempDir: URL!
    private var storeURL: URL!
    private var backupURL: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SigilTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        storeURL = tempDir.appendingPathComponent("volumes.json")
        backupURL = tempDir.appendingPathComponent("volumes.json.bak")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func makeStore() -> VolumeStore {
        VolumeStore(storeURL: storeURL, backupURL: backupURL)
    }

    private func sampleRecord(uuid: String = UUID().uuidString, name: String = "Test") -> VolumeRecord {
        VolumeRecord(
            identity: VolumeIdentity(uuid),
            name: name,
            note: "",
            lastSeen: Date(timeIntervalSince1970: 1_700_000_000),
            fitMode: .fit
        )
    }

    // MARK: - Load / fresh start

    func testFreshStartReturnsEmpty() async throws {
        let store = makeStore()
        let result = try await store.load()
        let records = await store.allRecords()
        XCTAssertEqual(records.count, 0)
        if case .freshStart = result {} else { XCTFail("Expected .freshStart, got \(result)") }
    }

    // MARK: - Round-trip

    func testRoundTripPreservesRecords() async throws {
        let store = makeStore()
        try await store.load()
        try await store.upsert(sampleRecord(name: "A"))
        try await store.upsert(sampleRecord(name: "B"))
        try await store.upsert(sampleRecord(name: "C"))

        let store2 = makeStore()
        try await store2.load()
        let records = await store2.allRecords()
        XCTAssertEqual(records.count, 3)
        XCTAssertEqual(Set(records.map(\.name)), ["A", "B", "C"])
    }

    func testRecordEncodesUuidAtTopLevel() async throws {
        let store = makeStore()
        try await store.load()
        try await store.upsert(sampleRecord(uuid: "11111111-2222-3333-4444-555555555555", name: "Photos"))

        let raw = try String(contentsOf: storeURL, encoding: .utf8)
        XCTAssertTrue(raw.contains("\"uuid\""), "Expected `uuid` key at top level, got: \(raw)")
        XCTAssertTrue(raw.contains("11111111-2222-3333-4444-555555555555"))
    }

    // MARK: - Recovery

    func testFallbackToBackupOnCorruptedPrimary() async throws {
        let valid = try Self.encode([sampleRecord(name: "FromBackup")])
        try valid.write(to: backupURL)
        try Data("not valid json".utf8).write(to: storeURL)

        let store = makeStore()
        let result = try await store.load()
        let records = await store.allRecords()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.name, "FromBackup")
        if case .recoveredFromBackup = result {} else {
            XCTFail("Expected .recoveredFromBackup, got \(result)")
        }
    }

    func testBothCorruptStartsEmpty() async throws {
        try Data("garbage primary".utf8).write(to: storeURL)
        try Data("garbage backup".utf8).write(to: backupURL)

        let store = makeStore()
        let result = try await store.load()
        let records = await store.allRecords()
        XCTAssertEqual(records.count, 0)
        if case .bothCorrupt = result {} else { XCTFail("Expected .bothCorrupt, got \(result)") }
    }

    func testPrimaryCorruptNoBackup() async throws {
        try Data("garbage".utf8).write(to: storeURL)

        let store = makeStore()
        let result = try await store.load()
        let records = await store.allRecords()
        XCTAssertEqual(records.count, 0)
        if case .primaryCorruptNoBackup = result {} else {
            XCTFail("Expected .primaryCorruptNoBackup, got \(result)")
        }
    }

    // MARK: - Backup rotation

    func testBackupRotationCapturesPriorState() async throws {
        let store = makeStore()
        try await store.load()
        try await store.upsert(sampleRecord(name: "First"))
        try await store.upsert(sampleRecord(name: "Second"))

        let backupData = try Data(contentsOf: backupURL)
        let backupRecords = try Self.decode(backupData)
        XCTAssertEqual(backupRecords.count, 1)
        XCTAssertEqual(backupRecords.first?.name, "First")

        let primaryRecords = await store.allRecords()
        XCTAssertEqual(primaryRecords.count, 2)
    }

    // MARK: - Mutations

    func testUpsertIsIdempotentByIdentity() async throws {
        let store = makeStore()
        try await store.load()
        let id = "11111111-2222-3333-4444-555555555555"
        try await store.upsert(sampleRecord(uuid: id, name: "A"))
        try await store.upsert(sampleRecord(uuid: id, name: "B (updated)"))

        let records = await store.allRecords()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.name, "B (updated)")
    }

    func testRemoveReturnsFalseForUnknownIdentity() async throws {
        let store = makeStore()
        try await store.load()
        let id = "deadbeef-0000-0000-0000-000000000000"
        let removed = try await store.remove(identity: VolumeIdentity(id))
        XCTAssertFalse(removed)
    }

    func testRemoveDeletesAndPersists() async throws {
        let store = makeStore()
        try await store.load()
        let id = "11111111-2222-3333-4444-555555555555"
        try await store.upsert(sampleRecord(uuid: id, name: "DeleteMe"))

        let removed = try await store.remove(identity: VolumeIdentity(id))
        XCTAssertTrue(removed)
        let after = await store.allRecords()
        XCTAssertEqual(after.count, 0)

        // Verify it's gone after a fresh load too.
        let store2 = makeStore()
        try await store2.load()
        let afterReload = await store2.allRecords()
        XCTAssertEqual(afterReload.count, 0)
    }

    // MARK: - JSON helpers (mirrors VolumeStore's private encoder/decoder)

    private static func encode(_ records: [VolumeRecord]) throws -> Data {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return try e.encode(records)
    }

    private static func decode(_ data: Data) throws -> [VolumeRecord] {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return try d.decode([VolumeRecord].self, from: data)
    }
}
