import Foundation
import SwiftUI

/// Top-level orchestrator. Owns the persistent store, enumerator, and watcher;
/// exposes the data the UI binds to and the high-level actions the UI invokes.
@MainActor
@Observable
final class AppState {

    // MARK: - Published state

    private(set) var mounted: [VolumeInfo] = []
    private(set) var remembered: [VolumeRecord] = []
    var selectedID: String?

    /// Conflicts surfaced by `SmartSilentApplier` that the user hasn't resolved
    /// yet. Rendered as an in-app banner in the detail pane.
    private(set) var pendingConflicts: [SmartSilentApplier.Outcome.Conflict] = []

    /// Toolbar toggle — when `true` the sidebar also lists boot/system/DMG volumes.
    var showAllVolumes: Bool = false {
        didSet {
            guard oldValue != showAllVolumes else { return }
            Task { await refresh() }
        }
    }

    // MARK: - Services

    private(set) var store: VolumeStore?
    private let enumerator = VolumeEnumerator()
    private let watcher = MountWatcher()
    private let applier = IconApplier()
    private var smart: SmartSilentApplier?
    private var streamTask: Task<Void, Never>?

    // MARK: - Lifecycle

    init() {}

    func bootstrap() async {
        do {
            let store = try VolumeStore()
            self.store = store
            _ = try await store.load()
            self.remembered = await store.allRecords()
            self.smart = SmartSilentApplier(store: store, applier: applier)
        } catch {
            print("Sigil: failed to load VolumeStore — \(error)")
        }
        ConflictNotifier.shared.attach(to: self)
        await refresh()
        startWatching()
    }

    func refresh() async {
        self.mounted = await enumerator.currentVolumes(includeSystem: showAllVolumes)
    }

    // MARK: - Derived

    var rememberedNotMounted: [VolumeRecord] {
        let mountedIDs = Set(mounted.compactMap { $0.identity?.raw })
        return remembered.filter { !mountedIDs.contains($0.identity.raw) }
    }

    var selectedMounted: VolumeInfo? {
        guard let id = selectedID else { return nil }
        return mounted.first(where: { $0.id == id })
    }

    var selectedRemembered: VolumeRecord? {
        guard let id = selectedID else { return nil }
        return rememberedNotMounted.first(where: { $0.id == id })
    }

    /// Pending conflict for the currently-selected volume, if any.
    var selectedConflict: SmartSilentApplier.Outcome.Conflict? {
        guard let id = selectedID else { return nil }
        return pendingConflicts.first(where: { $0.identity.raw == id })
    }

    // MARK: - Icon actions (user-driven)

    /// Apply a user-provided source image as the volume's custom icon.
    /// Full pipeline: render → cache → write to volume → persist record.
    func applyIcon(source: URL, mode: FitMode, to info: VolumeInfo) async throws {
        guard let identity = info.identity else { throw Error.noIdentity }
        guard let store else { throw Error.notReady }

        let icns = try await IconRenderer.render(source: source, mode: mode)
        try await applyRendered(
            icns: icns, info: info, identity: identity,
            fitMode: mode, sourceFilename: source.lastPathComponent,
            cacheSource: source, store: store
        )
    }

    /// Apply an in-memory rendered `.icns` (used by the Wave 5 smoke test).
    func applyRenderedIcns(_ icns: Data, to info: VolumeInfo, labelMode: FitMode = .fit) async throws {
        guard let identity = info.identity else { throw Error.noIdentity }
        guard let store else { throw Error.notReady }
        try await applyRendered(
            icns: icns, info: info, identity: identity,
            fitMode: labelMode, sourceFilename: nil,
            cacheSource: nil, store: store
        )
    }

    private func applyRendered(
        icns: Data,
        info: VolumeInfo,
        identity: VolumeIdentity,
        fitMode: FitMode,
        sourceFilename: String?,
        cacheSource: URL?,
        store: VolumeStore
    ) async throws {
        try IconCache.saveIcns(icns, for: identity)
        if let cacheSource {
            try IconCache.saveSource(cacheSource, for: identity)
        }

        let hash = try await applier.apply(icns: icns, to: info.url)

        let existing = await store.record(for: identity)
        let record = VolumeRecord(
            identity: identity,
            name: info.name,
            note: existing?.note ?? "",
            lastSeen: Date(),
            lastApplied: Date(),
            lastAppliedHash: hash,
            fitMode: fitMode,
            sourceFilename: sourceFilename ?? existing?.sourceFilename
        )
        try await store.upsert(record)
        self.remembered = await store.allRecords()
        // Clear any conflict banner for this volume — we just authoritatively set the icon.
        pendingConflicts.removeAll { $0.identity == identity }
    }

