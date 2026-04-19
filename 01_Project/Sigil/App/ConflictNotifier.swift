import Foundation
import UserNotifications

/// Surfaces `SmartSilentApplier` conflicts to the user via
/// `UNUserNotificationCenter`. User picks one of three actions:
/// - **Use Sigil icon** — overwrite the on-disk icon, update stored hash.
/// - **Keep current** — update Sigil's stored hash to match the on-disk icon.
/// - **Forget volume** — delete Sigil's record + cached files for this volume.
///
/// If notification authorization is denied, conflicts are collected in
/// `AppState.pendingConflicts` and surfaced as an in-app banner instead.
@MainActor
final class ConflictNotifier: NSObject {

    static let shared = ConflictNotifier()

    static let categoryID = "com.lucesumbrarum.sigil.conflict"
    static let actionUseSigil = "USE_SIGIL_ICON"
    static let actionKeepCurrent = "KEEP_CURRENT"
    static let actionForget = "FORGET_VOLUME"

    private weak var appState: AppState?
    private var categoriesRegistered = false

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    /// Wire into AppState so action callbacks can mutate app state.
    func attach(to appState: AppState) {
        self.appState = appState
    }

    /// Present a notification for a conflict. If authorization is denied,
    /// does nothing — the conflict should already be in `AppState.pendingConflicts`
    /// so the in-app banner can render.
    func postConflict(_ conflict: SmartSilentApplier.Outcome.Conflict) async {
        registerCategoriesIfNeeded()
        guard await requestAuthorizationIfNeeded() else { return }

        let content = UNMutableNotificationContent()
        content.title = "Icon conflict on '\(conflict.volumeName)'"
        content.body = "The icon currently on this volume differs from the one Sigil last wrote. Choose how to resolve it."
        content.categoryIdentifier = Self.categoryID
        content.userInfo = ["uuid": conflict.identity.raw]
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "conflict-\(conflict.identity.raw)",  // stable ID: replaces any previous conflict for same volume
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Authorization & setup

    private func registerCategoriesIfNeeded() {
        guard !categoriesRegistered else { return }
        let useSigil = UNNotificationAction(
            identifier: Self.actionUseSigil, title: "Use Sigil icon", options: []
        )
        let keepCurrent = UNNotificationAction(
            identifier: Self.actionKeepCurrent, title: "Keep current", options: []
        )
        let forget = UNNotificationAction(
            identifier: Self.actionForget, title: "Forget volume", options: [.destructive]
        )
        let category = UNNotificationCategory(
            identifier: Self.categoryID,
            actions: [useSigil, keepCurrent, forget],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
        categoriesRegistered = true
    }

    /// Returns whether we currently have (or just obtained) authorization to post.
    private func requestAuthorizationIfNeeded() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        @unknown default:
            return false
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension ConflictNotifier: UNUserNotificationCenterDelegate {

    /// Show banners even when Sigil is in the foreground (otherwise silent).
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let uuid = response.notification.request.content.userInfo["uuid"] as? String else {
            return
        }
        let identity = VolumeIdentity(uuid)
        let action = response.actionIdentifier
        await MainActor.run {
            Task { [weak self] in
                await self?.route(action: action, identity: identity)
            }
        }
    }

    private func route(action: String, identity: VolumeIdentity) async {
        guard let appState else { return }
        switch action {
        case Self.actionUseSigil:
            try? await appState.resolveConflictUseSigil(identity: identity)
        case Self.actionKeepCurrent:
            try? await appState.resolveConflictKeepCurrent(identity: identity)
        case Self.actionForget:
            try? await appState.forget(identity: identity)
        default:
            break  // Default action (tap without choosing): leave conflict pending.
        }
    }
}
