import Foundation
import UIKit
import XCTest
@testable import Drivy

/// S3 + S7: the palette is only a design system if every text token stays legible
/// on both surfaces of the app, in both appearances. The contract of S7 is WCAG
/// AA — at least 4.5:1 for body text, 4.5:1 for the white of a blue sign, and
/// 3:1 for the road paint, which is a large graphical element and not text.
///
/// The tests read the fixed light/dark pair of each token (`uiColor(for:)`), the
/// same values the app resolves at runtime, and one test walks the dynamic
/// `UIColor` through a `UITraitCollection` to prove the two appearances agree with
/// the pair. A failure names the pair, so a broken token points at itself instead
/// of at "the palette".
final class DesignTokensTests: XCTestCase {

    /// What every assertion of S7 is written against.
    private enum Appearance: String, CaseIterable {

        case light
        case dark

        var style: UIUserInterfaceStyle {
            self == .dark ? .dark : .light
        }
    }

    /// AA for body text (S7).
    private static let minimumTextContrast: CGFloat = 4.5

    /// AA for large text and for graphical objects such as painted road lines.
    private static let minimumLargeTextContrast: CGFloat = 3.0

    /// The two surfaces any text of the app sits on (S3, `drivyCard()`).
    private static var surfaces: [(name: String, token: DrivyToken)] {
        [
            ("paper", .paper),
            ("paperRaised", .paperRaised)
        ]
    }

    // MARK: - Text tokens on both surfaces (S3, S7)

    func testInkMeetsAAOnBothSurfacesInBothAppearances() {
        assertTextTokenMeetsAA(.ink)
    }

    func testInkMutedMeetsAAOnBothSurfacesInBothAppearances() {
        assertTextTokenMeetsAA(.inkMuted)
    }

    func testTintMeetsAAOnBothSurfacesInBothAppearances() {
        assertTextTokenMeetsAA(.tint)
    }

    func testCautionTextMeetsAAOnBothSurfacesInBothAppearances() {
        assertTextTokenMeetsAA(.cautionText)
    }

    func testGoMeetsAAOnBothSurfacesInBothAppearances() {
        assertTextTokenMeetsAA(.go)
    }

    /// Red as *text* is `alertText`, never `signRed`: the ring of a sign is a
    /// 3 pt stroke and only has to meet the graphical threshold, the wrong-answer
    /// line is reading text and has to meet AA (S3).
    func testAlertTextMeetsAAOnBothSurfacesInBothAppearances() {
        assertTextTokenMeetsAA(.alertText)
    }

    // MARK: - The road itself (S3, S7)

    /// The edge lines and the centre dashes are what make the asphalt read as a
    /// road, especially in dark mode where asphalt is only slightly lighter than
    /// the paper. They are graphics, not text, so the bar is 3:1.
    func testLaneMarkKeepsTheRoadLegibleOnAsphalt() {
        for appearance in Appearance.allCases {
            assertContrast(
                DrivyToken.laneMark.uiColor(for: appearance.style),
                on: DrivyToken.asphalt.uiColor(for: appearance.style),
                atLeast: Self.minimumLargeTextContrast,
                pair: "laneMark/asphalt",
                appearance: appearance
            )
        }
    }

    /// The glyph of a blue information sign is white on `signBlue` in both
    /// appearances (S3: sign colours are fixed, real signs are retroreflective).
    func testWhiteReadsOnTheBlueSignFace() {
        for appearance in Appearance.allCases {
            assertContrast(
                UIColor.white,
                on: DrivyToken.signBlue.uiColor(for: appearance.style),
                atLeast: Self.minimumTextContrast,
                pair: "white/signBlue",
                appearance: appearance
            )
        }
    }

    // MARK: - The dynamic colour resolves to the fixed pair

    /// `Color.drivy*` is built on a dynamic `UIColor`. If the trait branch of that
    /// colour ever stops matching `uiColor(for:)`, the views and the contrast test
    /// would be reading two different palettes.
    func testEveryTokenResolvesToItsFixedValueInBothAppearances() {
        for token in DrivyToken.allCases {
            for appearance in Appearance.allCases {
                let resolved = token.uiColor.resolvedColor(
                    with: UITraitCollection(userInterfaceStyle: appearance.style)
                )
                let fixed = token.uiColor(for: appearance.style)
                let pair = "\(token.rawValue) in \(appearance.rawValue) mode"

                guard let resolvedComponents = srgbComponents(of: resolved),
                      let fixedComponents = srgbComponents(of: fixed) else {
                    XCTFail("could not read the sRGB components of \(pair)")
                    continue
                }

                XCTAssertEqual(
                    resolvedComponents.red,
                    fixedComponents.red,
                    accuracy: 0.001,
                    "red of \(pair)"
                )
                XCTAssertEqual(
                    resolvedComponents.green,
                    fixedComponents.green,
                    accuracy: 0.001,
                    "green of \(pair)"
                )
                XCTAssertEqual(
                    resolvedComponents.blue,
                    fixedComponents.blue,
                    accuracy: 0.001,
                    "blue of \(pair)"
                )
            }
        }
    }

    // MARK: - Assertions

    /// One text token against both surfaces of both appearances, at AA.
    private func assertTextTokenMeetsAA(
        _ token: DrivyToken,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for appearance in Appearance.allCases {
            for surface in Self.surfaces {
                assertContrast(
                    token.uiColor(for: appearance.style),
                    on: surface.token.uiColor(for: appearance.style),
                    atLeast: Self.minimumTextContrast,
                    pair: "\(token.rawValue)/\(surface.name)",
                    appearance: appearance,
                    file: file,
                    line: line
                )
            }
        }
    }

    private func assertContrast(
        _ foreground: UIColor,
        on background: UIColor,
        atLeast minimum: CGFloat,
        pair: String,
        appearance: Appearance,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let ratio = contrastRatio(of: foreground, on: background) else {
            XCTFail(
                "could not read the sRGB components of \(pair) in \(appearance.rawValue) mode",
                file: file,
                line: line
            )
            return
        }

        let measured = String(format: "%.2f", Double(ratio))
        let required = String(format: "%.1f", Double(minimum))
        XCTAssertGreaterThanOrEqual(
            ratio,
            minimum,
            "\(pair) is \(measured):1 in \(appearance.rawValue) mode, below the \(required):1 of WCAG AA (S7)",
            file: file,
            line: line
        )
    }

    // MARK: - WCAG 2.1 relative luminance and contrast

    private func contrastRatio(of first: UIColor, on second: UIColor) -> CGFloat? {
        guard let firstLuminance = relativeLuminance(of: first),
              let secondLuminance = relativeLuminance(of: second) else {
            return nil
        }

        let lighter = max(firstLuminance, secondLuminance)
        let darker = min(firstLuminance, secondLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    /// WCAG 2.1 relative luminance from the sRGB components of the colour.
    private func relativeLuminance(of color: UIColor) -> CGFloat? {
        guard let components = srgbComponents(of: color) else { return nil }
        return 0.2126 * linearComponent(components.red)
            + 0.7152 * linearComponent(components.green)
            + 0.0722 * linearComponent(components.blue)
    }

    /// The sRGB transfer function: the linear value of one 0…1 component.
    private func linearComponent(_ component: CGFloat) -> CGFloat {
        if component <= 0.04045 {
            return component / 12.92
        }

        let base = (Double(component) + 0.055) / 1.055
        return CGFloat(pow(base, 2.4))
    }

    private func srgbComponents(
        of color: UIColor
    ) -> (red: CGFloat, green: CGFloat, blue: CGFloat)? {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return nil
        }
        return (red, green, blue)
    }
}
