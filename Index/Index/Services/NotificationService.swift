import Foundation
import UserNotifications
import UIKit

/// Owns the iOS local-notification surface: permission requests,
/// scheduling, and tap-routing. Instantiated once in IndexApp and
/// passed to HealthKitService at construction so the HK observer
/// paths can call `scheduleNew*` directly after a genuinely-new
/// insert.
///
/// Tap routing: the delegate posts a `Notification.Name` broadcast
/// with `destinationTab` in userInfo. ContentView listens via
/// `.onReceive` and updates its `selectedTab` state. If the app is
/// already in `.active` foreground when the user taps a banner, the
/// route post is skipped — yanking the user across tabs while
/// they're mid-task is worse than no-op.
@MainActor
@Observable
final class NotificationService: NSObject, UNUserNotificationCenterDelegate, Sendable {

    /// App-lifetime singleton. The same instance backs IndexApp's
    /// `@State` injection AND HealthKitService's construction-time
    /// dependency, so the observer paths and the UI agree on the
    /// single registered `UNUserNotificationCenterDelegate`. The
    /// service holds no per-launch state beyond the delegate
    /// registration, so a singleton is safe.
    static let shared = NotificationService()

    /// Broadcast posted on tap. `userInfo["destinationTab"]` is
    /// `"body"` or `"fitness"` matching `ContentView.TabSlot`.
    static let tabRouteNotificationName = Notification.Name("IndexNotificationTabRoute")
    static let tabRouteUserInfoKey = "destinationTab"

    enum PermissionError: Error {
        /// User denied at the iOS prompt OR has previously denied and
        /// must re-enable from iOS Settings.
        case denied
        /// Authorization request threw — surface to caller so they can
        /// log it; the toggle stays off.
        case requestFailed(Error)
    }

    override init() {
        super.init()
        // Setting the delegate at init time (before any tap can occur)
        // is required by `UNUserNotificationCenterDelegate`. Done
        // unconditionally — having a delegate registered when zero
        // notifications are scheduled is harmless.
        UNUserNotificationCenter.current().delegate = self
    }

    // MARK: - Permission

    /// Requests notification permission and returns true if granted.
    /// Throws `.denied` when the user denies (so callers can surface
    /// a single "Enable in iOS Settings" alert). Idempotent — calling
    /// after a prior grant is a fast no-op via the system cache.
    func requestPermission() async throws {
        let center = UNUserNotificationCenter.current()
        let current = await center.notificationSettings()
        switch current.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return
        case .denied:
            throw PermissionError.denied
        case .notDetermined:
            break
        @unknown default:
            break
        }
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            if !granted { throw PermissionError.denied }
        } catch let e as PermissionError {
            throw e
        } catch {
            throw PermissionError.requestFailed(error)
        }
    }

    /// Read-only check used by HK observer paths before scheduling.
    /// Falls through to false on `.denied` / `.notDetermined` so a
    /// background fire that arrives before the user has been prompted
    /// stays silent.
    func isAuthorized() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        case .denied, .notDetermined:               return false
        @unknown default:                           return false
        }
    }

    // MARK: - Scheduling

    /// Insight-style notification for a freshly-inserted workout.
    /// Caller is responsible for the profile-flag gate. Body falls
    /// back gracefully when kcal / avgHR are absent (manual swim logs,
    /// strength sessions without HR samples).
    func scheduleNewWorkout(
        typeLabel: String,
        durationMinutes: Int,
        kcal: Double?,
        avgHR: Int?
    ) {
        let content = UNMutableNotificationContent()
        content.title = "New workout"
        content.body = Self.workoutBody(
            typeLabel: typeLabel,
            durationMinutes: durationMinutes,
            kcal: kcal,
            avgHR: avgHR
        )
        content.sound = .default
        content.userInfo = [Self.tabRouteUserInfoKey: "fitness"]
        schedule(content: content, idPrefix: "workout")
    }

    /// Insight-style notification for a freshly-inserted weigh-in.
    /// Delta omitted when no prior WeightEntry exists.
    func scheduleNewWeight(weightKg: Double, deltaKg: Double?) {
        let content = UNMutableNotificationContent()
        content.title = "New weigh-in"
        content.body = Self.weightBody(weightKg: weightKg, deltaKg: deltaKg)
        content.sound = .default
        content.userInfo = [Self.tabRouteUserInfoKey: "body"]
        schedule(content: content, idPrefix: "weight")
    }

    /// Schedules with a 1-second trigger so the system delivers
    /// even when the app is active (the spec wants "fires
    /// immediately"). Background HK delivery wakes the app, the
    /// notification queues, and the system displays it once
    /// `application(_:didReceiveRemoteNotification:)`-equivalent
    /// completes.
    private func schedule(content: UNNotificationContent, idPrefix: String) {
        let id = "\(idPrefix).\(UUID().uuidString)"
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("[NotificationService] schedule(\(idPrefix)) failed: \(error)")
            }
        }
    }

    // MARK: - Body composition helpers (pure-static, unit-test-friendly)

    static func workoutBody(
        typeLabel: String,
        durationMinutes: Int,
        kcal: Double?,
        avgHR: Int?
    ) -> String {
        var segments = ["\(typeLabel), \(durationMinutes)m"]
        if let kcal { segments.append("\(Int(kcal.rounded())) kcal") }
        if let avgHR, avgHR > 0 { segments.append("\(avgHR) avg BPM") }
        return segments.joined(separator: " · ")
    }

    static func weightBody(weightKg: Double, deltaKg: Double?) -> String {
        let kgStr = formatKg(weightKg)
        guard let deltaKg else { return "\(kgStr) kg" }
        let sign = deltaKg >= 0 ? "+" : "-"
        let absDelta = String(format: "%.1f", abs(deltaKg))
        return "\(kgStr) kg (\(sign)\(absDelta) from previous)"
    }

    private static func formatKg(_ kg: Double) -> String {
        kg == floor(kg) ? "\(Int(kg))" : String(format: "%.1f", kg)
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Foreground presentation. iOS would suppress the banner by
    /// default while the app is active; explicitly request banner +
    /// sound so the user actually sees the alert.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    /// Tap handling. When the app was NOT active at tap time (cold
    /// launch from notification, or background resume), post the tab-
    /// route broadcast that ContentView subscribes to. When already
    /// active, skip — the user is mid-task and shouldn't be yanked
    /// across tabs.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let tab = userInfo[Self.tabRouteUserInfoKey] as? String
        Task { @MainActor in
            let wasActive = UIApplication.shared.applicationState == .active
            if !wasActive, let tab {
                NotificationCenter.default.post(
                    name: Self.tabRouteNotificationName,
                    object: nil,
                    userInfo: [Self.tabRouteUserInfoKey: tab]
                )
            }
            completionHandler()
        }
    }
}
