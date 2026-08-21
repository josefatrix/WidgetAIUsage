import AppKit
import SwiftUI
import UsageBarCore

enum MenuBarStyle: String, CaseIterable, Identifiable {
    case ring, ringPercent, bar, dual
    var id: String { rawValue }
    var label: String {
        switch self {
        case .ring: return "Ring"
        case .ringPercent: return "Ring + %"
        case .bar: return "Bar"
        case .dual: return "Claude + Codex"
        }
    }
}

enum MenuBarLabel {
    static func nsColor(percent: Double, severity: String?) -> NSColor {
        switch LimitLevel.of(percent: percent, severity: severity) {
        case .normal: return .controlAccentColor
        case .warning: return .systemOrange
        case .critical: return .systemRed
        case .stale: return .tertiaryLabelColor
        }
    }

    static let barWidth: CGFloat = 34
    /// 20pt. The menu bar gives about 22pt of usable height, and a ring has no
    /// fine detail to lose, so it can fill more of that than a glyph would — at
    /// 17 it sat noticeably smaller than the system icons beside it.
    static let ringSize: CGFloat = 20

    // MARK: ring

    /// 270° sweep with the gap at the bottom, matching the popover's dial. AppKit
    /// angles grow counter-clockwise from 3 o'clock, so sweeping clockwise from
    /// 225° to −45° passes over the top and leaves the gap under the glyph.
    private static func arc(center: NSPoint, radius: CGFloat, fraction: Double) -> NSBezierPath {
        let path = NSBezierPath()
        let start: CGFloat = 225
        let end = start - 270 * CGFloat(max(0, min(1, fraction)))
        path.appendArc(withCenter: center, radius: radius,
                       startAngle: start, endAngle: end, clockwise: true)
        return path
    }

    /// What every style draws: the outer ring's limit — the current session — so
    /// the icon and the dial's big number always agree.
    static func headline(_ pair: (outer: LimitBar?, inner: LimitBar?)) -> LimitBar? {
        pair.outer
    }

    private static func drawRing(_ bar: LimitBar?, center: NSPoint, radius: CGFloat, width: CGFloat) {
        let track = arc(center: center, radius: radius, fraction: 1)
        track.lineWidth = width
        track.lineCapStyle = .round
        // labelColor inverts with the appearance, so this seat stays visible on a
        // dark bar and on a light one — on Tahoe the menu bar is itself glass and a
        // fixed-colour track disappears over half the wallpapers out there.
        NSColor.labelColor.withAlphaComponent(0.22).setStroke()
        track.stroke()

        guard let bar, bar.percent > 0 else { return }
        let value = arc(center: center, radius: radius, fraction: bar.percent / 100)
        value.lineWidth = width
        value.lineCapStyle = .round
        nsColor(percent: bar.percent, severity: bar.severity).setStroke()
        value.stroke()
    }

    /// ONE ring, deliberately. The popover's dial nests two, but at menu-bar size
    /// the inner arc collapsed into a smudge in the middle — it read as a dot in a
    /// circle rather than as a second reading. The icon shows the limit closest to
    /// biting; the second window is one click away.
    private static func drawDial(outer: LimitBar?, inner: LimitBar?, in rect: NSRect) {
        let c = NSPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2 - 2.1
        drawRing(headline((outer: outer, inner: inner)), center: c, radius: r, width: 3.2)
    }

    // MARK: bar (kept as an option — some people just want the meter)

    private static func drawBar(_ bar: LimitBar?, in rect: NSRect) {
        let radius = rect.height / 2 - 0.5
        let well = rect.insetBy(dx: 0.5, dy: 0.5)
        let wellPath = NSBezierPath(roundedRect: well, xRadius: radius, yRadius: radius)

        NSColor.labelColor.withAlphaComponent(0.14).setFill()
        wellPath.fill()
        NSColor.labelColor.withAlphaComponent(0.30).setStroke()
        wellPath.lineWidth = 1
        wellPath.stroke()

        guard let bar else { return }
        let usable = rect.width - 4
        let fillWidth = MenuBarMetrics.fillWidth(percent: bar.percent, usableWidth: usable)
        guard fillWidth > 0 else { return }
        let fillRect = NSRect(x: rect.minX + 2, y: rect.minY + 2, width: fillWidth, height: rect.height - 4)
        let fill = NSBezierPath(roundedRect: fillRect, xRadius: 1.5, yRadius: 1.5)
        nsColor(percent: bar.percent, severity: bar.severity).setFill()
        fill.fill()
        // Specular lip only where there is room for one.
        guard fillRect.width > 5 else { return }
        let lip = NSBezierPath()
        lip.move(to: NSPoint(x: fillRect.minX + 1.5, y: fillRect.maxY - 0.5))
        lip.line(to: NSPoint(x: fillRect.maxX - 1.5, y: fillRect.maxY - 0.5))
        NSColor.white.withAlphaComponent(0.40).setStroke()
        lip.lineWidth = 1
        lip.stroke()
    }

    // MARK: composition

    static func image(style: MenuBarStyle,
                      selected: (outer: LimitBar?, inner: LimitBar?),
                      claude: LimitBar?, codex: LimitBar?) -> NSImage {
        switch style {
        case .ring:
            let size = NSSize(width: ringSize, height: ringSize)
            return NSImage(size: size, flipped: false) { rect in
                drawDial(outer: selected.outer, inner: selected.inner, in: rect)
                return true
            }

        case .ringPercent:
            let size = NSSize(width: ringSize + 26, height: ringSize)
            return NSImage(size: size, flipped: false) { _ in
                drawDial(outer: selected.outer, inner: selected.inner,
                         in: NSRect(x: 0, y: 0, width: ringSize, height: ringSize))
                let bar = headline(selected)
                let text = bar.map { "\(Int($0.percent.rounded()))%" } ?? "–"
                draw(text: text, at: NSPoint(x: ringSize + 4, y: 3),
                     color: bar.map { nsColor(percent: $0.percent, severity: $0.severity) }
                        ?? .secondaryLabelColor)
                return true
            }

        case .bar:
            let size = NSSize(width: barWidth, height: 12)
            return NSImage(size: size, flipped: false) { rect in
                drawBar(headline(selected), in: rect)
                return true
            }

        case .dual:
            let size = NSSize(width: ringSize * 2 + 4, height: ringSize)
            return NSImage(size: size, flipped: false) { _ in
                drawDial(outer: claude, inner: nil,
                         in: NSRect(x: 0, y: 0, width: ringSize, height: ringSize))
                drawDial(outer: codex, inner: nil,
                         in: NSRect(x: ringSize + 4, y: 0, width: ringSize, height: ringSize))
                return true
            }
        }
    }

    private static func draw(text: String, at point: NSPoint, color: NSColor) {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        (text as NSString).draw(at: point, withAttributes: attrs)
    }
}
