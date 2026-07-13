import AppKit
import SwiftUI

enum MenuBarLabel {
    static func color(for percent: Double) -> NSColor {
        if percent >= 85 { return .systemRed }
        if percent >= 60 { return .systemOrange }
        return .controlAccentColor
    }

    static func barImage(percent: Double?) -> NSImage {
        let size = NSSize(width: 26, height: 10)
        let image = NSImage(size: size, flipped: false) { rect in
            let outline = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 4.5, yRadius: 4.5)
            NSColor.secondaryLabelColor.setStroke()
            outline.lineWidth = 1
            outline.stroke()
            if let percent {
                let frac = max(0, min(1, percent / 100))
                let maxWidth = rect.width - 4
                let fillWidth = max(3, maxWidth * frac)
                let fillRect = NSRect(x: 2, y: 2, width: fillWidth, height: rect.height - 4)
                color(for: percent).setFill()
                NSBezierPath(roundedRect: fillRect, xRadius: 3, yRadius: 3).fill()
            }
            return true
        }
        image.isTemplate = false
        return image
    }
}
