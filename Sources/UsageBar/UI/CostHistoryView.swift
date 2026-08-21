import SwiftUI
import UsageBarCore

struct CostHistoryView: View {
    let history: [DailyCost]
    let unit: CostUnit
    @State private var hoverIndex: Int? = nil

    private var maxCost: Double { max(history.map(\.costUSD).max() ?? 0, 0.01) }

    private var focused: DailyCost? {
        if let i = hoverIndex, history.indices.contains(i) { return history[i] }
        return history.last { $0.costUSD > 0 }
    }

    private func value(_ d: DailyCost) -> String {
        switch unit {
        case .usd: return "\(Format.usd(d.costUSD)) · \(Format.tokens(d.tokens))"
        default: return "\(Int(d.costUSD)) \(unit.pluralNoun)"
        }
    }

    private var totalLabel: String {
        let total = history.reduce(0) { $0 + $1.costUSD }
        switch unit {
        case .usd: return "Total (30d): \(Format.usd(total))"
        default: return "Total (30d): \(Int(total)) \(unit.pluralNoun)"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let d = focused {
                Text("\(Format.dayLabel(d.day)): \(value(d))")
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(Array(history.enumerated()), id: \.offset) { index, day in
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(Color.orange.opacity(barOpacity(index)))
                            .frame(height: max(2, 70 * day.costUSD / maxCost))
                            .frame(maxWidth: .infinity, alignment: .bottom)
                    }
                }
                .frame(height: 74, alignment: .bottom)
                .contentShape(Rectangle())
                // Continuous 1:1 hover tracking across the whole chart — no dead
                // gaps between bars, feedback follows the pointer the entire way.
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let p):
                        let step = geo.size.width / CGFloat(max(1, history.count))
                        hoverIndex = min(history.count - 1, max(0, Int(p.x / max(step, 1))))
                    case .ended:
                        hoverIndex = nil
                    }
                }
            }
            .frame(height: 74)
            if let first = history.first?.day, let last = history.last?.day {
                HStack {
                    Text(Format.dayLabel(first))
                    Spacer()
                    Text(Format.dayLabel(last))
                }
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
            }
            Text(totalLabel)
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.top, 2)
    }

    private func barOpacity(_ index: Int) -> Double {
        guard let hoverIndex else { return 0.8 }
        return hoverIndex == index ? 1 : 0.45
    }
}
