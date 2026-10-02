import SwiftUI
import UsageBarCore

/// Direction C1 — "Concentric". The reading becomes the object: one lens you can
/// read from the corner of your eye, with both limit windows in the same shape
/// instead of stacked as two separate bars.
///
/// Geometry: a 270° sweep with the gap at the bottom. SwiftUI's `Circle` starts at
/// 3 o'clock and runs clockwise, so rotating by 135° puts the start at 7:30 and
/// the end at 4:30 — the gap centred under the number.
enum Dial {
    static let sweep: CGFloat = 0.75          // 270° of the circle
    static let startAngle: Double = 135

    /// Fraction of the *arc* a percentage occupies.
    static func trimEnd(_ percent: Double) -> CGFloat {
        sweep * CGFloat(max(0, min(100, percent)) / 100)
    }

    /// Same, but never so short that a round cap collapses it into a blob. At 3%
    /// the arc was a stray dot that read as dirt on the glass rather than a value.
    static func arcEnd(_ percent: Double) -> CGFloat {
        percent <= 0 ? 0 : max(trimEnd(percent), 0.022)
    }
}

/// One ring of the dial: recessed track, value arc lit from its own surface.
struct RingGauge: View {
    /// nil = we have no reading. The track still draws — an empty dial with no
    /// track at all reads as a broken disc, which is exactly how it looked.
    let percent: Double?
    let color: Color
    let lineWidth: CGFloat
    /// Where this pace lands by reset. Drawn as a translucent continuation of the
    /// arc rather than a floating pip: "here is where you are heading" is a
    /// direction, and a lone tick on a ring did not say that to anyone.
    var projection: Double? = nil
    var dimmed: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Critically damped, and slow enough to be followed by eye. Every layer of
    /// the ring animates on this same clock — the sheen used to snap to the new
    /// value while the arc underneath was still travelling.
    static let motion = Animation.spring(duration: 0.55, bounce: 0)

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: Dial.sweep)
                .stroke(Color.primary.opacity(0.11),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))

            // Ghost of the forecast first, so the solid value sits on top of it.
            if let percent, let projection, projection > percent {
                Circle()
                    .trim(from: Dial.trimEnd(percent), to: Dial.trimEnd(min(100, projection)))
                    // Dashed and faint: a solid ghost outweighed the real value —
                    // at 6% used and 49% forecast, the forecast looked like the
                    // reading. A forecast should whisper, not announce.
                    .stroke(color.opacity(0.22),
                            style: StrokeStyle(lineWidth: lineWidth * 0.34, lineCap: .butt,
                                               dash: [1.5, 3]))
                // Overshoot past 100% turns amber: you run out before the reset.
                if projection > 100 {
                    Circle()
                        .trim(from: Dial.sweep - 0.02, to: Dial.sweep)
                        .stroke(Color.orange.opacity(0.85),
                                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                }
            }

            if let percent {
                Circle()
                    .trim(from: 0, to: Dial.arcEnd(percent))
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .overlay(
                        // Angular, not linear: a top-to-bottom sheen leaves the
                        // bottom of a 270° arc looking dead. This one follows the
                        // curve, the way light actually runs along glass.
                        Circle()
                            .trim(from: 0, to: Dial.arcEnd(percent))
                            .stroke(AngularGradient(
                                        colors: [.white.opacity(0.02), .white.opacity(0.34),
                                                 .white.opacity(0.10), .white.opacity(0.02)],
                                        center: .center,
                                        angle: .degrees(-90)),
                                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    )
                    .opacity(dimmed ? 0.72 : 1)
            }
        }
        .rotationEffect(.degrees(Dial.startAngle))
        // On the container, not on one layer: the arc, its sheen and the forecast
        // ghost all move together, and the colour crossfades with them when a
        // threshold is crossed mid-travel.
        .animation(reduceMotion ? nil : Self.motion, value: percent)
        .animation(reduceMotion ? nil : Self.motion, value: projection)
        .animation(reduceMotion ? nil : Self.motion, value: color)
    }
}

/// The full dial: outer ring for the tightest window, inner for the next one,
/// the number of the tightest in the middle.
struct ConcentricDial: View {
    let outer: LimitBar?
    let inner: LimitBar?
    let reading: String
    let readingCaption: String
    let readingColor: Color
    let outerColor: Color
    let innerColor: Color
    /// The inner ring, spelled out under the big number. Without it the dial had
    /// two arcs and one label, and you had to go read the legend to learn which
    /// arc was which — the dial was not saying anything on its own.
    let secondaryLine: String?
    /// Sits in the 90° gap at the bottom, which was otherwise dead space.
    let footnote: String?
    let projection: Double?
    let dimmed: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            // No filled puck: the popover is already a sheet of glass, and a disc
            // behind the rings is glass on glass — it read as a grey blob.
            RingGauge(percent: outer?.percent, color: outerColor, lineWidth: 11,
                      projection: projection, dimmed: dimmed)
                .padding(6)
            if inner != nil {
                // Pulled well inside the outer ring: at 8pt vs 26pt of padding the
                // two arcs were nearly the same radius. Thinner and quieter too —
                // the session is the headline, and a weekly arc at 63% beside a
                // session at 3% otherwise steals the eye from the number.
                // Moved OUT, not in. Pushing it inward to clear the text shrank the
                // hole it had to clear; sitting closer to the outer ring leaves a
                // 111pt centre, which is what three lines of text actually need.
                // 12pt of clear space still separates the two strokes.
                RingGauge(percent: inner?.percent, color: innerColor, lineWidth: 5, dimmed: dimmed)
                    .padding(26)
                    .opacity(0.75)
            }

