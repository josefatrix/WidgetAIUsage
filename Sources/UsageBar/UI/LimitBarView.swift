import SwiftUI
import UsageBarCore

/// API severity wins; falls back to percent thresholds when the provider has none.
func limitColor(percent: Double, severity: String?) -> Color {
    switch severity {
    case "warning": return .orange
    case "exceeded", "critical", "error": return .red
    case "normal": return .accentColor
    default:
        if percent >= 85 { return .red }
        if percent >= 60 { return .orange }
        return .accentColor
    }
}

struct LimitBarView: View {
    let limit: LimitBar
    let now: Date
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(limit.label)
                .font(.system(size: 12, weight: .semibold))
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.08))
                    Capsule()
                        .fill(limitColor(percent: limit.percent, severity: limit.severity))
                        .frame(width: max(4, geo.size.width * min(1, limit.percent / 100)))
                        // Critically damped spring (Apple: damping 1.0, response 0.4).
                        .animation(reduceMotion ? nil : .spring(duration: 0.4, bounce: 0), value: limit.percent)
                }
            }
            .frame(height: 5)
            HStack {
                Text("\(Int(limit.percent.rounded()))% used")
                Spacer()
                if let resets = limit.resetsAt {
                    Text(Format.resetsIn(resets, now: now))
                }
            }
            .font(.system(size: 11))
            .monospacedDigit()
            .foregroundStyle(.secondary)
        }
    }
}
