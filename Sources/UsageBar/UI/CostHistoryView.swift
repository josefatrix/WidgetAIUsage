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
        case .requests: return "\(Int(d.costUSD)) requests"
        }
    }

    private var totalLabel: String {
        let total = history.reduce(0) { $0 + $1.costUSD }
        switch unit {
        case .usd: return "Total (30d): \(Format.usd(total))"
        case .requests: return "Total (30d): \(Int(total)) requests"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let d = focused {
                Text("\(Format.dayLabel(d.day)): \(value(d))")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(Array(history.enumerated()), id: \.offset) { index, day in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.orange.opacity(hoverIndex == index ? 1 : 0.75))
                        .frame(height: max(2, 70 * day.costUSD / maxCost))
                        .frame(maxWidth: .infinity, alignment: .bottom)
                        .onHover { inside in
                            hoverIndex = inside ? index : (hoverIndex == index ? nil : hoverIndex)
                        }
                }
            }
            .frame(height: 74, alignment: .bottom)
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
                .foregroundStyle(.secondary)
        }
        .padding(.top, 2)
        .transition(.opacity)
    }
}
