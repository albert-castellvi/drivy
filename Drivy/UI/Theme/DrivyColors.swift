import SwiftUI
import UIKit

// MARK: - Colour tokens (S3)
//
// One table, one source of truth: `DrivyToken` holds the light and the dark hex
// of every colour of the road design system. Views read the `drivy*` colors, the
// UIKit appearance proxies read `uiColor`, and the contrast test of S7 reads the
// fixed `light` / `dark` pair. Nothing else may hardcode a hex.
//
// Two rules the table encodes (S3):
//   - the sign colours (`signBlue`, `signRed`, `signGlyph`, `caution`) are the
//     same in both appearances, because real signs are retroreflective; only
//     `signFace` dims slightly in dark;
//   - red *text* (wrong answers, relegation, alerts) uses `alertText`, never
//     `signRed`: `signRed` on dark paper is 3.72:1 and fails WCAG AA.

extension UIColor {

    /// A fixed sRGB colour from a `0xRRGGBB` literal. The only way an S3 hex
    /// value enters the app.
    convenience init(drivyHex hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255.0,
            green: CGFloat((hex >> 8) & 0xFF) / 255.0,
            blue: CGFloat(hex & 0xFF) / 255.0,
            alpha: 1.0
        )
    }
}

/// The S3 palette: one case per token, with the light and dark value of S3.
enum DrivyToken: String, CaseIterable {

    /// Screen background: the paper the whole app is printed on.
    case paper

    /// The raised surface of `drivyCard()`, one step lighter than the paper.
    case paperRaised

    /// Hairlines and rules: the separator that replaces card fills.
    case rule

    /// Body text and the darkest ink (nav titles, big numbers).
    case ink

    /// Secondary text, kickers, captions.
    case inkMuted

    /// The road surface itself.
    case asphalt

    /// Edge lines and centre dashes painted on the asphalt.
    case laneMark

    /// Blue directional and information signs, and the app tint.
    case signBlue

    /// The red ring and border of signs. Never for text (see `alertText`).
    case signRed

    /// Red as text: wrong answers, relegation, destructive actions.
    case alertText

    /// The white face a sign is drawn on.
    case signFace

    /// The glyph painted on a sign face.
    case signGlyph

    /// Amber: the lit dashboard lamp and the arrow of the "you are here" pin.
    case caution

    /// Amber as text, dark enough to read on paper.
    case cautionText

    /// A completed quest, a good score: green as text.
    case go

    /// Interactive colour of the app (`.tint`), links, selected chrome.
    case tint

    /// The cap of a streak freeze post (S4: the "hielo" is a coloured cap, no icy
    /// glyph).
    case ice

    /// The light hex of S3.
    var lightHex: UInt32 {
        switch self {
        case .paper: return 0xECEBE6
        case .paperRaised: return 0xF6F5F1
        case .rule: return 0xD6D4CC
        case .ink: return 0x22231F
        case .inkMuted: return 0x5F5D56
        case .asphalt: return 0x34363A
        case .laneMark: return 0xF4F2EA
        case .signBlue: return 0x0F4C8A
        case .signRed: return 0xC8102E
        case .alertText: return 0xC8102E
        case .signFace: return 0xFFFFFF
        case .signGlyph: return 0x1B1B19
        case .caution: return 0xFFB020
        case .cautionText: return 0x9A4A00
        case .go: return 0x1A6B33
        case .tint: return 0x0F4C8A
        case .ice: return 0x8FC1E3
        }
    }

    var darkHex: UInt32 {
        switch self {
        case .paper: return 0x131416
        case .paperRaised: return 0x1D1F21
        case .rule: return 0x2C2F32
        case .ink: return 0xECEAE3
        case .inkMuted: return 0xA3A097
        case .asphalt: return 0x3A3E45
        case .laneMark: return 0xD9D6CC
        case .signBlue: return 0x0F4C8A
        case .signRed: return 0xC8102E
        case .alertText: return 0xF25768
        case .signFace: return 0xF2F0EA
        case .signGlyph: return 0x1B1B19
        case .caution: return 0xFFB020
        case .cautionText: return 0xFFB84D
        case .go: return 0x4CC77F
        case .tint: return 0x6EA6E8
        case .ice: return 0x5E9CC8
        }
    }

    /// The light value, resolved without a trait environment (S7, the share card).
    var light: UIColor { UIColor(drivyHex: lightHex) }

    /// The dark value, resolved without a trait environment.
    var dark: UIColor { UIColor(drivyHex: darkHex) }

    /// The token for one fixed appearance: what the share card of S6 renders with.
    func uiColor(for style: UIUserInterfaceStyle) -> UIColor {
        style == .dark ? dark : light
    }

    /// The token as a dynamic `UIColor`: light value in light mode, dark value in
    /// dark mode. Safe to hand to UIKit appearance proxies.
    var uiColor: UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark ? self.dark : self.light
        }
    }

    /// The token as a `Color`, the form views use.
    var color: Color { Color(uiColor: uiColor) }
}

extension Color {

    /// The one helper every S3 colour goes through: a dynamic `UIColor` built
    /// from the two fixed hex values.
    private static func drivyToken(_ token: DrivyToken) -> Color { token.color }

    static let drivyPaper: Color = Color.drivyToken(.paper)
    static let drivyPaperRaised: Color = Color.drivyToken(.paperRaised)
    static let drivyRule: Color = Color.drivyToken(.rule)
    static let drivyInk: Color = Color.drivyToken(.ink)
    static let drivyInkMuted: Color = Color.drivyToken(.inkMuted)
    static let drivyAsphalt: Color = Color.drivyToken(.asphalt)
    static let drivyLaneMark: Color = Color.drivyToken(.laneMark)
    static let drivySignBlue: Color = Color.drivyToken(.signBlue)
    static let drivySignRed: Color = Color.drivyToken(.signRed)
    static let drivyAlertText: Color = Color.drivyToken(.alertText)
    static let drivySignFace: Color = Color.drivyToken(.signFace)
    static let drivySignGlyph: Color = Color.drivyToken(.signGlyph)
    static let drivyCaution: Color = Color.drivyToken(.caution)
    static let drivyCautionText: Color = Color.drivyToken(.cautionText)
    static let drivyGo: Color = Color.drivyToken(.go)
    static let drivyTint: Color = Color.drivyToken(.tint)
    static let drivyIce: Color = Color.drivyToken(.ice)
}

/// The palette as data, for the tests of S7 and for any tool that needs the
/// fixed pair of a token.
enum DrivyPalette {

    /// Every token with its light and dark `UIColor`, in `DrivyToken` order.
    static let all: [(name: String, light: UIColor, dark: UIColor)] = DrivyToken.allCases.map { token in
        (token.rawValue, token.light, token.dark)
    }
}
