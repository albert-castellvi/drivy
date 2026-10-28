import SwiftUI

/// One Spanish road sign, drawn with `Shape`s: no image asset, no gradient, no
/// shadow (S3, S4).
///
/// The four faces of the system are the four cases of `Kind`. The sign is
/// decorative by default — a row of quests reads its text, not its paint — and
/// becomes one VoiceOver image when a caller passes `accessibilityLabel`.
///
/// Sign colours are fixed in both appearances (S3: real signs are
/// retroreflective), so a `RoadSign` never asks for the palette of the mode.
struct RoadSign: View {

    /// The limit a speed sign shows when the app has no real limit to report:
    /// the urban default the lessons teach, and the only number the system ever
    /// paints on a disc. `QuestSign` and `EventSign` share it.
    static let genericSpeedLimit = 50

    /// The face of the sign, with whatever sits on it.
    enum Kind: Equatable {

        /// White disc, red ring, red diagonal bar: a thing the drive must not do.
        case prohibition(systemName: String)

        /// White triangle, red border: a thing to watch for.
        case warning(systemName: String)

        /// Blue square, white border, white glyph: information.
        case info(systemName: String)

        /// White disc, red ring, black number: the speed limit itself.
        case speedLimit(Int)
    }

    let kind: Kind

    /// Edge of the square the sign is drawn in, kept inside the design range of
    /// S3 (`minSignSize`…`maxSignSize`). A pin is drawn at
    /// `RoadMetrics.signSize`.
    let size: CGFloat

    /// VoiceOver label. `nil` — the default — keeps the sign decorative: a row of
    /// quests reads its text, not its paint. With a label the sign becomes one
    /// image element.
    private let label: String?

    private static let faceColor = Color.drivySignFace
    private static let glyphColor = Color.drivySignGlyph
    private static let redColor = Color.drivySignRed
    private static let blueColor = Color.drivySignBlue

    init(kind: Kind, size: CGFloat = RoadMetrics.signSize, accessibilityLabel: String? = nil) {
        self.kind = kind
        self.size = min(max(size, RoadMetrics.minSignSize), RoadMetrics.maxSignSize)
        self.label = accessibilityLabel
    }

    var body: some View {
        Group {
            if let label {
                paintedFace
                    .accessibilityLabel(label)
                    .accessibilityAddTraits(.isImage)
            } else {
                paintedFace
                    .accessibilityHidden(true)
            }
        }
        .frame(width: size, height: size)
    }

    /// The sign itself, chosen by `kind`.
    @ViewBuilder
    private var paintedFace: some View {
        switch kind {
        case let .prohibition(systemName):
            disc {
                glyphView(systemName, fraction: 0.42, color: Self.glyphColor)
            } bar: {
                slash
            }
        case let .warning(systemName):
            triangle {
                glyphView(systemName, fraction: 0.34, color: Self.glyphColor)
                    .offset(y: size * 0.07)
            }
        case let .info(systemName):
            informationPanel {
                glyphView(systemName, fraction: 0.42, color: Self.faceColor)
            }
        case let .speedLimit(limit):
            disc {
                Text("\(limit)")
                    .font(
                        Font.custom(
                            DrivyFontName.condensedBold,
                            size: size * 0.46,
                            relativeTo: .body
                        )
                        .monospacedDigit()
                    )
                    .foregroundStyle(Self.glyphColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(.horizontal, size * 0.16)
            } bar: {
                EmptyView()
            }
        }
    }

    // MARK: - Faces

    /// The white disc with the red ring, used by prohibition signs and speed
    /// limits. `bar` is painted over the glyph: the diagonal of a prohibition
    /// sign crosses it, exactly like the painted sign.
    private func disc<Content: View, Bar: View>(
        @ViewBuilder _ content: () -> Content,
        @ViewBuilder bar: () -> Bar
    ) -> some View {
        let ring = size * 0.114
        let faceDiameter = size * 0.886

        return ZStack {
            Circle()
                .fill(Self.faceColor)
                .frame(width: faceDiameter, height: faceDiameter)

            content()

            bar()

            Circle()
                .stroke(Self.redColor, lineWidth: ring)
                .frame(width: faceDiameter, height: faceDiameter)
        }
    }

    /// The red diagonal bar of a prohibition sign, bottom-left to top-right as in
    /// the approved mockup.
    private var slash: some View {
        Path { path in
            path.move(to: CGPoint(x: size * 0.22, y: size * 0.78))
            path.addLine(to: CGPoint(x: size * 0.78, y: size * 0.22))
        }
        .stroke(Self.redColor, style: StrokeStyle(lineWidth: size * 0.09, lineCap: .round))
    }

    /// Warning triangle: white face and red border drawn on the same path, so the
    /// sign keeps its size.
    private func triangle<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        let border = size * 0.10
        let shape = RoadSignTriangle(border: border)

        return ZStack {
            shape
                .fill(Self.faceColor)

            shape
                .stroke(
                    Self.redColor,
                    style: StrokeStyle(lineWidth: border, lineCap: .round, lineJoin: .round)
                )

            content()
        }
    }

    /// Blue information panel: a blue square with a white rule inside it.
    private func informationPanel<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        let inset = size * 0.07
        let rule = size * 0.05

        return ZStack {
            RoundedRectangle(cornerRadius: size * 0.12, style: .continuous)
                .fill(Self.blueColor)

            RoundedRectangle(cornerRadius: size * 0.07, style: .continuous)
                .stroke(Self.faceColor, lineWidth: rule)
                .padding(inset)

            content()
        }
    }

    // MARK: - Glyphs

    private func glyphView(_ systemName: String, fraction: CGFloat, color: Color) -> some View {
        Image(systemName: systemName)
            .font(.system(size: size * fraction, weight: .semibold))
            .foregroundStyle(color)
    }
}

/// The warning-triangle path: apex up, base on the bottom rule. Half the border
/// is drawn inside the shape, so the path is pulled in by `border` / 2 and the
/// sign never leaves its frame.
struct RoadSignTriangle: Shape {

    var border: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let box = rect.insetBy(dx: border / 2, dy: border / 2)
        var path = Path()
        path.move(to: CGPoint(x: box.midX, y: box.minY))
        path.addLine(to: CGPoint(x: box.maxX, y: box.maxY))
        path.addLine(to: CGPoint(x: box.minX, y: box.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Previews

#Preview("Road signs · light") {
    RoadSignPreviewRow()
        .padding()
        .background(Color.drivyPaper)
        .preferredColorScheme(.light)
}

#Preview("Road signs · dark") {
    RoadSignPreviewRow()
        .padding()
        .background(Color.drivyPaper)
        .preferredColorScheme(.dark)
}

/// Every face at the pin size, so the two previews above show the whole set.
private struct RoadSignPreviewRow: View {

    var body: some View {
        HStack(spacing: 16) {
            RoadSign(kind: .prohibition(systemName: "iphone"))
            RoadSign(kind: .warning(systemName: "exclamationmark"))
            RoadSign(kind: .info(systemName: "book.closed"))
            RoadSign(kind: .speedLimit(50))
        }
    }
}
