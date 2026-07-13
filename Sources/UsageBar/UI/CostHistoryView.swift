import SwiftUI
import UsageBarCore

struct CostHistoryView: View {
    let history: [DailyCost]
    let totalLabel: String
    @State private var hoverIndex: Int? = nil

    private var maxCost: Double { max(history.map(\.costUSD).max() ?? 0, 0.01) }

    private var focused: DailyCost? {
        if let i = hoverIndex, history.indices.contains(i) { return history[i] }
        return history.last { $0.costUSD > 0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let d = focused {
                Text("\(Format.dayLabel(d.day)): \(Format.usd(d.costUSD)) · \(Format.tokens(d.tokens))")
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
            Text(totalLabel)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.top, 2)
        .transition(.opacity)
    }
}
