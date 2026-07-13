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

    private let providers: [any UsageProvider] = [CodexProvider(), ClaudeProvider(), GeminiProvider()]
    private var timer: Timer?
    private let notifier = Notifier()

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
