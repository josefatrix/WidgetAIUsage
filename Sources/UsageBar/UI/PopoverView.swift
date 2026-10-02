import SwiftUI
import UsageBarCore

struct PopoverView: View {
    @EnvironmentObject var store: UsageStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showHistory = false
    @State private var showSettings = false
    @State private var showModels = false
    @State private var showProjects = false
    @State private var connectError: String? = nil

    /// Critically damped spring — Apple's default UI motion (damping 1.0).
    static let uiSpring = Animation.spring(duration: 0.3, bounce: 0)

    /// Past this, scraped data gets an explicit "this is old" banner. Six hours
    /// covers a normal working gap without crying wolf.
    static let staleAfter: TimeInterval = 6 * 3600

    private var settingsTransition: AnyTransition {
        reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity)
    }
    private var contentTransition: AnyTransition {
        reduceMotion ? .opacity : .move(edge: .leading).combined(with: .opacity)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(alignment: .leading, spacing: 10) {
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
        .onAppear { store.refreshIfStale() }
        // MenuBarExtra keeps this view alive between openings, so onAppear alone only
        // fires the first time. The panel becoming key is the reliable "opened" signal.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            store.refreshIfStale()
        }
    }

    @ViewBuilder
    private func providerContent(now: Date) -> some View {
        let state = store.selectedState

        header(state, now: now)

        if let error = state.errorMessage {
            GlassNotice(text: error, systemImage: "exclamationmark.triangle", amber: true)
        }

        if let snap = state.snapshot {
            if snap.dataThrough != nil, snap.isStale(now: now, threshold: Self.staleAfter) {
                GlassNotice(
                    text: store.selected == .codex && !snap.limits.isEmpty
                        ? "General Codex quota observed \(Format.relativeAge(snap.asOf, now: now)) — local costs refresh separately."
                        : "Last local \(store.selected.displayName) session \(Format.relativeAge(snap.asOf, now: now)) — everything below is from then.",
                    systemImage: "clock.badge.exclamationmark",
                    amber: true)
            }

            switch store.popoverStyle {
            case .dial: dial(snap, now: now)
            case .panel: panel(snap, now: now)
            }

            // Why the dial is empty or old. A blank ring with no explanation is
            // the worst outcome — the user cannot tell "no quota exists" from
            // "we could not reach the API".
            // Providers only set a note when something is wrong, so always show it.
            // (It used to hinge on the snapshot looking stale, which hid it whenever
            // the local logs were fresh but the limits were a day old.)
            if let note = snap.limitsNote {
                GlassNotice(text: note, systemImage: "exclamationmark.triangle", amber: true)
                // The fix, one click from the complaint.
                if store.selected == .claude, !store.claudeStatusLineInstalled {
                    ghostButton("Read limits from Claude Code", icon: "link") {
                        connectError = store.setClaudeStatusLine(true)
                    }
                }
                if let connectError {
                    Text(connectError)
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if let note = store.selected.noQuotaNote, snap.limits.isEmpty {
                Text(note)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if store.popoverStyle == .dial {
                costLine(snap)
            } else {
                costTiles(snap)
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

            if !snap.history.isEmpty, showHistory {
                CostHistoryView(history: snap.history, unit: snap.costUnit)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }
        } else if case .loading = state {
            HStack {
                ProgressView().controlSize(.small)
                Text("Loading…").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 12)
        }

        Divider().padding(.top, 2)

        // The switcher sits under the reading, not over it: you land on your data
        // and change provider afterwards. Same dial at 30pt, so comparing all four
        // needs no second screen and no second visual language.
        ProviderSelector()

        actionBar(hasHistory: !(state.snapshot?.history.isEmpty ?? true))
    }

    // MARK: dial

    @ViewBuilder
    private func dial(_ snap: ProviderSnapshot, now: Date) -> some View {
        // A provider with no quota at all gets no ring: a full empty track reads as
        // a meter sitting at 0%, which is a different claim from "there is nothing
        // to meter here". Claude with an unreadable quota still gets the ring, so
        // "couldn't read it" stays visibly different from "doesn't exist".
        if snap.limits.isEmpty, store.selected.noQuotaNote != nil {
            VStack(spacing: 2) {
                Text(reading(snap, headline: nil))
                    .font(.system(size: 34, weight: .light))
                    .monospacedDigit()
                    .kerning(-1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(readingCaption(snap, headline: nil))
                    .font(.system(size: 8.5, weight: .semibold))
                    .tracking(0.4)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        } else {
            quotaDial(snap, now: now)
        }
    }

    @ViewBuilder
    private func quotaDial(_ snap: ProviderSnapshot, now: Date) -> some View {
        // Fixed rings: current session outside, weekly inside, always. The legend
        // stays ranked by pressure so nothing hides, and a per-model limit close to
        // biting gets its own line — it can never take a ring.
        let pair = UsageWindow.rings(limits: snap.limits, now: now)
        let headline = pair.outer
        let second = pair.inner
        // Legend order follows the dial, not pressure: outer ring first, inner
        // second, then everything the dial cannot draw, most-pressing first. With
        // pressure ordering, the outer ring's own row ended up last in its list.
        // Only what the dial cannot say itself. Both rings are now spelled out in
        // the middle, so listing them again below was the same numbers twice.
        let ordered = UsageWindow.ranked(limits: snap.limits, now: now)
            .filter { $0.id != pair.outer?.id && $0.id != pair.inner?.id }
        let pressing = UsageWindow.pressing(limits: snap.limits, now: now)
        let forecast = projection(for: headline, now: now)

        VStack(spacing: 8) {
            ConcentricDial(outer: headline,
                           inner: second,
                           reading: reading(snap, headline: headline),
                           readingCaption: readingCaption(snap, headline: headline),
                           readingColor: Self.tint(headline),
                           outerColor: Self.tint(headline),
                           innerColor: Self.tint(second),
                           // Kept short on purpose: the space inside the inner ring
                           // is ~79pt wide, and appending the reset pushed this line
                           // straight under the arc.
                           secondaryLine: second.map { "\(Int($0.percent.rounded()))% \($0.label.lowercased())" },
                           footnote: Self.resetFootnote(outer: headline, inner: second, now: now),
                           projection: forecast?.projectedPercentAtReset,
                           dimmed: headline?.severity == "stale")
                .frame(maxWidth: .infinity)

            VStack(spacing: 0) {
                ForEach(ordered.prefix(3)) { bar in
                    RingLegendRow(bar: bar, color: Self.tint(bar), now: now, ring: 2)
                }
            }
        }

        // Dial-only: the panel gives every limit its own meter, so a per-model one
        // at 100% is already impossible to miss there.
        if let pressing {
            GlassNotice(text: "\(pressing.label) at \(Int(pressing.percent.rounded()))% of its weekly limit",
                        systemImage: "exclamationmark.circle", amber: true)
        }

        if let forecast {
            if forecast.willHitBeforeReset {
                GlassNotice(text: "On pace to hit the limit in \(Format.etaShort(forecast.hitDate, now: now))",
                            systemImage: "gauge.with.dots.needle.67percent", amber: true)
            } else {
                GlassNotice(text: "At this pace ≈\(Int(forecast.projectedPercentAtReset.rounded()))% by reset",
                            systemImage: "gauge.with.dots.needle.33percent")
            }
        }
    }

    /// Both resets in the gap under the dial — the one place with the width for
    /// them, and the gap was dead space anyway.
    static func resetFootnote(outer: LimitBar?, inner: LimitBar?, now: Date) -> String? {
        guard let outer else { return nil }
        if outer.severity == "stale" { return "window already reset" }
        guard let a = outer.resetsAt else { return nil }
        let head = "resets " + Format.etaShort(a, now: now)
        guard let inner, inner.severity != "stale", let b = inner.resetsAt else { return head }
        return head + " · " + inner.label.lowercased() + " " + Format.etaShort(b, now: now)
    }

    static func tint(_ bar: LimitBar?) -> Color {
        bar.map { limitColor(percent: $0.percent, severity: $0.severity) } ?? .secondary
    }

    // MARK: panel

    /// "A · Glass Panel": one labelled meter per limit, stacked. Denser than the
    /// dial and every limit gets equal billing, including per-model ones — the
    /// dial has only two rings, so those need a separate warning there.
    @ViewBuilder
    private func panel(_ snap: ProviderSnapshot, now: Date) -> some View {
        if snap.limits.isEmpty {
            VStack(spacing: 2) {
                Text(reading(snap, headline: nil))
                    .font(.system(size: 28, weight: .light))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(readingCaption(snap, headline: nil))
                    .font(.system(size: 8.5, weight: .semibold))
                    .tracking(0.4)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        } else {
            VStack(alignment: .leading, spacing: 11) {
                ForEach(UsageWindow.ranked(limits: snap.limits, now: now)) { bar in
                    LimitBarView(limit: bar, now: now)
                }
            }
        }
    }

    @ViewBuilder
    private func costTiles(_ snap: ProviderSnapshot) -> some View {
        if let cost = snap.cost {
            HStack(spacing: 8) {
                GlassStatTile(label: cost.sessionLabel,
                              value: Format.usd(cost.sessionCostUSD),
                              sub: Format.tokens(cost.sessionTokens))
                GlassStatTile(label: "Last 30 days",
                              value: Format.usd(cost.last30DaysCostUSD),
                              sub: "estimated")
            }
            HStack(spacing: 6) {
                Text("Today \(Format.usd(snap.history.last?.costUSD ?? 0))")
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                SparklineView(values: Array(snap.history.suffix(14).map(\.costUSD)))
            }
        } else if !snap.history.isEmpty {
            HStack(spacing: 8) {
                GlassStatTile(label: "Today",
                              value: "\(Int(snap.history.last?.costUSD ?? 0))",
                              sub: snap.costUnit.pluralNoun)
                GlassStatTile(label: "Last 30 days",
                              value: "\(Int(snap.history.reduce(0) { $0 + $1.costUSD }))",
                              sub: snap.costUnit.pluralNoun)
            }
        }
    }

    private func projection(for bar: LimitBar?, now: Date) -> Forecast? {
        guard let bar, let resets = bar.resetsAt, let window = bar.windowMinutes else { return nil }
        return Projection.forecast(percent: bar.percent, resetsAt: resets, windowMinutes: window, now: now)
    }

    /// The number in the middle. Three cases, and conflating them is how a dial
    /// starts lying: a real percentage; an activity count for providers that have
    /// no quota to report; and an em dash for a provider that *has* a quota we
    /// just could not read this time (an Anthropic 429 is routine).
    private func reading(_ snap: ProviderSnapshot, headline: LimitBar?) -> String {
        if let headline { return "\(Int(headline.percent.rounded()))" }
        guard store.selected.noQuotaNote != nil else { return "—" }
        let total = snap.history.reduce(0) { $0 + $1.costUSD }
        return snap.costUnit == .usd ? Format.usd(total) : "\(Int(total))"
    }

    private func readingCaption(_ snap: ProviderSnapshot, headline: LimitBar?) -> String {
        if let headline { return "% \(headline.label.uppercased())" }
        guard store.selected.noQuotaNote != nil else { return "NO LIMIT DATA" }
        return "\(snap.costUnit.pluralNoun.uppercased()) · 30D"
    }

    // MARK: cost

    @ViewBuilder
    private func costLine(_ snap: ProviderSnapshot) -> some View {
        if let cost = snap.cost {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(Format.usd(cost.sessionCostUSD))
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                Text(cost.sessionLabel.lowercased())
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 4)
                Text(Format.usd(cost.last30DaysCostUSD))
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Text("30d")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                SparklineView(values: Array(snap.history.suffix(14).map(\.costUSD)))
            }
        } else if !snap.history.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text("\(Int(snap.history.last?.costUSD ?? 0))")
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                Text("today")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 4)
                SparklineView(values: Array(snap.history.suffix(14).map(\.costUSD)))
            }
        }
    }

    // MARK: chrome

    @ViewBuilder
    private func actionBar(hasHistory: Bool) -> some View {
        HStack(spacing: 6) {
            ghostButton("Refresh", icon: "arrow.clockwise", busy: store.isRefreshing) {
                Task { await store.refreshAll() }
            }
            if hasHistory {
                ghostButton(showHistory ? "Hide" : "Detail", icon: "chart.bar.xaxis") {
                    withAnimation(Self.uiSpring) { showHistory.toggle() }
                }
            }
            Spacer(minLength: 0)
            ghostIcon("gearshape", help: "Settings") {
                withAnimation(Self.uiSpring) { showSettings = true }
            }
            ghostIcon("power", help: "Quit UsageBar") {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    private func ghostButton(_ title: String, icon: String, busy: Bool = false,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if busy {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: icon).font(.system(size: 10, weight: .medium))
                }
                Text(title).font(.system(size: 11))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(GhostButtonStyle())
    }

    private func ghostIcon(_ icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 13, height: 13)
                .contentShape(Rectangle())
        }
        .buttonStyle(GhostButtonStyle())
        .help(help)
    }

    /// Label column + a single truncating value line.
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
            Text(store.selected.displayName)
                .font(.system(size: 13, weight: .bold))
            if let plan = state.snapshot?.plan {
                Text(plan)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 6)
            if let snap = state.snapshot {
                // asOf, not fetchedAt: for log-scraping providers re-reading a
                // three-week-old file every 5 min is not an update.
                Text(Format.relativeAge(snap.asOf, now: now))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        if let account = state.snapshot?.account {
            Text(account)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.top, -8)
        }
    }
}

