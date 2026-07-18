import SwiftUI
import UsageBarCore

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
                        let now = Date()
                        for b in s.limits {
                            if let resets = b.resetsAt, let w = b.windowMinutes,
                               let f = UsageBarCore.Projection.forecast(percent: b.percent, resetsAt: resets, windowMinutes: w, now: now) {
                                if f.willHitBeforeReset {
                                    let secs = max(0, Int(f.hitDate.timeIntervalSince(now)))
                                    print("    ⚠︎ \(b.label): on pace to hit limit in \(secs/3600)h \((secs%3600)/60)m")
                                } else {
                                    print("    ~ \(b.label): at this pace ≈\(Int(f.projectedPercentAtReset.rounded()))% by reset")
                                }
                            }
                        }
                        if !s.modelBreakdown.isEmpty {
                            print("    by model: " + s.modelBreakdown.prefix(4).map { String(format: "%@ $%.2f", $0.model, $0.costUSD) }.joined(separator: ", "))
                        }
                        if !s.projectBreakdown.isEmpty {
                            print("    by project: " + s.projectBreakdown.map { String(format: "%@ $%.2f", $0.project, $0.costUSD) }.joined(separator: ", "))
                        }
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
