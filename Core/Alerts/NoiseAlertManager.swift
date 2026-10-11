import Foundation
import UserNotifications

final class NoiseAlertManager {
    private var wasAboveThreshold = false

    func evaluate(level: Double, threshold: Double, enabled: Bool) {
        guard enabled else { wasAboveThreshold = false; return }
        let isAboveThreshold = level >= threshold
        defer { wasAboveThreshold = isAboveThreshold }
        guard isAboveThreshold, !wasAboveThreshold else { return }

        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { return }
            let content = UNMutableNotificationContent()
            content.title = "Noise level exceeded"
            content.body = String(format: "Current level %.1f dBFS is above your %.1f dBFS alert.", level, threshold)
            content.sound = .default
            let request = UNNotificationRequest(identifier: "soundmeter.noise-alert", content: content, trigger: nil)
            center.add(request)
        }
    }

    func requestPermissionIfNeeded() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }
}
