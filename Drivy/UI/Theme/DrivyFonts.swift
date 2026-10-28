import SwiftUI
import UIKit

// MARK: - Type roles (S3)
//
// Barlow carries the reading, Barlow Condensed carries the signage voice, both
// bundled under `Drivy/Resources/Fonts/` and registered in `UIAppFonts`. Every
// role is `Font.custom(_:size:relativeTo:)`, so Dynamic Type still scales the
// custom face instead of freezing it at the design size.
//
// No role is uppercase with tracked-out letters: an eyebrow in this system is a
// plain `drivyKicker` in `drivyInkMuted`.

/// The PostScript names of the bundled faces. They must match the file names
/// listed in `UIAppFonts`; `DrivyFontsTests` fails if a name stops loading.
enum DrivyFontName {

    static let regular = "Barlow-Regular"
    static let medium = "Barlow-Medium"
    static let semiBold = "Barlow-SemiBold"
    static let bold = "Barlow-Bold"
    static let condensedSemiBold = "BarlowCondensed-SemiBold"
    static let condensedBold = "BarlowCondensed-Bold"

    /// Every face the app registers, for the loading test.
    static let all: [String] = [
        regular,
        medium,
        semiBold,
        bold,
        condensedSemiBold,
        condensedBold
    ]

    /// The file names as they appear in `UIAppFonts` (S3, same order as `all`).
    static let bundledFiles: [String] = all.map { "\($0).ttf" }
}

extension Font {

    /// Screen headline: the day, the league, the lesson. Condensed Bold 44.
    static let drivyDisplay = Font.custom(
        DrivyFontName.condensedBold,
        size: 44,
        relativeTo: .largeTitle
    )

    /// Section and screen title. Condensed Bold 26.
    static let drivyTitle = Font.custom(
        DrivyFontName.condensedBold,
        size: 26,
        relativeTo: .title2
    )

    /// Row title, the name of a quest or a drive. Condensed SemiBold 20.
    static let drivyHeadline = Font.custom(
        DrivyFontName.condensedSemiBold,
        size: 20,
        relativeTo: .title3
    )

    /// Reading text. Barlow Regular 17.
    static let drivyBody = Font.custom(DrivyFontName.regular, size: 17, relativeTo: .body)

    /// The emphasis inside reading text: a name, a number that matters.
    static let drivyBodyStrong = Font.custom(DrivyFontName.semiBold, size: 17, relativeTo: .body)

    /// Secondary lines, event captions. Barlow Regular 13.
    static let drivyFootnote = Font.custom(DrivyFontName.regular, size: 13, relativeTo: .footnote)

    /// The small label above a title ("Por delante", "13:40 · trayecto").
    static let drivyKicker = Font.custom(DrivyFontName.semiBold, size: 12, relativeTo: .caption)
}

/// The UIKit half of the same roles. Appearance proxies need a `UIFont`, and a
/// missing face must never crash the app: every lookup falls back to the system
/// font of the same weight, which the tests of S3 then report as a missing font.
enum DrivyUIFont {

    /// The bundled face, or the given system font if it is not registered (a
    /// broken bundle must degrade, not trap).
    static func font(_ name: String, size: CGFloat, fallback: UIFont) -> UIFont {
        UIFont(name: name, size: size) ?? fallback
    }

    static func regular(_ size: CGFloat) -> UIFont {
        font(DrivyFontName.regular, size: size, fallback: .systemFont(ofSize: size))
    }

    static func medium(_ size: CGFloat) -> UIFont {
        font(DrivyFontName.medium, size: size, fallback: .systemFont(ofSize: size, weight: .medium))
    }

    static func semiBold(_ size: CGFloat) -> UIFont {
        font(DrivyFontName.semiBold, size: size, fallback: .systemFont(ofSize: size, weight: .semibold))
    }

    static func bold(_ size: CGFloat) -> UIFont {
        font(DrivyFontName.bold, size: size, fallback: .boldSystemFont(ofSize: size))
    }

    static func condensedSemiBold(_ size: CGFloat) -> UIFont {
        font(DrivyFontName.condensedSemiBold, size: size, fallback: .systemFont(ofSize: size, weight: .semibold))
    }

    static func condensedBold(_ size: CGFloat) -> UIFont {
        font(DrivyFontName.condensedBold, size: size, fallback: .boldSystemFont(ofSize: size))
    }

    /// Every role with its design size, so a test can walk the table instead of
    /// repeating the sizes of S3.
    static let roles: [(name: String, font: UIFont)] = [
        ("display", condensedBold(44)),
        ("title", condensedBold(26)),
        ("headline", condensedSemiBold(20)),
        ("body", regular(17)),
        ("bodyStrong", semiBold(17)),
        ("footnote", regular(13)),
        ("kicker", semiBold(12))
    ]
}
