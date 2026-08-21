import SwiftUI
import UsageBarCore

/// Which layout the popover uses. Both are finished designs rather than a
/// half-built alternative: the dial reads at a glance, the panel packs more
/// numbers into less height, and which one is better depends on whether you
/// open the popover to check or to study.
enum PopoverStyle: String, CaseIterable, Identifiable {
    case dial, panel
    var id: String { rawValue }
    var label: String {
        switch self {
        case .dial: return "Dial"
        case .panel: return "Bars"
        }
    }
}

// MARK: - Panel style ("A · Glass Panel")

/// A meter recessed into the sheet. The track is a well; the fill sits in it with
/// its own top highlight, so the value reads as something poured in rather than
/// painted on.
struct GlassMeter: View {
    let percent: Double
    let color: Color
    var height: CGFloat = 7

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.11))
                    .overlay(Capsule().strokeBorder(Glass.specularInset, lineWidth: 0.5))
                Capsule()
                    .fill(color)
                    .overlay(
                        Capsule().fill(
                            LinearGradient(colors: [.white.opacity(0.42), .white.opacity(0.02)],
                                           startPoint: .top, endPoint: .bottom))
                    )
                    .frame(width: max(percent > 0 ? 4 : 0,
                                      geo.size.width * min(1, percent / 100)))
            }
        }
        .frame(height: height)
        .animation(reduceMotion ? nil : RingGauge.motion, value: percent)
        .animation(reduceMotion ? nil : RingGauge.motion, value: color)
    }
}

/// One limit as a labelled horizontal meter, with its reset and forecast.
struct LimitBarView: View {
    let limit: LimitBar
    let now: Date

    /// Flagged by the provider when the window this figure belongs to already
    /// reset: keep showing the last number, stop implying it is current.
    private var isStale: Bool { limit.severity == "stale" }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Text(limit.label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isStale ? .secondary : .primary)
                if isStale {
                    Text("STALE")
                        .font(.system(size: 8, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Capsule().fill(Color.primary.opacity(0.09)))
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.16), lineWidth: 0.5))
                }
                Spacer(minLength: 4)
                Text("\(Int(limit.percent.rounded()))%")
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(limitColor(percent: limit.percent, severity: limit.severity))
                    .contentTransition(.numericText())
            }

            GlassMeter(percent: limit.percent,
                       color: limitColor(percent: limit.percent, severity: limit.severity))

            HStack {
                if isStale {
                    // "Resets in 0m" for a reset that passed weeks ago reads as
                    // "about to refresh"; say what actually happened instead.
                    Text("window already reset")
                } else if let resets = limit.resetsAt {
                    Text(Format.resetsIn(resets, now: now))
                }
                Spacer(minLength: 4)
                if let forecast {
                    Text(forecast.willHitBeforeReset
                         ? "hits the limit in \(Format.etaShort(forecast.hitDate, now: now))"
                         : "≈\(Int(forecast.projectedPercentAtReset.rounded()))% by reset")
                        .foregroundStyle(forecast.willHitBeforeReset ? Color.orange : Color.secondary)
                }
            }
            .font(.system(size: 11))
            .monospacedDigit()
            .foregroundStyle(.secondary)
        }
    }

    private var forecast: Forecast? {
        guard let resets = limit.resetsAt, let window = limit.windowMinutes else { return nil }
        return Projection.forecast(percent: limit.percent, resetsAt: resets,
                                   windowMinutes: window, now: now)
    }
}

/// Headline number with a small label above and a caption below — gives the two
/// key figures visual weight so the eye lands on them before the detail.
struct GlassStatTile: View {
    let label: String
    let value: String
    let sub: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .medium))
                .tracking(0.4)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 16, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
            if let sub {
                Text(sub)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .glassWash(Glass.tileRadius, tint: 0.055)
    }
}

/// Provider chip for the panel style: name, percentage and a horizontal meter —
/// the same vocabulary as the bars above it.
struct ProviderChip: View {
    let id: ProviderID
    let bar: LimitBar?
    let selected: Bool

    var body: some View {
        // Two lines, not one: four chips across 320pt leave ~55pt of content each,
        // and a name beside its percentage truncated every provider to "Cla…".
        VStack(spacing: 4) {
            Text(id.displayName)
                .font(.system(size: 10.5, weight: selected ? .semibold : .regular))
                .foregroundStyle(bar == nil && !selected ? .secondary : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 4) {
                if id.noQuotaNote == nil {
                    GlassMeter(percent: bar?.percent ?? 0,
                               color: limitColor(percent: bar?.percent ?? 0, severity: bar?.severity),
                               height: 5)
                        .opacity(bar == nil ? 0.5 : 1)
                    if let bar {
                        Text("\(Int(bar.percent.rounded()))%")
                            .font(.system(size: 9, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .fixedSize()
                    }
                } else {
                    // No quota to meter — signal "activity only" instead of a fake number.
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(height: 5)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 6)
        .glassWash(Glass.chipRadius, tint: selected ? 0.10 : 0.035, lit: selected ? 1 : 0.6)
        .glassSelection(Glass.chipRadius, active: selected)
        .contentShape(Rectangle())
    }
}
