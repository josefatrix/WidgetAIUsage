import SwiftUI
import UsageBarCore

struct LimitBarView: View {
    let limit: LimitBar

    private var barColor: Color {
        if limit.percent >= 85 { return .red }
        if limit.percent >= 60 { return .orange }
        return .accentColor
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(limit.label)
                .font(.system(size: 12, weight: .semibold))
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.08))
                    Capsule()
                        .fill(barColor)
                        .frame(width: max(4, geo.size.width * min(1, limit.percent / 100)))
                        .animation(.easeOut(duration: 0.25), value: limit.percent)
                }
            }
            .frame(height: 5)
            HStack {
                Text("\(Int(limit.percent.rounded()))% used")
                Spacer()
                if let resets = limit.resetsAt {
                    Text(Format.resetsIn(resets))
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
    }
}
