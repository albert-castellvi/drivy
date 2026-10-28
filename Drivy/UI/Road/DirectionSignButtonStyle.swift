import SwiftUI

/// The primary action of the road: a blue directional sign with an arrow tip and
/// its text in Barlow Condensed (S3).
///
/// The shape is the sign — a rounded left end and a point on the right, the same
/// silhouette the green direction signs use — so the button says where the action
/// leads without an icon. The tip grows with the height of the label, which keeps
/// the angle honest at every Dynamic Type size.
///
/// The label owns the layout, exactly like `GlassButtonStyle`: a call site that
/// wants a full-width action keeps adding its own `.frame(maxWidth: .infinity)`.
/// The touch target is never below 44 pt.
struct DirectionSignButtonStyle: ButtonStyle {

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.drivyTitle)
            .foregroundStyle(Color.drivySignFace)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.leading, 22)
            .padding(.trailing, 30)
            .padding(.vertical, 12)
            .frame(minHeight: 44)
            .background {
                DirectionSignShape()
                    .fill(Color.drivySignBlue)
            }
            .opacity(configuration.isPressed ? 0.85 : 1)
            .contentShape(DirectionSignShape())
    }
}

/// The silhouette of a directional sign: square-ish left corners, an arrow tip on
/// the right edge.
struct DirectionSignShape: Shape {

    /// Radius of the two left corners.
    var cornerRadius: CGFloat = 10

    /// How far the arrow tip reaches into the shape. It never takes more than
    /// half the width, so a narrow label still gets a rectangle.
    var tipDepth: CGFloat = 22

    func path(in rect: CGRect) -> Path {
        let radius = min(max(cornerRadius, 0), min(rect.width, rect.height) / 2)
        let tip = min(max(tipDepth, 0), rect.width / 2)

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + radius, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - tip, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX - tip, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - radius),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.closeSubpath()
        return path
    }
}

extension ButtonStyle where Self == DirectionSignButtonStyle {

    /// `.directionSign()`: the primary action of the app, in the sign vocabulary.
    static var directionSign: DirectionSignButtonStyle { DirectionSignButtonStyle() }
}

// MARK: - Previews

private struct DirectionSignPreview: View {

    var body: some View {
        VStack(spacing: 16) {
            Button("Empezar trayecto") {}
                .buttonStyle(.directionSign)

            Button("Empezar trayecto") {}
                .buttonStyle(.directionSign)
                .frame(maxWidth: .infinity)
                .disabled(true)
                .opacity(0.5)
        }
        .padding()
        .background(Color.drivyPaper)
    }
}

#Preview("Direction sign · light") {
    DirectionSignPreview()
        .preferredColorScheme(.light)
}

#Preview("Direction sign · dark") {
    DirectionSignPreview()
        .preferredColorScheme(.dark)
}