            VStack(spacing: 0) {
                Text(reading)
                    // A dash rendered at 42pt ultralight is a hairline, not a
                    // reading — placeholders get a weight you can actually see.
                    // ultraLight turns "0" into a hairline oval and "—" into a
                    // stray line; .light keeps the airiness and stays a numeral.
                    .font(.system(size: outer == nil ? 24 : 36,
                                  weight: outer == nil ? .regular : .light))
                    .monospacedDigit()
                    .kerning(outer == nil ? 0 : -1.2)
                    .foregroundStyle(outer == nil ? AnyShapeStyle(.secondary)
                                     : AnyShapeStyle(readingColor.opacity(dimmed ? 0.7 : 1)))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .fixedSize()
                    // Digits roll instead of cutting to the new value.
                    .contentTransition(.numericText())
                    .animation(reduceMotion ? nil : RingGauge.motion, value: reading)
                    .animation(reduceMotion ? nil : RingGauge.motion, value: readingColor)
                Text(readingCaption)
                    .font(.system(size: 8.5, weight: .semibold))
                    .tracking(0.4)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.top, 3)
                if let secondaryLine {
                    Text(secondaryLine)
                        .font(.system(size: 9.5, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(innerColor.opacity(dimmed ? 0.5 : 0.75))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.top, 5)
                        .contentTransition(.numericText())
                        .animation(reduceMotion ? nil : RingGauge.motion, value: secondaryLine)
                }
            }
            .padding(.horizontal, 30)
            // The gap sits at the bottom, so the optical centre is above the
            // geometric one — and this lifts the text clear of the inner arc.
            .offset(y: -7)

            if let footnote {
                VStack {
                    Spacer()
                    Text(footnote)
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        // fixedSize, not minimumScaleFactor: the dial's frame is
                        // only 168pt but the popover gives 292, so the line is
                        // allowed to overflow the ring and use the real width
                        // instead of shrinking itself to fit a box it only
                        // happens to be drawn inside.
                        .fixedSize()
                }
                .padding(.bottom, -2)
            }
        }
        // 168: three lines of text inside a ring need a bigger hole than two did.
        // At 152 the weekly line ran into the inner arc.
        .frame(width: 168, height: 168)
    }
}

/// Provider switcher entry: the same dial at 30pt, so comparing four providers
/// needs no second screen and no different visual language.
struct MiniRing: View {
    let outer: Double?
    let inner: Double?
    let color: Color
    let dimmed: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: Dial.sweep)
                .stroke(Color.primary.opacity(0.12), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(Dial.startAngle))
            if let outer {
                Circle()
                    .trim(from: 0, to: Dial.trimEnd(outer))
                    .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(Dial.startAngle))
                    .opacity(dimmed ? 0.72 : 1)
            }
            if let inner {
                Circle()
                    .trim(from: 0, to: Dial.trimEnd(inner))
                    .stroke(color.opacity(0.75), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                    .rotationEffect(.degrees(Dial.startAngle))
                    .padding(5.5)
                    .opacity(dimmed ? 0.72 : 1)
            }
        }
        .frame(width: 30, height: 30)
        // The switcher's dials were static: four meters that never moved while the
        // big one did, which made the popover look half-alive.
        .animation(reduceMotion ? nil : RingGauge.motion, value: outer)
        .animation(reduceMotion ? nil : RingGauge.motion, value: inner)
        .animation(reduceMotion ? nil : RingGauge.motion, value: color)
    }
}

/// One line of the dial's legend — the labelling the rings themselves can't carry.
struct RingLegendRow: View {
    let bar: LimitBar
    let color: Color
    let now: Date
    /// 0 = outer ring, 1 = inner ring, 2+ = a limit the dial has no room to draw.
    /// Identical dots left you guessing which row was which; the glyph mirrors the
    /// nesting you see in the dial, and rows past the second get a plain tick so
    /// they do not pretend to be on it.
    let ring: Int

    var body: some View {
        HStack(spacing: 7) {
            Group {
                switch ring {
                case 0: Circle().strokeBorder(color, lineWidth: 2)
                case 1: Circle().fill(color).padding(1.5)
                // Not on a ring at all — small, but not so small it vanishes when
                // it is the row that matters, like a model sitting at 100%.
                default: Circle().fill(color).padding(2)
                }
            }
            .frame(width: 8, height: 8)
            .opacity(bar.severity == "stale" ? 0.6 : 1)
            Text(bar.label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Text("\(Int(bar.percent.rounded()))%")
                .font(.system(size: 11))
                .monospacedDigit()
            Spacer(minLength: 6)
            Text(bar.severity == "stale" ? "window already reset"
                 : bar.resetsAt.map { Format.resetsIn($0, now: now).replacingOccurrences(of: "Resets in", with: "resets in") } ?? "")
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .padding(.vertical, 2)
    }
}
