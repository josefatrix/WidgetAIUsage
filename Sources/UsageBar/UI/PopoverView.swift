import SwiftUI
import UsageBarCore

struct PopoverView: View {
    @EnvironmentObject var store: UsageStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showHistory = false
    @State private var showSettings = false

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
                Picker("", selection: $store.selected) {
                    ForEach(ProviderID.allCases) { id in
                        Text(id.displayName).tag(id)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

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
                VStack(alignment: .leading, spacing: 3) {
                    Text("Cost (est.)")
                        .font(.system(size: 12, weight: .semibold))
                    Group {
                        Text("Session: \(Format.usd(cost.sessionCostUSD)) · \(Format.tokens(cost.sessionTokens))")
                            .foregroundStyle(.secondary)
                        Text("Last 30 days: \(Format.usd(cost.last30DaysCostUSD))")
                            .foregroundStyle(.secondary)
                        if let extra = snap.extraUsage {
                            Text("Extra usage: \(Format.usd(extra.usedUSD)) of \(Format.usd(extra.limitUSD)) (\(Int(extra.utilization))%)")
                                .foregroundStyle(extra.utilization >= 100 ? .orange : .secondary)
                        }
                    }
                    .font(.system(size: 11))
                    .monospacedDigit()
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
