import SwiftUI

@main
struct UsageBarApp: App {
    @StateObject private var store = UsageStore()

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
        if CommandLine.arguments.contains("--check") {
            Task {
                let providers: [any UsageProvider] = [CodexProvider(), ClaudeProvider()]
                for p in providers {
                    switch await p.fetch() {
                    case .success(let s):
                        let bars = s.limits.map { "\($0.label) \(Int($0.percent))%" }.joined(separator: ", ")
                        let cost = s.cost.map {
                            String(format: "session $%.2f · 30d $%.2f", $0.sessionCostUSD, $0.last30DaysCostUSD)
                        } ?? "no cost data"
                        print("\(p.id.rawValue): \(s.account ?? "?") [\(s.plan ?? "?")] — \(bars) — \(cost)")
                    case .failure(let e):
                        print("\(p.id.rawValue): FAILED — \(e.message)")
                    }
                }
                exit(0)
            }
        }
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environmentObject(store)
        } label: {
            Image(nsImage: MenuBarLabel.barImage(percent: store.menuBarPercent))
        }
        .menuBarExtraStyle(.window)
    }
}