/// Menu-row style for the popover's action bar: a wash that lights up on hover
/// and presses in, rather than a filled button competing with the dial.
struct GhostButtonStyle: ButtonStyle {
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(
                Glass.shape(Glass.rowRadius)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.14
                                                : hovering ? 0.085 : 0.045))
            )
            .overlay(
                Glass.shape(Glass.rowRadius)
                    .strokeBorder(Glass.specular, lineWidth: 0.5)
                    .opacity(configuration.isPressed ? 1 : hovering ? 0.85 : 0.5)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
            .onHover { hovering = $0 }
    }
}

/// Tiny always-visible line chart of recent daily spend.
struct SparklineView: View {
    let values: [Double]

    /// Flat input draws a horizontal rule that reads as a trend line. Codex, with
    /// no activity for three weeks, was showing exactly that.
    private var hasShape: Bool {
        guard let first = values.first, values.count > 1 else { return false }
        return values.contains { abs($0 - first) > 0.0001 }
    }

    var body: some View {
        if hasShape { chart } else { Color.clear.frame(width: 0, height: 14) }
    }

    private var chart: some View {
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

/// Compact one-line summary that expands into a full aligned list on tap.
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

/// Comparison selector: all four providers as the same dial at 30pt. Tapping one
/// selects it — one control that both compares and navigates.
struct ProviderSelector: View {
    @EnvironmentObject var store: UsageStore

    var body: some View {
        HStack(spacing: store.popoverStyle == .dial ? 2 : 5) {
            ForEach(ProviderID.allCases) { id in
                chip(id)
            }
        }
    }

    @ViewBuilder
    private func chip(_ id: ProviderID) -> some View {
        let rings = store.rings(for: id)
        let selected = store.selected == id
        let color = rings.outer.map { limitColor(percent: $0.percent, severity: $0.severity) } ?? .secondary
        Button {
            withAnimation(PopoverView.uiSpring) { store.selected = id }
        } label: {
            Group {
                if store.popoverStyle == .dial {
                    VStack(spacing: 5) {
                        MiniRing(outer: rings.outer?.percent,
                                 inner: rings.inner?.percent,
                                 color: color,
                                 dimmed: rings.outer?.severity == "stale")
                        Text(id.displayName)
                            .font(.system(size: 10, weight: selected ? .semibold : .regular))
                            .foregroundStyle(selected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .glassWash(Glass.chipRadius, tint: selected ? 0.10 : 0, lit: selected ? 1 : 0)
                    .glassSelection(Glass.chipRadius, active: selected)
                } else {
                    ProviderChip(id: id, bar: rings.outer, selected: selected)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
