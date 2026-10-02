import SwiftUI
import UsageBarCore

/// The material vocabulary for direction A — "Glass Panel".
///
/// The governing rule, from the mockups and from Apple's own guidance for Tahoe:
/// **the popover window IS the sheet of glass.** The system draws it, and on
/// macOS 26 it is already Liquid Glass. Nothing inside nests a second pane —
/// glass on glass muddies both. So everything here is one of two things:
///
///   - a *wash*: a tinted surface lying flat ON the sheet (chips, tiles, rows),
///     lit along its top edge because that is where light enters glass;
///   - a *well*: a recess cut INTO the sheet (meter tracks), darkened and with
///     the highlight on the bottom edge instead, since a recess catches light
///     the other way round.
///
/// Body tints stay on `Color.primary` so they invert with the appearance;
/// highlights stay white, because a specular highlight is light, not ink.
enum Glass {
    /// Squircles, matching the system's own corner geometry.
    static func shape(_ radius: CGFloat) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }

    static let tileRadius: CGFloat = 13
    static let chipRadius: CGFloat = 11
    static let rowRadius: CGFloat = 9
    static let noticeRadius: CGFloat = 11

    /// Light entering the top edge and falling off down the face.
    static let specular = LinearGradient(
        colors: [.white.opacity(0.50), .white.opacity(0.06), .white.opacity(0.16)],
        startPoint: .top, endPoint: .bottom)

    /// The same, inverted: a recess is lit along its lower lip.
    static let specularInset = LinearGradient(
        colors: [.black.opacity(0.16), .clear, .white.opacity(0.22)],
        startPoint: .top, endPoint: .bottom)
}

extension View {
    /// A wash on the sheet: tinted body plus a specular top edge.
    func glassWash(_ radius: CGFloat, tint: Double = 0.06, lit: Double = 1) -> some View {
        background(Glass.shape(radius).fill(Color.primary.opacity(tint)))
            .overlay(Glass.shape(radius).strokeBorder(Glass.specular, lineWidth: 0.5).opacity(lit))
    }

    /// Ring used to mark the selected provider — accent, not a heavier fill, so
    /// selection reads as light rather than as weight.
    func glassSelection(_ radius: CGFloat, active: Bool) -> some View {
        overlay(
            Glass.shape(radius)
                .strokeBorder(Color.accentColor.opacity(active ? 0.55 : 0), lineWidth: 1)
        )
    }
}

/// Colour follows `LimitLevel`, which takes the worse of the provider's severity
/// and the percentage thresholds. Trusting severity alone kept a 65% bar blue,
/// because Anthropic still calls that "normal".
func limitColor(percent: Double, severity: String?) -> Color {
    switch LimitLevel.of(percent: percent, severity: severity) {
    case .normal: return .accentColor
    case .warning: return .orange
    case .critical: return .red
    case .stale: return .secondary
    }
}

/// One-line notice on the sheet — amber for "look at this", plain wash for
/// "this is just context".
struct GlassNotice: View {
    let text: String
    let systemImage: String
    var amber: Bool = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(amber ? Color.orange : Color.secondary)
            Text(text)
                .font(.system(size: 10.5))
                .foregroundStyle(amber ? Color.orange : Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(
            Glass.shape(Glass.noticeRadius)
                .fill(amber ? Color.orange.opacity(0.14) : Color.primary.opacity(0.05))
        )
        .overlay(
            Glass.shape(Glass.noticeRadius)
                .strokeBorder(amber ? Color.orange.opacity(0.28) : Color.white.opacity(0.14),
                              lineWidth: 0.5)
        )
    }
}
