import Foundation

/// Pure decision logic for "a remembered volume just mounted — should we
/// silently re-apply, flag a conflict, or do nothing?"
///
/// Side-effect-free by design: all I/O happens through the injected store,
/// applier, and cache loader. Easily unit-testable with mocks.
actor SmartSilentApplier {

    enum Outcome: Sendable {
        /// Volume is unknown to Sigil, or has no UUID.
        case nothingToDo(NothingToDoReason)

        /// Icon was silently re-applied (hash matched, or on-disk icon was missing).
        case applied(hash: String)

        /// On-disk icon differs from the last-applied hash; user must resolve.
        case conflict(Conflict)

        enum NothingToDoReason: Sendable, Equatable {
            case notRemembered
            case volumeHasNoIdentity
            case cachedIcnsMissing  // Record exists but we can't find the cached bytes to re-apply.
        }

        struct Conflict: Sendable, Equatable {
            let identity: VolumeIdentity
            let volumeName: String
            let volumeURL: URL
            /// SHA-256 of `.VolumeIcon.icns` currently on the volume, or `nil`
            /// if the file is missing on-disk.
            let currentHash: String?
            /// SHA-256 of the bytes Sigil last wrote.
            let expectedHash: String
        }
    }

    /// Dependency: load cached `.icns` bytes for a given identity. Injected
    /// so tests can mock without touching the real App Support directory.
    typealias LoadIcns = @Sendable (VolumeIdentity) throws -> Data?

    private let store: VolumeStore
    private let applier: IconApplier
    private let loadIcns: LoadIcns

    init(
        store: VolumeStore,
        applier: IconApplier,
        loadIcns: @escaping LoadIcns = { try IconCache.loadIcns(for: $0) }
    ) {
        self.store = store
        self.applier = applier
        self.loadIcns = loadIcns
    }

    /// Handle a mount event for the given volume. Returns the decision taken
    /// and, on `.applied`, the new hash to persist.
    func handle(mount info: VolumeInfo) async throws -> Outcome {
        guard let identity = info.identity else {
            return .nothingToDo(.volumeHasNoIdentity)
        }
        guard let record = await store.record(for: identity) else {
            return .nothingToDo(.notRemembered)
        }

        let currentHash = await applier.currentIconHash(volumeURL: info.url)

        // No prior application — if we have cached bytes, apply them now.
        guard let expectedHash = record.lastAppliedHash else {
            return try await applyCached(identity: identity, info: info)
        }

        // Hash match, or nothing on disk at all → silent reapply.
        if currentHash == nil || currentHash == expectedHash {
            return try await applyCached(identity: identity, info: info)
        }

        // Mismatch — user must choose.
        return .conflict(.init(
            identity: identity,
            volumeName: info.name,
            volumeURL: info.url,
            currentHash: currentHash,
            expectedHash: expectedHash
        ))
    }

    // MARK: - Private

    private func applyCached(identity: VolumeIdentity, info: VolumeInfo) async throws -> Outcome {
        guard let icns = try loadIcns(identity) else {
            return .nothingToDo(.cachedIcnsMissing)
        }
        let hash = try await applier.apply(icns: icns, to: info.url)
        return .applied(hash: hash)
    }
}
