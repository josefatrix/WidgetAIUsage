import AppKit
import SwiftUI
import UsageBarCore

enum MenuBarStyle: String, CaseIterable, Identifiable {
    case bar, percent, dual
    var id: String { rawValue }
    var label: String {
        switch self {
        case .bar: return "Bar"
        case .percent: return "Bar + %"
        case .dual: return "Claude + Codex"
        }
    }
}

enum MenuBarLabel {
    static func nsColor(percent: Double, severity: String?) -> NSColor {
        switch severity {
        case "warning": return .systemOrange
        case "exceeded", "critical", "error": return .systemRed
        case "normal": return .controlAccentColor
        default:
            if percent >= 85 { return .systemRed }
            if percent >= 60 { return .systemOrange }
            return .controlAccentColor
        }
    }

    private static func drawBar(_ bar: LimitBar?, in rect: NSRect) {
        let outline = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5),
                                   xRadius: rect.height / 2 - 0.5, yRadius: rect.height / 2 - 0.5)
        NSColor.secondaryLabelColor.setStroke()
        outline.lineWidth = 1
        outline.stroke()
        guard let bar else { return }
        let frac = max(0, min(1, bar.percent / 100))
        let maxWidth = rect.width - 4
        let fillWidth = max(3, maxWidth * frac)
        let fillRect = NSRect(x: rect.minX + 2, y: rect.minY + 2, width: fillWidth, height: rect.height - 4)
        nsColor(percent: bar.percent, severity: bar.severity).setFill()
        NSBezierPath(roundedRect: fillRect, xRadius: (rect.height - 4) / 2, yRadius: (rect.height - 4) / 2).fill()
    }

    static func image(style: MenuBarStyle, selected: LimitBar?, claude: LimitBar?, codex: LimitBar?) -> NSImage {
        switch style {
        case .bar:
            let size = NSSize(width: 26, height: 10)
            return NSImage(size: size, flipped: false) { rect in
                drawBar(selected, in: rect)
                return true
            }
        case .percent:
            let size = NSSize(width: 54, height: 12)
            return NSImage(size: size, flipped: false) { _ in
                drawBar(selected, in: NSRect(x: 0, y: 1, width: 26, height: 10))
                let text = selected.map { "\(Int($0.percent.rounded()))%" } ?? "–"
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .medium),
                    .foregroundColor: NSColor.labelColor,
                ]
                (text as NSString).draw(at: NSPoint(x: 30, y: 0.5), withAttributes: attrs)
                return true
            }
        case .dual:
            let size = NSSize(width: 26, height: 12)
            return NSImage(size: size, flipped: false) { _ in
                drawBar(claude, in: NSRect(x: 0, y: 7, width: 26, height: 5))
                drawBar(codex, in: NSRect(x: 0, y: 0, width: 26, height: 5))
                return true
            }
        }
    }
}
