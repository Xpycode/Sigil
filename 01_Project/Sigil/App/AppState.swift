import Foundation
import SwiftUI

/// Top-level orchestrator. Owns the persistent store, enumerator, and watcher;
/// exposes the data the UI binds to.
///
/// Wave 3 scope: load store, scan + watch volumes. The smart-silent reapply
/// that kicks in on mount is added in Wave 6.
@MainActor
@Observable
final class AppState {

    // MARK: - Published state

    private(set) var mounted: [VolumeInfo] = []
    private(set) var remembered: [VolumeRecord] = []
    var selectedID: String?

    /// Toolbar toggle: when `true`, the sidebar also lists boot/system/DMG volumes.
    var showAllVolumes: Bool = false {
        didSet {
            guard oldValue != showAllVolumes else { return }
            Task { await refresh() }
        }
    }

    // MARK: - Services

    private var store: VolumeStore?
    private let enumerator = VolumeEnumerator()
    private let watcher = MountWatcher()
    private var streamTask: Task<Void, Never>?

    // MARK: - Lifecycle

    init() {}

    /// Run once at launch (from `.task` in the root view).
    /// Loads the store, snapshots current volumes, starts the mount watcher.
    func bootstrap() async {
        do {
            let store = try VolumeStore()
            self.store = store
            _ = try await store.load()
            self.remembered = await store.allRecords()
        } catch {
            // Wave 8 turns this into a non-blocking warning sheet.
            print("Sigil: failed to load VolumeStore — \(error)")
        }
        await refresh()
        startWatching()
    }

    /// Re-snapshot currently-mounted volumes (filtered per `showAllVolumes`).
    func refresh() async {
        self.mounted = await enumerator.currentVolumes(includeSystem: showAllVolumes)
    }

    // MARK: - Derived

    /// Remembered records that are NOT currently mounted (sidebar's "Remembered" section).
    var rememberedNotMounted: [VolumeRecord] {
        let mountedIDs = Set(mounted.compactMap { $0.identity?.raw })
        return remembered.filter { !mountedIDs.contains($0.identity.raw) }
    }

    /// Currently-selected mounted volume, if any.
    var selectedMounted: VolumeInfo? {
        guard let id = selectedID else { return nil }
        return mounted.first(where: { $0.id == id })
    }

    /// Currently-selected remembered (unmounted) record, if any.
    var selectedRemembered: VolumeRecord? {
        guard let id = selectedID else { return nil }
        return rememberedNotMounted.first(where: { $0.id == id })
    }

    // MARK: - Watcher loop

    private func startWatching() {
        streamTask?.cancel()
        let task = Task { [weak self] in
            guard let self else { return }
            let stream = await self.watcher.events()
            for await _ in stream {
                // Wave 3: any mount/unmount triggers a re-snapshot.
                // Wave 6 will inspect the event and run smart-silent apply here.
                await self.refresh()
            }
        }
        streamTask = task
    }
}
