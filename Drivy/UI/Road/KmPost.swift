import SwiftUI

/// The hitto of the system: a white post with a coloured cap, the mark of one
/// day on the road (S3).
///
/// It carries the day's number (a score, a distance) or nothing at all, which is
/// what a streak row uses: seven posts, one per day.
///
/// The cap says what the day was: `drivySignRed` for a day that counts,
/// `drivyIce` for a streak freeze — S4 forbids an icy glyph, the colour is the
/// message. A day with no drive and no freeze is drawn pending: a dashed rule and
/// an empty cap, so the row never claims a day it did not earn.
struct KmPost<Content: View>: View {

    /// The two sizes of the system: the marker of a streak row, and the score
    /// post of a screen header (both from the approved mockup).
    enum Size {

        static let marker = CGSize(width: 38, height: 52)

        static let score = CGSize(width: 74, height: 92)
    }

    /// Colour of the cap.
    let capColor: Color

    /// `true` draws the ring of the current day, so the row reads without
    /// relying on colour alone.
    let isToday: Bool

    /// `true` draws a day with nothing on it yet: dashed rule, no cap fill.
    let isPending: Bool

    /// Design size of the post; it grows with the text size.
    let size: CGSize

    /// VoiceOver label. With one, the post is announced as a single element with
    /// this text; without one, the content keeps speaking for itself and an
    /// empty marker post says nothing at all.
    private let label: String?

    private let content: Content

    /// The post grows with Dynamic Type instead of clipping its number.
    @ScaledMetric(relativeTo: .body) private var textScale: CGFloat = 1

    init(
        capColor: Color = Color.drivySignRed,
        isToday: Bool = false,
        isPending: Bool = false,
        size: CGSize = Size.marker,
        accessibilityLabel: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.capColor = capColor
        self.isToday = isToday
        self.isPending = isPending
        self.size = size
        self.label = accessibilityLabel
        self.content = content()
    }

    var body: some View {
        let width = size.width * textScale
        let height = size.height * textScale
        let radius = width / 2
        let bottomRadius = width * 0.08
        let capHeight = height * 0.29
        let shape = KmPostShape(topRadius: radius, bottomRadius: bottomRadius)
        let borderWidth: CGFloat = 1.5
        let dashPattern: [CGFloat] = isPending ? [3, 3] : []
        let borderColor: Color = isPending
            ? Color.drivyInkMuted
            : Color.drivyRule

        return ZStack {
            shape
                .fill(isPending ? Color.clear : Color.drivySignFace)
                .overlay(alignment: .top) {
                    if !isPending {
                        Rectangle()
                            .fill(capColor)
                            .frame(height: capHeight)
                    }
                }
                .clipShape(shape)

            shape
                .stroke(
                    borderColor,
                    style: StrokeStyle(lineWidth: borderWidth, dash: dashPattern)
                )

            content
                .padding(.top, capHeight)
        }
        .overlay {
            if isToday {
                shape
                    .stroke(Color.drivyTint, lineWidth: 2)
                    .padding(-3)
            }
        }
        .frame(width: width, height: height)
        .modifier(KmPostAccessibility(label: label))
    }
}

/// One element with the caller's words, or the plain text of the post when the
/// caller said nothing (S6: the score must stay readable by VoiceOver).
private struct KmPostAccessibility: ViewModifier {

    let label: String?

    func body(content: Content) -> some View {
        if let label {
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(label)
        } else {
            content
        }
    }
}

/// The number of a score post: the display role in ink, one line, tabular
/// figures, allowed to shrink instead of clipping.
struct KmPostValue: View {

    let value: String

    var body: some View {
        Text(value)
            .font(.drivyDisplay)
            .monospacedDigit()
            .foregroundStyle(Color.drivyInk)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }
}

extension KmPost where Content == KmPostValue {

    /// The score post: one number on the white body.
    init(
        value: String,
        capColor: Color = Color.drivySignRed,
        isToday: Bool = false,
        isPending: Bool = false,
        size: CGSize = Size.score,
        accessibilityLabel: String? = nil
    ) {
        self.init(
            capColor: capColor,
            isToday: isToday,
            isPending: isPending,
            size: size,
            accessibilityLabel: accessibilityLabel,
            content: { KmPostValue(value: value) }
        )
    }
}

/// The post silhouette: a wide round top and an almost square bottom, like the
/// concrete hitos on the shoulder of a Spanish road.
struct KmPostShape: Shape {

    var topRadius: CGFloat = 0

    var bottomRadius: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let top = min(max(topRadius, 0), min(rect.width, rect.height) / 2)
        let bottom = min(max(bottomRadius, 0), min(rect.width, rect.height) / 2)

        var path = Path()
        path.move(to: CGPoint(x: rect.minX + top, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - top, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + top),
            control: CGPoint(x: rect.maxX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottom))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - bottom, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + bottom, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - bottom),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + top))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + top, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}

// MARK: - Previews

private struct KmPostPreviewRow: View {

    var body: some View {
        HStack(alignment: .bottom, spacing: 14) {
            KmPost(value: "87")
            KmPost(capColor: Color.drivyIce) { EmptyView() }
            KmPost(isToday: true) { EmptyView() }
            KmPost(isPending: true) { EmptyView() }
        }
    }
}

#Preview("Km posts · light") {
    KmPostPreviewRow()
        .padding()
        .background(Color.drivyPaper)
        .preferredColorScheme(.light)
}

#Preview("Km posts · dark") {
    KmPostPreviewRow()
        .padding()
        .background(Color.drivyPaper)
        .preferredColorScheme(.dark)
}