    /// Reset the icon on a mounted volume and remove the record.
    func resetIcon(for info: VolumeInfo) async throws {
        guard let identity = info.identity else { throw Error.noIdentity }
        guard let store else { throw Error.notReady }
        try await applier.reset(volumeURL: info.url)
        try? IconCache.delete(for: identity)
        _ = try await store.remove(identity: identity)
        self.remembered = await store.allRecords()
        pendingConflicts.removeAll { $0.identity == identity }
    }

    /// Forget a remembered volume (mounted or not). Removes record + cache;
    /// leaves any `.VolumeIcon.icns` that may be on the physical volume intact.
    func forget(identity: VolumeIdentity) async throws {
        guard let store else { throw Error.notReady }
        _ = try await store.remove(identity: identity)
        try? IconCache.delete(for: identity)
        self.remembered = await store.allRecords()
        pendingConflicts.removeAll { $0.identity == identity }
    }

    // MARK: - Conflict resolution

    /// User picked "Use Sigil icon" — re-apply our cached bytes despite mismatch.
    func resolveConflictUseSigil(identity: VolumeIdentity) async throws {
        guard let store else { throw Error.notReady }
        guard let info = mounted.first(where: { $0.identity == identity }) else {
            // Not currently mounted — just drop the conflict; will re-evaluate on next mount.
            pendingConflicts.removeAll { $0.identity == identity }
            return
        }
        guard let icns = try IconCache.loadIcns(for: identity) else {
            throw Error.cachedIcnsMissing
        }
        let hash = try await applier.apply(icns: icns, to: info.url)
        if var record = await store.record(for: identity) {
            record.lastApplied = Date()
            record.lastAppliedHash = hash
            try await store.upsert(record)
            self.remembered = await store.allRecords()
        }
        pendingConflicts.removeAll { $0.identity == identity }
    }

    /// User picked "Keep current" — update Sigil's stored hash to match disk.
    func resolveConflictKeepCurrent(identity: VolumeIdentity) async throws {
        guard let store else { throw Error.notReady }
        guard let info = mounted.first(where: { $0.identity == identity }) else {
            pendingConflicts.removeAll { $0.identity == identity }
            return
        }
        let currentHash = await applier.currentIconHash(volumeURL: info.url)
        if var record = await store.record(for: identity) {
            record.lastAppliedHash = currentHash
            record.lastApplied = Date()
            try await store.upsert(record)
            self.remembered = await store.allRecords()
        }
        pendingConflicts.removeAll { $0.identity == identity }
    }

    // MARK: - Watcher loop

    private func startWatching() {
        streamTask?.cancel()
        streamTask = Task { [weak self] in
            guard let self else { return }
            let stream = await self.watcher.events()
            for await event in stream {
                await self.handle(event)
            }
        }
    }

    private func handle(_ event: MountEvent) async {
        await refresh()

        // Smart-silent dispatch on mount events only.
        if case .mounted(let url) = event {
            await runSmartSilent(for: url)
        }
    }

    /// Used at launch to process volumes that were already mounted when the app started.
    func processCurrentlyMountedForSmartSilent() async {
        for info in mounted {
            await runSmartSilent(info: info)
        }
    }

    private func runSmartSilent(for url: URL) async {
        guard let info = await enumerator.info(for: url) else { return }
        await runSmartSilent(info: info)
    }

    private func runSmartSilent(info: VolumeInfo) async {
        guard let smart else { return }
        do {
            let outcome = try await smart.handle(mount: info)
            switch outcome {
            case .nothingToDo:
                break
            case .applied(let hash):
                // Update lastApplied / lastAppliedHash (hash should be unchanged
                // since we applied the exact stored bytes, but lastApplied advances).
                if let store, let identity = info.identity,
                   var record = await store.record(for: identity) {
                    record.lastApplied = Date()
                    record.lastAppliedHash = hash
                    record.lastSeen = Date()
                    try await store.upsert(record)
                    self.remembered = await store.allRecords()
                }
            case .conflict(let conflict):
                if !pendingConflicts.contains(where: { $0.identity == conflict.identity }) {
                    pendingConflicts.append(conflict)
                }
                await ConflictNotifier.shared.postConflict(conflict)
            }
        } catch {
            print("Sigil: smart-silent failed for \(info.name) — \(error)")
        }
    }

    // MARK: - Error

    enum Error: LocalizedError {
        case noIdentity
        case notReady
        case cachedIcnsMissing

        var errorDescription: String? {
            switch self {
            case .noIdentity: "This volume has no UUID and can't be remembered."
            case .notReady: "Sigil is still starting up. Try again in a moment."
            case .cachedIcnsMissing: "Sigil's cached icon for this volume is missing."
            }
        }
    }
}
