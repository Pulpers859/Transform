import Foundation
import UserNotifications

/// The system side of the rest-over alert. The rules (when to arm, when to clear) are in
/// `RestEndAlerts`, which is headless and tested; this file only talks to iOS and is not
/// covered by a test.
///
/// Local notifications need the user's permission and no entitlement or push setup, so they
/// work in a sideloaded build. Permission is asked the first time a rest is armed, which is
/// the moment the question makes sense.
extension RestEndAlerts {
    static let shared = RestEndAlerts(center: RestEndNotificationCenter())
}

final class RestEndNotificationCenter: RestEndAlertCenter {
    /// Bumped on every schedule and cancel. Permission and `add` are asynchronous, so a cancel
    /// can land while a schedule is still in flight; the ticket check stops that schedule from
    /// arming an alert for a rest that was already paused or reset.
    private var tickets: [String: Int] = [:]

    func schedule(id: String, title: String, body: String, after seconds: TimeInterval) {
        let ticket = (tickets[id] ?? 0) + 1
        tickets[id] = ticket

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, seconds), repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)

        Task { @MainActor in
            let center = UNUserNotificationCenter.current()
            let status = await center.notificationSettings().authorizationStatus
            var allowed = status == .authorized || status == .provisional || status == .ephemeral
            if status == .notDetermined {
                allowed = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
            }
            guard allowed, self.tickets[id] == ticket else { return }
            try? await center.add(request)
            // A cancel that arrived during `add` found nothing to remove; remove it now.
            if self.tickets[id] != ticket {
                center.removePendingNotificationRequests(withIdentifiers: [id])
            }
        }
    }

    func cancel(ids: [String]) {
        for id in ids { tickets[id] = (tickets[id] ?? 0) + 1 }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }
}

/// Decides whether a rest-over alert shows while the app is open. iOS asks this only when the
/// app is in the foreground; with the phone locked it delivers the alert itself, and forwards
/// it to a paired Apple Watch.
nonisolated final class RestEndNotificationDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = RestEndNotificationDelegate()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let id = notification.request.identifier
        return await MainActor.run {
            RestEndAlerts.shared.delivered(id: id)
            return RestEndAlerts.shared.shouldPresentWhileAppIsOpen(id: id) ? [.banner, .list, .sound] : []
        }
    }
}
