import SwiftUI
import UsageBarCore

struct PopoverView: View {
    @EnvironmentObject var store: UsageStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showHistory = false
    @State private var showSettings = false
    @State private var showModels = false
    @State private var showProjects = false

    /// Critically damped spring — Apple's default UI motion (damping 1.0).
    static let uiSpring = Animation.spring(duration: 0.3, bounce: 0)

    /// Settings slides in from the trailing edge and leaves the same way
    /// (spatial consistency); reduced motion gets a plain cross-fade.
    private var settingsTransition: AnyTransition {
        reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity)
    }
    private var contentTransition: AnyTransition {
        reduceMotion ? .opacity : .move(edge: .leading).combined(with: .opacity)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(alignment: .leading, spacing: 12) {
                ProviderSelector()

                if showSettings {
                    SettingsView(isPresented: $showSettings)
                        .transition(settingsTransition)
                } else {
                    providerContent(now: context.date)
                        .transition(contentTransition)
                }
            }
            .padding(14)
            .frame(width: 320)
            .clipped()
        }
        .onAppear {
            Task { await store.refreshAll() }
        }
    }

    @ViewBuilder
    private func providerContent(now: Date) -> some View {
        let state = store.selectedState

        header(state, now: now)

        if let error = state.errorMessage {
            Label(error, systemImage: "exclamationmark.triangle")
                .font(.system(size: 11))
                .foregroundStyle(.orange)
                .lineLimit(2)
        }

        if let snap = state.snapshot {
            if store.selected == .gemini && snap.limits.isEmpty {
                Text("Gemini doesn't expose quota limits locally — showing activity only.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            if !snap.limits.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(snap.limits) { limit in
                        LimitBarView(limit: limit, now: now)
                    }
                }
            }

            if let cost = snap.cost {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        statTile(label: "This session",
                                 value: Format.usd(cost.sessionCostUSD),
                                 sub: Format.tokens(cost.sessionTokens))
                        statTile(label: "Last 30 days",
                                 value: Format.usd(cost.last30DaysCostUSD),
                                 sub: "estimated")
                    }
                    if let trend = todayTrend(snap) {
                        HStack(spacing: 6) {
                            Text("Today \(Format.usd(trend.today))")
                                .font(.system(size: 11))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                            Label("\(abs(Int(trend.deltaPct.rounded())))% vs avg",
                                  systemImage: trend.deltaPct >= 0 ? "arrow.up.right" : "arrow.down.right")
                                .font(.system(size: 10, weight: .medium))
                                .monospacedDigit()
                                .foregroundStyle(trend.deltaPct >= 0 ? .orange : .green)
                            Spacer(minLength: 4)
                            SparklineView(values: Array(snap.history.suffix(14).map(\.costUSD)))
                        }
                    }
                    if let extra = snap.extraUsage {
                        breakdownRow(label: "Extra",
                                     value: "\(Format.usd(extra.usedUSD)) of \(Format.usd(extra.limitUSD)) (\(Int(extra.utilization))%)",
                                     tint: extra.utilization >= 100 ? .orange : .secondary)
                    }
                    if !snap.modelBreakdown.isEmpty {
                        BreakdownDisclosure(
                            label: "Models",
                            items: snap.modelBreakdown.map { (Format.shortModel($0.model), $0.costUSD) },
                            expanded: $showModels)
                    }
                    if !snap.projectBreakdown.isEmpty {
                        BreakdownDisclosure(
                            label: "Projects",
                            items: snap.projectBreakdown.map { ($0.project, $0.costUSD) },
                            expanded: $showProjects)
                    }
                }
            }

            if !snap.history.isEmpty {
                Divider()
                Button {
                    withAnimation(Self.uiSpring) { showHistory.toggle() }
                } label: {
                    HStack {
                        Text(snap.costUnit == .usd ? "Cost history (30 days)" : "Activity (30 days)")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .rotationEffect(.degrees(showHistory ? 90 : 0))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(RowButtonStyle())

                if showHistory {
                    CostHistoryView(history: snap.history, unit: snap.costUnit)
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
                }
            }
        } else if case .loading = state {
            HStack {
                ProgressView().controlSize(.small)
                Text("Loading…").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 12)
        }

        Divider()

        VStack(alignment: .leading, spacing: 2) {
            Button {
                Task { await store.refreshAll() }
            } label: {
                HStack {
                    if store.isRefreshing {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "arrow.clockwise").font(.system(size: 11))
                    }
                    Text("Refresh Now")
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(RowButtonStyle())

            Button {
                withAnimation(Self.uiSpring) { showSettings = true }
            } label: {
                HStack {
                    Image(systemName: "gearshape").font(.system(size: 11))
                    Text("Settings…")
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(RowButtonStyle())

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                HStack {
                    Image(systemName: "power").font(.system(size: 11))
                    Text("Quit")
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(RowButtonStyle())
        }
    }

    /// Today's spend vs the trailing daily average (excluding today) — a quick
    /// "am I burning faster than usual?" signal. Only for USD providers with data.
    private func todayTrend(_ snap: ProviderSnapshot) -> (today: Double, deltaPct: Double)? {
        guard snap.costUnit == .usd, let today = snap.history.last?.costUSD, today > 0 else { return nil }
        let prior = snap.history.dropLast().map(\.costUSD).filter { $0 > 0 }
        guard prior.count >= 3 else { return nil }
        let avg = prior.reduce(0, +) / Double(prior.count)
        guard avg > 0 else { return nil }
        return (today, (today - avg) / avg * 100)
    }

    /// Headline number with a small label above and a caption below — gives the
    /// two key figures visual weight so the eye lands on them before the detail.
    private func statTile(label: String, value: String, sub: String?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .medium))
                .tracking(0.4)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let sub {
                Text(sub)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.045)))
    }

    /// Label column + a single truncating value line — keeps breakdowns to one
    /// tidy row each instead of a wall of same-weight text.
    private func breakdownRow(label: String, value: String, tint: Color = .secondary) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .frame(width: 52, alignment: .leading)
            Text(value)
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    @ViewBuilder
    private func header(_ state: ProviderState, now: Date) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 1) {
                Text(store.selected.displayName)
                    .font(.system(size: 14, weight: .bold))
                if let snap = state.snapshot {
                    Text("Updated \(Format.relativeAge(snap.fetchedAt, now: now))")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                if let account = state.snapshot?.account {
                    Text(account)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                if let plan = state.snapshot?.plan {
                    Text(plan)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// Tiny always-visible line chart of recent daily spend — an at-a-glance trend
/// without opening the full 30-day chart.
struct SparklineView: View {
    let values: [Double]

    var body: some View {
        GeometryReader { geo in
            let maxV = max(values.max() ?? 1, 0.0001)
            let n = max(1, values.count - 1)
            Path { p in
                for (i, v) in values.enumerated() {
                    let x = geo.size.width * CGFloat(i) / CGFloat(n)
                    let y = geo.size.height * (1 - CGFloat(v / maxV))
                    if i == 0 { p.move(to: CGPoint(x: x, y: y)) }
                    else { p.addLine(to: CGPoint(x: x, y: y)) }
                }
            }
            .stroke(Color.orange.opacity(0.85),
                    style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
        }
        .frame(width: 46, height: 14)
    }
}

/// Compact one-line summary (label + top names + chevron) that expands into a
/// full aligned list on tap — progressive disclosure keeps the default popover
/// short while making every value fully readable on demand.
struct BreakdownDisclosure: View {
    let label: String
    let items: [(name: String, cost: Double)]
    @Binding var expanded: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var summary: String {
        items.prefix(3).map(\.name).joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(PopoverView.uiSpring) { expanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Text(label)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .frame(width: 52, alignment: .leading)
                    Text(summary)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(spacing: 3) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        HStack(spacing: 8) {
                            Text(item.name)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 8)
                            Text(Format.usd(item.cost))
                                .font(.system(size: 11, weight: .medium))
                                .monospacedDigit()
                                .foregroundStyle(.primary)
                        }
                    }
                }
                .padding(.leading, 60)
                .padding(.trailing, 2)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

/// Comparison selector: all three providers' session bars at once; tapping one
/// selects it. Doubles as navigation and an at-a-glance comparison (one control
/// that both compares and selects — clear mapping, direct manipulation).
struct ProviderSelector: View {
    @EnvironmentObject var store: UsageStore

    var body: some View {
        HStack(spacing: 6) {
            ForEach(ProviderID.allCases) { id in
                chip(id)
            }
        }
    }

    @ViewBuilder
    private func chip(_ id: ProviderID) -> some View {
        let bar = store.sessionBar(for: id)
        let selected = store.selected == id
        Button {
            withAnimation(PopoverView.uiSpring) { store.selected = id }
        } label: {
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    Text(id.displayName)
                        .font(.system(size: 11, weight: selected ? .semibold : .regular))
                        .foregroundStyle(bar == nil && !selected ? .secondary : .primary)
                    Spacer(minLength: 0)
                    trailingBadge(id: id, bar: bar)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        // Gemini has no session limit — no track (an empty track
                        // would read as 0%/broken); everyone else shows a meter.
                        if id != .gemini {
                            Capsule().fill(Color.primary.opacity(0.1))
                            if let bar {
                                Capsule()
                                    .fill(limitColor(percent: bar.percent, severity: bar.severity))
                                    .frame(width: max(3, geo.size.width * min(1, bar.percent / 100)))
                            }
                        }
                    }
                }
                .frame(height: 4)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.primary.opacity(selected ? 0.09 : 0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(selected ? Color.accentColor.opacity(0.5) : .clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func trailingBadge(id: ProviderID, bar: LimitBar?) -> some View {
        if let bar {
            Text("\(Int(bar.percent.rounded()))%")
                .font(.system(size: 10, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        } else if id == .gemini {
            // No quota to meter — signal "activity only" instead of a fake number.
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
        // else: loading/unavailable — show nothing rather than "—"
    }
}

/// Menu-row style: hover highlight, instant press feedback on pointer-down
/// (stronger highlight + slight scale — response before release, never after).
struct RowButtonStyle: ButtonStyle {
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(configuration.isPressed ? Color.primary.opacity(0.12)
                          : hovering ? Color.primary.opacity(0.07) : .clear)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
            .onHover { hovering = $0 }
    }
}
