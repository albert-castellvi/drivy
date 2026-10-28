import SwiftUI
import XCTest
@testable import Drivy

/// S8, on top of S3 and S4: the visual proof of the design system. One sheet holds
/// the whole vocabulary — every colour token, every type role, every sign face, the
/// three `KmPost` states, a road with three stops, the directional button and both
/// states of the warning lamp — and `renderGallery` produces its light and its dark
/// PNG.
///
/// The copy is fixture text of the app in Spanish, so the sheet shows the real
/// typeface on real words instead of lorem ipsum, and nothing in it is a gradient,
/// a shadow or an emoji (S4).
@MainActor
final class DesignSystemGalleryTests: XCTestCase {

    /// Taller than a phone on purpose: the sheet is one page a reviewer reads top
    /// to bottom, not a scrolling screen, and the fixed frame keeps the whole
    /// vocabulary inside the image.
    private static let sheetWidth: CGFloat = 390

    private static let sheetHeight: CGFloat = 1_400

    func testDesignSystemSheetRendersInLightAndDark() {
        renderGallery(
            "design-system",
            width: Self.sheetWidth,
            height: Self.sheetHeight
        ) {
            DesignSystemSheet()
        }
    }
}

// MARK: - The sheet

/// The fixture sheet of the gallery.
private struct DesignSystemSheet: View {

    /// One row of the type scale: the name of the role as a kicker, the sample set
    /// in the role itself.
    private struct TypeRole {

        let name: String

        let font: Font

        let sample: String
    }

    /// One sign face with the word the sheet calls it by.
    private struct SignFace {

        let name: String

        let kind: RoadSign.Kind
    }

    private static var typeRoles: [TypeRole] {
        [
            TypeRole(name: "display", font: .drivyDisplay, sample: "83"),
            TypeRole(name: "title", font: .drivyTitle, sample: "Camino de hoy"),
            TypeRole(name: "headline", font: .drivyHeadline, sample: "Lección de hoy"),
            TypeRole(name: "body", font: .drivyBody, sample: "Trayecto de 2 km o más con nota 90."),
            TypeRole(name: "bodyStrong", font: .drivyBodyStrong, sample: "Cero móvil"),
            TypeRole(name: "footnote", font: .drivyFootnote, sample: "13:40 · trayecto"),
            TypeRole(name: "kicker", font: .drivyKicker, sample: "Por delante")
        ]
    }

    private static var signFaces: [SignFace] {
        [
            SignFace(name: "Prohibición", kind: .prohibition(systemName: "iphone")),
            SignFace(name: "Aviso", kind: .warning(systemName: "exclamationmark")),
            SignFace(name: "Información", kind: .info(systemName: "book.closed")),
            SignFace(name: "Límite", kind: .speedLimit(RoadSign.genericSpeedLimit))
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header
            colourSection
            typeSection
            signSection
            kmPostSection
            timelineSection
            actionSection
            lampSection
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Sistema de diseño")
                .font(.drivyKicker)
                .foregroundStyle(DrivyToken.inkMuted.color)

            Text("Drivy")
                .font(.drivyDisplay)
                .foregroundStyle(DrivyToken.ink.color)
        }
    }

    private var colourSection: some View {
        section("Color") {
            HStack(alignment: .top, spacing: 16) {
                colourColumn(Array(DrivyToken.allCases.prefix(9)))
                colourColumn(Array(DrivyToken.allCases.suffix(8)))
            }
        }
    }

    private func colourColumn(_ tokens: [DrivyToken]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(tokens, id: \.rawValue) { token in
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(token.color)
                        .frame(width: 20, height: 20)
                        .overlay {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .stroke(DrivyToken.rule.color, lineWidth: 1)
                        }

                    Text(token.rawValue)
                        .font(.drivyFootnote)
                        .foregroundStyle(DrivyToken.ink.color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var typeSection: some View {
        section("Tipografía") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Self.typeRoles, id: \.name) { role in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(role.name)
                            .font(.drivyKicker)
                            .foregroundStyle(DrivyToken.inkMuted.color)
                            .frame(width: 78, alignment: .leading)

                        Text(role.sample)
                            .font(role.font)
                            .foregroundStyle(DrivyToken.ink.color)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                    }
                }
            }
        }
    }

    private var signSection: some View {
        section("Señales") {
            HStack(alignment: .top, spacing: 16) {
                ForEach(Self.signFaces, id: \.name) { face in
                    VStack(spacing: 6) {
                        RoadSign(kind: face.kind, size: RoadMetrics.signSize)

                        caption(face.name)
                    }
                }
            }
        }
    }

    private var kmPostSection: some View {
        section("Hitos") {
            HStack(alignment: .bottom, spacing: 18) {
                VStack(spacing: 6) {
                    KmPost(value: "83", isToday: true, accessibilityLabel: "Nota de hoy: 83")
                    caption("Nota de hoy")
                }

                VStack(spacing: 6) {
                    KmPost(capColor: DrivyToken.ice.color, accessibilityLabel: "Hielo disponible") {
                        EmptyView()
                    }
                    caption("Hielo")
                }

                VStack(spacing: 6) {
                    KmPost(isToday: true, accessibilityLabel: "Hoy") {
                        EmptyView()
                    }
                    caption("Hoy")
                }

                VStack(spacing: 6) {
                    KmPost(isPending: true, accessibilityLabel: "Sin trayecto") {
                        EmptyView()
                    }
                    caption("Pendiente")
                }
            }
        }
    }

    private var timelineSection: some View {
        section("Camino de hoy") {
            RoadTimeline(isMoving: false) {
                RoadStop(sign: .info(systemName: "book.closed")) {
                    stopText(kicker: "Por delante", title: "Lección de hoy")
                }

                RoadStop(sign: .warning(systemName: "exclamationmark")) {
                    stopText(kicker: "Por delante", title: "Frenada suave")
                }

                RoadStop(sign: .prohibition(systemName: "iphone")) {
                    stopText(kicker: "Ahora", title: "Cero móvil")
                }
            }
        }
    }

    private var actionSection: some View {
        section("Acción") {
            Button("Empezar trayecto") {}
                .buttonStyle(.directionSign)
        }
    }

    private var lampSection: some View {
        section("Avisos del cuadro") {
            HStack(spacing: 24) {
                WarningLamp(systemName: "exclamationmark", isLit: true, caption: "1 frenada")
                WarningLamp(systemName: "iphone", isLit: false, caption: "Móvil")
            }
        }
    }

    // MARK: - Pieces

    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.drivyKicker)
                .foregroundStyle(DrivyToken.inkMuted.color)

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func stopText(kicker: String, title: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(kicker)
                .font(.drivyKicker)
                .foregroundStyle(DrivyToken.inkMuted.color)

            Text(title)
                .font(.drivyHeadline)
                .foregroundStyle(DrivyToken.ink.color)
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.drivyKicker)
            .foregroundStyle(DrivyToken.inkMuted.color)
            .lineLimit(1)
    }
}
