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
    @Published var isRefreshing = false
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

    private let providers: [any UsageProvider] = Providers.all()
    private var timer: Timer?
    private let notifier = Notifier()

    init() {
        let saved = UserDefaults.standard.string(forKey: "selectedProvider")
        selected = saved.flatMap(ProviderID.init(rawValue:)) ?? .claude
        let interval = UserDefaults.standard.integer(forKey: "refreshIntervalMinutes")
        refreshIntervalMinutes = interval > 0 ? interval : 5
        let style = UserDefaults.standard.string(forKey: "menuBarStyle")
        // .ring is the new default; a saved "percent" from the old bar-only set no
        // longer parses and falls through to it, which is the intent.
        menuBarStyle = style.flatMap(MenuBarStyle.init(rawValue:)) ?? .ring
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
                           selected: rings(for: selected),
                           claude: sessionBar(for: .claude),
                           codex: sessionBar(for: .codex))
    }

    func refreshAll() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        await withTaskGroup(of: (ProviderID, Result<ProviderSnapshot, FetchFailure>).self) { group in
            for provider in providers {
                group.addTask { (provider.id, await provider.fetch()) }
            }
            for await (id, result) in group {
                switch result {
                case .success(let snap):
                    states[id] = .ready(snap)
                    notifier.check(provider: id, limits: snap.limits)
                case .failure(let err):
                    states[id] = .failed(err.message, last: states[id]?.snapshot)
                }
            }
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
