import SwiftUI

/// The road the day is drawn on (S3, S5): a vertical asphalt band with its edge
/// lines and a dashed centre line, running behind the stops.
///
/// The band is a `background` of the stop column, so it is exactly as tall as the
/// stops it carries and it never needs a height of its own.
///
/// `isMoving` animates the centre dashes: the road moves while a drive is being
/// recorded (S9), and stops at once under Reduce Motion.
struct RoadTimeline<Content: View>: View {

    /// `true` while a drive is recording: the dashes scroll towards the viewer.
    var isMoving: Bool = false

    private let content: Content

    init(isMoving: Bool = false, @ViewBuilder content: () -> Content) {
        self.isMoving = isMoving
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: RoadMetrics.stopSpacing) {
            content
        }
        .background(alignment: .topLeading) {
            RoadSurface(isMoving: isMoving)
                .frame(width: RoadMetrics.roadWidth)
        }
    }
}

/// One stop on the road: a pin centred on the asphalt, its content to the right,
/// top-aligned.
struct RoadStop<Pin: View, Content: View>: View {

    /// When `true` the text of the stop is merged into one VoiceOver element
    /// (S6). Set it to `false` when the stop contains its own control, such as
    /// the button that starts a drive: combining would swallow it.
    var combinesText: Bool = true

    private let pin: Pin
    private let content: Content

    init(
        combinesText: Bool = true,
        @ViewBuilder pin: () -> Pin,
        @ViewBuilder content: () -> Content
    ) {
        self.combinesText = combinesText
        self.pin = pin()
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .top, spacing: RoadMetrics.contentGap) {
            pin
                .frame(width: RoadMetrics.roadWidth, alignment: .center)

            content
                .modifier(RoadStopTextModifier(combinesText: combinesText))
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}

/// Merge the row's text into one VoiceOver element, or leave it alone when the
/// stop owns a control (S6: combined elements, never a swallowed button).
private struct RoadStopTextModifier: ViewModifier {

    let combinesText: Bool

    func body(content: Content) -> some View {
        if combinesText {
            content.accessibilityElement(children: .combine)
        } else {
            content
        }
    }
}

extension RoadStop where Pin == RoadSign {

    /// The usual stop: a road sign as its pin.
    init(
        sign: RoadSign.Kind,
        signSize: CGFloat = RoadMetrics.signSize,
        combinesText: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.init(combinesText: combinesText, pin: {
            RoadSign(kind: sign, size: signSize)
        }, content: content)
    }
}

/// The asphalt: the band, its two edge lines and the dashed centre line.
struct RoadSurface: View {

    /// `true` scrolls the centre dashes.
    var isMoving: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color.drivyAsphalt)

            HStack {
                Rectangle()
                    .fill(Color.drivyLaneMark)
                    .frame(width: RoadMetrics.edgeLineWidth)

                Spacer(minLength: 0)

                Rectangle()
                    .fill(Color.drivyLaneMark)
                    .frame(width: RoadMetrics.edgeLineWidth)
            }

            centreLine
        }
    }

    /// The dashes, animated only while a drive records and the user has not
    /// asked for reduced motion.
    @ViewBuilder
    private var centreLine: some View {
        let animate = isMoving && !reduceMotion
        let cycle = RoadMetrics.dashLength + RoadMetrics.dashGap

        if animate {
            TimelineView(.animation(paused: false)) { timeline in
                let seconds = CGFloat(timeline.date.timeIntervalSinceReferenceDate)
                let phase = seconds.truncatingRemainder(dividingBy: cycle)

                RoadDashLine(phase: phase)
                    .fill(Color.drivyLaneMark)
            }
        } else {
            RoadDashLine(phase: 0)
                .fill(Color.drivyLaneMark)
        }
    }
}

/// The centre line of the road, drawn as the dashes themselves so their phase is
/// a plain number: the moving road is one value, not a stroke trick.
struct RoadDashLine: Shape {

    /// How far the dashes have travelled along the road, in points. Growing
    /// values move them towards the viewer, the way the road moves when the car
    /// does.
    var phase: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let cycle = RoadMetrics.dashLength + RoadMetrics.dashGap
        guard cycle > 0, rect.height > 0, rect.width > 0 else { return Path() }

        let dashWidth = min(RoadMetrics.centreLineWidth, rect.width)
        let x = rect.midX - dashWidth / 2
        var path = Path()

        // Start one cycle above the visible top, so the first dash can be cut by
        // the top edge and the pattern reads as continuous. Growing `phase` moves
        // the dashes down the screen: the road coming towards you.
        var y = rect.minY - cycle + phase.truncatingRemainder(dividingBy: cycle)
        while y < rect.maxY {
            let top = max(y, rect.minY)
            let bottom = min(y + RoadMetrics.dashLength, rect.maxY)
            if bottom > top {
                path.addRect(CGRect(x: x, y: top, width: dashWidth, height: bottom - top))
            }
            y += cycle
        }
        return path
    }
}

// MARK: - Previews

private struct RoadTimelinePreview: View {

    var body: some View {
        RoadTimeline(isMoving: false) {
            RoadStop(sign: .info(systemName: "book.closed")) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Por delante")
                        .font(.drivyKicker)
                        .foregroundStyle(Color.drivyInkMuted)

                    Text("Lección de hoy")
                        .font(.drivyHeadline)
                        .foregroundStyle(Color.drivyInk)
                }
            }

            RoadStop(sign: .warning(systemName: "exclamationmark")) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Por delante")
                        .font(.drivyKicker)
                        .foregroundStyle(Color.drivyInkMuted)

                    Text("Frenada suave")
                        .font(.drivyHeadline)
                        .foregroundStyle(Color.drivyInk)
                }
            }

            RoadStop(pin: { KmPost(value: "87", size: KmPostSize.marker) }) {
                Text("13:40 · trayecto")
                    .font(.drivyFootnote)
                    .foregroundStyle(Color.drivyInkMuted)
            }
        }
        .padding()
        .background(Color.drivyPaper)
    }
}

#Preview("Road timeline · light") {
    RoadTimelinePreview()
        .preferredColorScheme(.light)
}

#Preview("Road timeline · dark") {
    RoadTimelinePreview()
        .preferredColorScheme(.dark)
}
