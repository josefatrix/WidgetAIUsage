import Foundation
import SwiftUI
import UsageBarCore

enum ProviderState {
    case loading
    case ready(ProviderSnapshot)
    case failed(String, last: ProviderSnapshot?)

    var snapshot: ProviderSnapshot? {
        switch self {
        case .ready(let s): return s
        case .failed(_, let last): return last
        case .loading: return nil
        }
    }

    var errorMessage: String? {
        if case .failed(let msg, _) = self { return msg }
        return nil
    }
}

@MainActor
final class UsageStore: ObservableObject {
    @Published var states: [ProviderID: ProviderState] = [.claude: .loading, .codex: .loading,
                                                          .gemini: .loading, .chatgpt: .loading]
    /// Providers with a fetch still running. Tracked per provider so one slow or stuck
    /// source (a Keychain prompt, a hung request) can never block the others.
    @Published private(set) var inFlight: Set<ProviderID> = []
    var isRefreshing: Bool { !inFlight.isEmpty }
    @Published var selected: ProviderID {
        didSet { UserDefaults.standard.set(selected.rawValue, forKey: "selectedProvider") }
    }
    @Published var refreshIntervalMinutes: Int {
        didSet {
            UserDefaults.standard.set(refreshIntervalMinutes, forKey: "refreshIntervalMinutes")
            startPolling()
        }
    }
    @Published var menuBarStyle: MenuBarStyle {
        didSet { UserDefaults.standard.set(menuBarStyle.rawValue, forKey: "menuBarStyle") }
    }
    @Published var popoverStyle: PopoverStyle {
        didSet { UserDefaults.standard.set(popoverStyle.rawValue, forKey: "popoverStyle") }
    }
    /// Which provider the menu bar icon tracks; nil follows the open tab. Following
    /// the tab meant peeking at Gemini (no quota) blanked the icon, so the default
    /// is pinned to Claude.
    @Published var menuBarProvider: ProviderID? {
        didSet { UserDefaults.standard.set(menuBarProvider?.rawValue ?? "", forKey: "menuBarProvider") }
    }
    @Published var notificationsEnabled: Bool {
        didSet { UserDefaults.standard.set(notificationsEnabled, forKey: "notificationsEnabled") }
    }

    private let providers: [any UsageProvider] = Providers.all()
    private var timer: Timer?
    private let notifier = Notifier()
    private var lastRefreshStarted = Date.distantPast
    /// Menu bar apps get App Nap'd, which can stall the polling timer for long stretches.
    private let pollingActivity = ProcessInfo.processInfo.beginActivity(
        options: .userInitiatedAllowingIdleSystemSleep, reason: "Polling AI usage limits")

    init() {
        let saved = UserDefaults.standard.string(forKey: "selectedProvider")
        selected = saved.flatMap(ProviderID.init(rawValue:)) ?? .claude
        let interval = UserDefaults.standard.integer(forKey: "refreshIntervalMinutes")
        refreshIntervalMinutes = interval > 0 ? interval : 5
        let style = UserDefaults.standard.string(forKey: "menuBarStyle")
        // .ring is the new default; a saved "percent" from the old bar-only set no
        // longer parses and falls through to it, which is the intent.
        menuBarStyle = style.flatMap(MenuBarStyle.init(rawValue:)) ?? .ring
        let popover = UserDefaults.standard.string(forKey: "popoverStyle")
        popoverStyle = popover.flatMap(PopoverStyle.init(rawValue:)) ?? .dial
        if let pinned = UserDefaults.standard.string(forKey: "menuBarProvider") {
            menuBarProvider = ProviderID(rawValue: pinned)  // "" = follow the open tab
        } else {
            menuBarProvider = .claude
        }
        notificationsEnabled = UserDefaults.standard.object(forKey: "notificationsEnabled") as? Bool ?? true
        startPolling()
        Task { await refreshAll() }
    }

    var selectedState: ProviderState { states[selected] ?? .loading }

    /// The two windows the dial draws for a provider — tightest outside.
    func rings(for id: ProviderID) -> (outer: LimitBar?, inner: LimitBar?) {
        guard let snap = states[id]?.snapshot else { return (nil, nil) }
        return UsageWindow.rings(limits: snap.limits, now: Date())
    }

    /// The bar the menu bar icon reflects: the current session, the same thing the
    /// dial's outer ring shows. Crossing a critical threshold on any other limit is
    /// already handled by the notifier, so the icon does not need to shout for it.
    func sessionBar(for id: ProviderID) -> LimitBar? {
        rings(for: id).outer
    }

    var menuBarImage: NSImage {
        MenuBarLabel.image(style: menuBarStyle,
                           selected: rings(for: menuBarProvider ?? selected),
                           claude: sessionBar(for: .claude),
                           codex: sessionBar(for: .codex))
    }

    /// What VoiceOver reads for the menu bar icon, which is otherwise just a picture.
    var menuBarAccessibilityLabel: String {
        let id = menuBarProvider ?? selected
        guard let bar = sessionBar(for: id) else { return "UsageBar, \(id.displayName): no limit data" }
        let stale = bar.severity == "stale" ? ", out of date" : ""
        return "UsageBar, \(id.displayName) \(bar.label): \(Int(bar.percent.rounded())) percent used\(stale)"
    }

    func refreshAll() async {
        lastRefreshStarted = Date()
        await withTaskGroup(of: Void.self) { group in
            for provider in providers where !inFlight.contains(provider.id) {
                inFlight.insert(provider.id)
                group.addTask { await self.refresh(provider) }
            }
        }
    }

    /// Refresh-on-open. The popover can open many times a minute, so skip if a refresh just ran.
    func refreshIfStale() {
        guard Date().timeIntervalSince(lastRefreshStarted) > 15 else { return }
        Task { await refreshAll() }
    }

    private func refresh(_ provider: any UsageProvider) async {
        defer { inFlight.remove(provider.id) }
        switch await provider.fetch() {
        case .success(let snap):
            states[provider.id] = .ready(snap)
            if notificationsEnabled { notifier.check(provider: provider.id, limits: snap.limits) }
        case .failure(let err):
            states[provider.id] = .failed(err.message, last: states[provider.id]?.snapshot)
        }
    }

    func startPolling() {
        timer?.invalidate()
        let seconds = TimeInterval(refreshIntervalMinutes * 60)
        timer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshAll() }
        }
    }
}
