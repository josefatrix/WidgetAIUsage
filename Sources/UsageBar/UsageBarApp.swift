import SwiftUI
import UsageBarCore

@main
struct UsageBarApp: App {
    @StateObject private var store = UsageStore()

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
        if let i = CommandLine.arguments.firstIndex(of: "--snapshot"),
           CommandLine.arguments.count > i + 1 {
            let dir = CommandLine.arguments[i + 1]
            Task { @MainActor in
                await Self.snapshot(into: dir)
                exit(0)
            }
        } else if CommandLine.arguments.contains("--check") {
            Task {
                let providers = Providers.all()
                for p in providers {
                    switch await p.fetch() {
                    case .success(let s):
                        let bars = s.limits.map { "\($0.label) \(Int($0.percent))%" }.joined(separator: ", ")
                        var cost = s.cost.map {
                            String(format: "session $%.2f · 30d $%.2f", $0.sessionCostUSD, $0.last30DaysCostUSD)
                        } ?? "no cost data"
                        if s.costUnit != .usd {
                            cost = "30d \(Int(s.history.reduce(0) { $0 + $1.costUSD })) \(s.costUnit.pluralNoun)"
                        }
                        if let x = s.extraUsage {
                            cost += String(format: " · extra $%.2f/$%.2f", x.usedUSD, x.limitUSD)
                        }
                        print("\(p.id.rawValue): \(s.account ?? "?") [\(s.plan ?? "?")] — \(bars) — \(cost)")
                        if let note = s.limitsNote { print("    note: \(note)") }
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

    /// Renders the popover to PNG for every provider, in both appearances, plus
    /// the menu bar icons. Not a test fixture — it draws the REAL views against
    /// the REAL local data, which is the only way to check a menu-bar UI without
    /// a human holding a camera.
    @MainActor
    private static func snapshot(into dir: String) async {
        let store = UsageStore()
        await store.refreshAll()
        let fm = FileManager.default
        try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)

        func write(_ image: NSImage?, _ name: String) {
            guard let image, let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else {
                print("  failed: \(name)"); return
            }
            let url = URL(fileURLWithPath: dir).appendingPathComponent(name)
            try? png.write(to: url)
            print("  \(name)  \(Int(image.size.width))x\(Int(image.size.height))")
        }

        for style in PopoverStyle.allCases {
        for scheme in [ColorScheme.dark, .light] {
            let suffix = "\(style.rawValue)-\(scheme == .dark ? "dark" : "light")"
            store.popoverStyle = style
            for id in ProviderID.allCases {
                store.selected = id
                let view = PopoverView()
                    .environmentObject(store)
                    .environment(\.colorScheme, scheme)
                    // The real popover floats on the system's glass; approximate it
                    // so translucent fills are judged against something, not white.
                    .background(scheme == .dark ? Color(white: 0.13) : Color(white: 0.95))
                let renderer = ImageRenderer(content: view)
                renderer.scale = 2
                write(renderer.nsImage, "popover-\(id.rawValue)-\(suffix).png")
            }
        }
        }
        store.popoverStyle = .dial

        // Colour ramp: the one thing you cannot check by reading the code, because
        // it depends on LimitLevel, the accent colour and the appearance at once.
        let ramp: [(Double, String?)] = [(5, "normal"), (40, "normal"), (62, "normal"),
                                         (70, nil), (88, "normal"), (100, "critical"),
                                         (36, "stale")]
        for scheme in [ColorScheme.dark, .light] {
            let suffix = scheme == .dark ? "dark" : "light"
            let strip = HStack(spacing: 10) {
                ForEach(Array(ramp.enumerated()), id: \.offset) { _, item in
                    VStack(spacing: 5) {
                        MiniRing(outer: item.0, inner: nil,
                                 color: limitColor(percent: item.0, severity: item.1),
                                 dimmed: item.1 == "stale")
                        Text("\(Int(item.0))%")
                            .font(.system(size: 9, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        Text(item.1 ?? "none")
                            .font(.system(size: 7))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(14)
            .environment(\.colorScheme, scheme)
            .background(scheme == .dark ? Color(white: 0.13) : Color(white: 0.95))
            let r = ImageRenderer(content: strip)
            r.scale = 3
            write(r.nsImage, "ramp-\(suffix).png")
        }

        for style in MenuBarStyle.allCases {
            store.selected = .claude
            write(MenuBarLabel.image(style: style,
                                     selected: store.rings(for: .claude),
                                     claude: store.sessionBar(for: .claude),
                                     codex: store.sessionBar(for: .codex)),
                  "menubar-\(style.rawValue).png")
        }
        print("snapshots written to \(dir)")
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
