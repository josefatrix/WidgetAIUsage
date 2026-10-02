import SwiftUI

@main
struct UsageBarApp: App {
    @StateObject private var store = UsageStore()

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
        if CommandLine.arguments.contains("--check") {
            Task {
                let providers: [any UsageProvider] = [CodexProvider(), ClaudeProvider(), GeminiProvider()]
                for p in providers {
                    switch await p.fetch() {
                    case .success(let s):
                        let bars = s.limits.map { "\($0.label) \(Int($0.percent))%" }.joined(separator: ", ")
                        var cost = s.cost.map {
                            String(format: "session $%.2f · 30d $%.2f", $0.sessionCostUSD, $0.last30DaysCostUSD)
                        } ?? "no cost data"
                        if s.costUnit == .requests {
                            cost = "30d \(Int(s.history.reduce(0) { $0 + $1.costUSD })) requests"
                        }
                        if let x = s.extraUsage {
                            cost += String(format: " · extra $%.2f/$%.2f", x.usedUSD, x.limitUSD)
                        }
                        print("\(p.id.rawValue): \(s.account ?? "?") [\(s.plan ?? "?")] — \(bars) — \(cost)")
                        if let w = s.warning { print("  warning: \(w)") }
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
            Image(nsImage: store.menuBarImage)
        }
        .menuBarExtraStyle(.window)
    }
}
