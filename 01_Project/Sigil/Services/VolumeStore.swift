import Foundation

/// Persistent store of `VolumeRecord`s, backed by `volumes.json` in App Support.
///
/// Atomicity & durability:
/// - Every `save()` writes to a temp file then atomically renames over the primary
///   (POSIX rename on the same volume is atomic).
/// - Before each save, the previous primary is copied to `volumes.json.bak`.
/// - On `load()`, a corrupted primary falls back to the backup; if both are
///   corrupted, the store starts empty and reports `.bothCorrupt`.
///
/// All mutation is serialized through actor isolation — no manual locks.
actor VolumeStore {

    private let storeURL: URL
    private let backupURL: URL
    private(set) var records: [VolumeRecord] = []
    private var loaded = false

    /// Production initializer — uses `AppPaths`.
    init() throws {
        self.storeURL = try AppPaths.volumesJSON()
        self.backupURL = try AppPaths.volumesJSONBackup()
    }

    /// Test initializer — explicit URLs for isolated test directories.
    init(storeURL: URL, backupURL: URL) {
        self.storeURL = storeURL
        self.backupURL = backupURL
    }

    /// Load from disk. Falls back to `.bak` on corruption. Idempotent —
    /// subsequent calls re-read from disk.
    @discardableResult
    func load() async throws -> LoadResult {
        let fm = FileManager.default

        if fm.fileExists(atPath: storeURL.path) {
            do {
                let data = try Data(contentsOf: storeURL)
                self.records = try Self.decode(data)
                self.loaded = true
                return .loadedPrimary(count: records.count)
            } catch let primaryError {
                if fm.fileExists(atPath: backupURL.path) {
                    do {
                        let data = try Data(contentsOf: backupURL)
                        self.records = try Self.decode(data)
                        self.loaded = true
                        return .recoveredFromBackup(count: records.count, primaryError: primaryError)
                    } catch let backupError {
                        self.records = []
                        self.loaded = true
                        return .bothCorrupt(primaryError: primaryError, backupError: backupError)
                    }
                }
                self.records = []
                self.loaded = true
                return .primaryCorruptNoBackup(primaryError: primaryError)
            }
        }

        self.records = []
        self.loaded = true
        return .freshStart
    }

    /// Persist current records atomically, rotating the previous state to `.bak`.
    func save() async throws {
        let data = try Self.encode(records)
        let fm = FileManager.default

        // Step 1: rotate current → .bak (preserves last-known-good state).
        if fm.fileExists(atPath: storeURL.path) {
            if fm.fileExists(atPath: backupURL.path) {
                try fm.removeItem(at: backupURL)
            }
            try fm.copyItem(at: storeURL, to: backupURL)
        }

        // Step 2: atomic write of new primary.
        // `.atomic` writes to a temp file then renames — survives mid-write crash.
        try data.write(to: storeURL, options: [.atomic])
    }

    // MARK: - Mutations

    /// Insert or update a record by identity. Persists immediately.
    func upsert(_ record: VolumeRecord) async throws {
        try await ensureLoaded()
        if let idx = records.firstIndex(where: { $0.identity == record.identity }) {
            records[idx] = record
        } else {
            records.append(record)
        }
        try await save()
    }

    /// Remove a record by identity. Persists immediately. Returns `true` if
    /// a record was removed, `false` if no matching record existed.
    @discardableResult
    func remove(identity: VolumeIdentity) async throws -> Bool {
        try await ensureLoaded()
        let before = records.count
        records.removeAll { $0.identity == identity }
        guard records.count != before else { return false }
        try await save()
        return true
    }

    // MARK: - Reads

    func record(for identity: VolumeIdentity) -> VolumeRecord? {
        records.first(where: { $0.identity == identity })
    }

    func allRecords() -> [VolumeRecord] {
        records
    }

    // MARK: - Private

    private func ensureLoaded() async throws {
        if !loaded { try await load() }
    }

    private static func decode(_ data: Data) throws -> [VolumeRecord] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([VolumeRecord].self, from: data)
    }

    private static func encode(_ records: [VolumeRecord]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(records)
    }
}

extension VolumeStore {
    enum LoadResult: Sendable {
        case freshStart
        case loadedPrimary(count: Int)
        case recoveredFromBackup(count: Int, primaryError: Error)
        case primaryCorruptNoBackup(primaryError: Error)
        case bothCorrupt(primaryError: Error, backupError: Error)

        var recordCount: Int {
            switch self {
            case .freshStart, .primaryCorruptNoBackup, .bothCorrupt: 0
            case .loadedPrimary(let n), .recoveredFromBackup(let n, _): n
            }
        }
    }
}
