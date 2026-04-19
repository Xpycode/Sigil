import Foundation
import AppKit

enum MountEvent: Sendable {
    case mounted(URL)
    case unmounted(URL)
}

/// Bridges `NSWorkspace` mount/unmount notifications to an `AsyncStream`.
/// One watcher per app; call `events()` once and `for await` on the stream.
/// Observers are torn down automatically when the stream is cancelled or the
/// continuation terminates.
actor MountWatcher {

    private var observers: [NSObjectProtocol] = []

    /// Returns an `AsyncStream` of mount/unmount events. Calling more than
    /// once will install duplicate observers — caller is expected to retain
    /// a single stream for the lifetime of the watcher.
    func events() -> AsyncStream<MountEvent> {
        let (stream, continuation) = AsyncStream<MountEvent>.makeStream()
        let nc = NSWorkspace.shared.notificationCenter

        let mountObs = nc.addObserver(
            forName: NSWorkspace.didMountNotification,
            object: nil,
            queue: .main
        ) { note in
            if let url = Self.volumeURL(from: note) {
                continuation.yield(.mounted(url))
            }
        }

        let unmountObs = nc.addObserver(
            forName: NSWorkspace.didUnmountNotification,
            object: nil,
            queue: .main
        ) { note in
            if let url = Self.volumeURL(from: note) {
                continuation.yield(.unmounted(url))
            }
        }

        observers.append(contentsOf: [mountObs, unmountObs])

        // Tear down when the consumer cancels the stream.
        let observersToCleanup = observers
        continuation.onTermination = { _ in
            for obs in observersToCleanup {
                nc.removeObserver(obs)
            }
        }

        return stream
    }

    /// Manual teardown if the watcher is being released without the stream
    /// being consumed to completion.
    func stop() {
        let nc = NSWorkspace.shared.notificationCenter
        for obs in observers { nc.removeObserver(obs) }
        observers.removeAll()
    }

    private static func volumeURL(from note: Notification) -> URL? {
        // `NSWorkspace.didMountNotification` userInfo carries the mount URL
        // under the key `NSWorkspaceVolumeURLKey` (string-typed in older SDKs).
        if let url = note.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL {
            return url
        }
        if let url = note.userInfo?["NSWorkspaceVolumeURLKey"] as? URL {
            return url
        }
        return nil
    }
}
