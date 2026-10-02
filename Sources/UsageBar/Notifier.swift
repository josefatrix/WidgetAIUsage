import Foundation
@preconcurrency import UserNotifications
import UsageBarCore

/// Fires a macOS notification once per (provider, bar, reset window, tier) when
/// usage crosses 80% / 95%. Re-arms automatically when the window's reset date changes.
@MainActor
final class Notifier {
    private var notified: Set<String> = []

    func check(provider: ProviderID, limits: [LimitBar]) {
        // UNUserNotificationCenter crashes in bare (non-bundled) dev binaries.
        guard Bundle.main.bundleIdentifier != nil else { return }
        let now = Date()
        // A percentage left over from a window that already reset can't cross a
        // threshold today — alerting on it would fire off weeks-old data.
        for bar in limits where !bar.hasExpired(now: now) {
            for tier in [95.0, 80.0] where bar.percent >= tier {
                let window = bar.resetsAt.map { String(Int($0.timeIntervalSince1970)) } ?? "none"
                let key = "\(provider.rawValue)|\(bar.label)|\(window)|\(Int(tier))"
                if !notified.contains(key) {
                    notified.insert(key)
                    let body = bar.resetsAt.map { Format.resetsIn($0) } ?? ""
                    send(title: "\(provider.displayName): \(bar.label) at \(Int(bar.percent.rounded()))%",
                         body: body)
                }
                break // only the highest crossed tier per bar
            }
        }
    }

    private func send(title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            center.add(UNNotificationRequest(identifier: UUID().uuidString,
                                             content: content, trigger: nil))
        }
    }
}
