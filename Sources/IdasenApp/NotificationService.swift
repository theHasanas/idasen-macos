import Foundation
import Combine
import UserNotifications

/// Wraps `UNUserNotificationCenter` and falls back to an in-app banner when
/// notifications are unavailable (or the app is running unbundled).
@MainActor
final class NotificationService: NSObject, ObservableObject {
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    static let arrivalCategory = "IDASEN_ARRIVAL"

    private var isAuthorized = false
    private var center: UNUserNotificationCenter? {
        Bundle.main.bundleIdentifier == nil ? nil : UNUserNotificationCenter.current()
    }

    func configure() {
        guard let center else { return }
        center.delegate = self
        center.setNotificationCategories(Self.categories)
        refreshAuthorization()
    }

    func updateAuthorization() {
        refreshAuthorization()
    }

    func refreshAuthorization() {
        guard let center else {
            isAuthorized = false
            return
        }
        center.getNotificationSettings { settings in
            let status = settings.authorizationStatus
            let authorized = settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional
            Task { @MainActor in
                self.authorizationStatus = status
                self.isAuthorized = authorized
            }
        }
    }

    func requestAuthorization() {
        guard let center else { return }
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            Task { @MainActor in
                self.isAuthorized = granted
                self.refreshAuthorization()
            }
        }
    }

    func postArrival(heightText: String) {
        let content = UNMutableNotificationContent()
        content.title = "Desk in position"
        content.body = "The desk reached \(heightText)."
        content.categoryIdentifier = Self.arrivalCategory
        deliver(content, identifier: "idasen.arrival.\(UUID().uuidString)")
    }

    private func deliver(_ content: UNMutableNotificationContent, identifier: String) {
        guard let center, isAuthorized else { return }
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        center.add(request)
    }

    private static var categories: Set<UNNotificationCategory> {
        let arrival = UNNotificationCategory(
            identifier: arrivalCategory,
            actions: [],
            intentIdentifiers: [],
            options: []
        )
        return [arrival]
    }
}

extension NotificationService: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
