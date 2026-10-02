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
    @Published var states: [ProviderID: ProviderState] = [.claude: .loading, .codex: .loading, .gemini: .loading]
    /// Providers with a fetch still running. Tracked per provider so one slow or stuck
    /// source can never block the others from refreshing.
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

    private let providers: [any UsageProvider] = [CodexProvider(), ClaudeProvider(), GeminiProvider()]
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
        menuBarStyle = style.flatMap(MenuBarStyle.init(rawValue:)) ?? .bar
        startPolling()
        Task { await refreshAll() }
    }

    var selectedState: ProviderState { states[selected] ?? .loading }

    func sessionBar(for id: ProviderID) -> LimitBar? {
        guard let snap = states[id]?.snapshot else { return nil }
        return snap.limits.first { $0.label == "Session" } ?? snap.limits.first
    }

    var menuBarImage: NSImage {
        MenuBarLabel.image(style: menuBarStyle,
                           selected: sessionBar(for: selected),
                           claude: sessionBar(for: .claude),
                           codex: sessionBar(for: .codex))
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
            notifier.check(provider: provider.id, limits: snap.limits)
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
