import Foundation
import SwiftUI
import AppKit

/// Top-level orchestrator. Owns the persistent store, enumerator, and watcher;
/// exposes the data the UI binds to and the high-level actions the UI invokes.
@MainActor
@Observable
final class AppState {

    // MARK: - Published state

    private(set) var mounted: [VolumeInfo] = []
    private(set) var remembered: [VolumeRecord] = []
    var selectedID: String?

    /// Cached icon thumbnails keyed by `identity.raw`. Populated at bootstrap
    /// from the on-disk `.icns` cache; refreshed surgically on apply/reset/forget.
    /// Drives the sidebar's per-row thumbnail — a glanceable "what's applied where".
    private(set) var iconThumbnails: [String: NSImage] = [:]

    /// Conflicts surfaced by `SmartSilentApplier` that the user hasn't resolved
    /// yet. Rendered as an in-app banner in the detail pane.
    private(set) var pendingConflicts: [SmartSilentApplier.Outcome.Conflict] = []

    /// Error surfaced to the user via `.alert`. Set on background-failure paths
    /// (bootstrap, smart-silent re-apply). User-initiated errors (Apply button,
    /// Reset button) surface inline in `VolumeDetailView` instead.
    var lastError: String?

    /// Non-blocking warning surfaced at launch when `VolumeStore.load` had to
    /// recover from backup or start empty due to corruption.
    var lastLoadWarning: String?

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
        Log.ui.info("Sigil bootstrap starting")
        do {
            let store = try VolumeStore()
            self.store = store
            let result = try await store.load()
            self.remembered = await store.allRecords()
            self.smart = SmartSilentApplier(store: store, applier: applier)
            handleLoadResult(result)
        } catch {
            Log.io.error("VolumeStore init/load failed: \(error.localizedDescription)")
            lastError = "Sigil couldn't initialize its volume memory. \(error.localizedDescription)"
        }
        ConflictNotifier.shared.attach(to: self)
        loadAllThumbnails()
        await refresh()
        startWatching()
        Log.ui.info("Sigil bootstrap complete — \(self.remembered.count, privacy: .public) remembered, \(self.mounted.count, privacy: .public) mounted")
    }

    private func handleLoadResult(_ result: VolumeStore.LoadResult) {
        switch result {
        case .freshStart:
            Log.io.info("VolumeStore: fresh start (no prior store)")
        case .loadedPrimary(let n):
            Log.io.info("VolumeStore: loaded \(n, privacy: .public) records from primary")
        case .recoveredFromBackup(let n, let err):
            Log.io.warning("VolumeStore: recovered \(n, privacy: .public) records from .bak (primary error: \(err.localizedDescription))")
            lastLoadWarning = "Sigil couldn't read its primary volume memory file but recovered \(n) record\(n == 1 ? "" : "s") from the backup. Recent changes since the last successful save may have been lost."
        case .primaryCorruptNoBackup(let err):
            Log.io.error("VolumeStore: primary corrupt, no backup (error: \(err.localizedDescription))")
            lastLoadWarning = "Sigil couldn't read its volume memory file and no backup was available. Starting fresh — your previously-remembered volumes are gone. If you have a backup in Time Machine, you can restore ~/Library/Application Support/Sigil/volumes.json manually."
        case .bothCorrupt(let pErr, _):
            Log.io.error("VolumeStore: both primary and backup corrupt (primary: \(pErr.localizedDescription))")
            lastLoadWarning = "Sigil couldn't read its volume memory file or its backup. Starting fresh — your previously-remembered volumes are gone. If you have a backup in Time Machine, you can restore ~/Library/Application Support/Sigil/volumes.json manually."
        }
    }

    /// Populate `iconThumbnails` by reading every remembered record's cached
    /// `.icns` file. Runs synchronously on the main actor (fast: 20 drives ≈ <50ms).
    private func loadAllThumbnails() {
        var result: [String: NSImage] = [:]
        for record in remembered {
            if let data = try? IconCache.loadIcns(for: record.identity),
               let image = NSImage(data: data) {
                result[record.identity.raw] = image
            }
        }
        iconThumbnails = result
    }

    /// Refresh a single thumbnail by re-reading its cached `.icns`.
    private func refreshThumbnail(for identity: VolumeIdentity) {
        if let data = try? IconCache.loadIcns(for: identity),
           let image = NSImage(data: data) {
            iconThumbnails[identity.raw] = image
        } else {
            iconThumbnails.removeValue(forKey: identity.raw)
        }
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
        Log.ui.info("apply: \(info.name, privacy: .public) (mode: \(fitMode.rawValue, privacy: .public), \(icns.count, privacy: .public) bytes)")

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
        refreshThumbnail(for: identity)
        pendingConflicts.removeAll { $0.identity == identity }
        Log.ui.info("apply: success on \(info.name, privacy: .public), hash \(hash.prefix(12), privacy: .public)…")
    }

    /// Reset the icon on a mounted volume and remove the record.
    func resetIcon(for info: VolumeInfo) async throws {
        guard let identity = info.identity else { throw Error.noIdentity }
        guard let store else { throw Error.notReady }
        Log.ui.info("reset: \(info.name, privacy: .public)")
        try await applier.reset(volumeURL: info.url)
        try? IconCache.delete(for: identity)
        _ = try await store.remove(identity: identity)
        self.remembered = await store.allRecords()
        iconThumbnails.removeValue(forKey: identity.raw)
        pendingConflicts.removeAll { $0.identity == identity }
    }

    /// Forget a remembered volume (mounted or not). Removes record + cache;
    /// leaves any `.VolumeIcon.icns` that may be on the physical volume intact.
    func forget(identity: VolumeIdentity) async throws {
        guard let store else { throw Error.notReady }
        Log.ui.info("forget: \(identity.raw, privacy: .public)")
        _ = try await store.remove(identity: identity)
        try? IconCache.delete(for: identity)
        self.remembered = await store.allRecords()
        iconThumbnails.removeValue(forKey: identity.raw)
        pendingConflicts.removeAll { $0.identity == identity }
    }

    /// Update just the note on a remembered volume. No-op if the volume
    /// isn't in the store yet (wait for Apply to create the record first).
    func updateNote(for identity: VolumeIdentity, to newNote: String) async throws {
        guard let store else { throw Error.notReady }
        guard var record = await store.record(for: identity) else { return }
        guard record.note != newNote else { return }
        record.note = newNote
        try await store.upsert(record)
        self.remembered = await store.allRecords()
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
        switch event {
        case .mounted(let url):
            Log.mount.info("mount event: \(url.lastPathComponent, privacy: .public)")
        case .unmounted(let url):
            Log.mount.info("unmount event: \(url.lastPathComponent, privacy: .public)")
        }
        await refresh()

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
            case .nothingToDo(let reason):
                Log.mount.debug("smart-silent: nothing to do for \(info.name, privacy: .public) — \(String(describing: reason), privacy: .public)")
            case .applied(let hash):
                Log.mount.info("smart-silent: applied cached icon to \(info.name, privacy: .public) (hash \(hash.prefix(12), privacy: .public)…)")
                if let store, let identity = info.identity,
                   var record = await store.record(for: identity) {
                    record.lastApplied = Date()
                    record.lastAppliedHash = hash
                    record.lastSeen = Date()
                    try await store.upsert(record)
                    self.remembered = await store.allRecords()
                }
            case .conflict(let conflict):
                Log.mount.notice("smart-silent: CONFLICT on \(info.name, privacy: .public) — expected \(conflict.expectedHash.prefix(12), privacy: .public)…, found \(conflict.currentHash?.prefix(12) ?? "nil", privacy: .public)…")
                if !pendingConflicts.contains(where: { $0.identity == conflict.identity }) {
                    pendingConflicts.append(conflict)
                }
                await ConflictNotifier.shared.postConflict(conflict)
            }
        } catch {
            Log.mount.error("smart-silent failed for \(info.name, privacy: .public): \(error.localizedDescription)")
            lastError = "Sigil couldn't automatically re-apply the icon on '\(info.name)'. \(error.localizedDescription)"
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
