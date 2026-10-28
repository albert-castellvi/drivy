import Foundation
import SwiftUI
import UIKit
import XCTest
@testable import Drivy

/// S3: the type scale of the road is Barlow and Barlow Condensed, bundled under
/// `Drivy/Resources/Fonts/` and registered in `UIAppFonts`. A face that is missing
/// from the bundle does not fail loudly — `DrivyUIFont` falls back to the system
/// font — so these tests are what turn "the app silently lost its typeface" into a
/// red build.
///
/// The tests run inside the app host (`TEST_HOST`), so `UIFont(name:)` resolves
/// through the `UIAppFonts` of the Drivy bundle, exactly like the app at launch.
final class DrivyFontsTests: XCTestCase {

    /// The seven roles of the S3 scale, in the order the table declares them.
    private static var roleNames: [String] {
        ["display", "title", "headline", "body", "bodyStrong", "footnote", "kicker"]
    }

    /// The design size of each role, from S3.
    private static var roleSizes: [String: CGFloat] {
        [
            "display": 44,
            "title": 26,
            "headline": 20,
            "body": 17,
            "bodyStrong": 17,
            "footnote": 13,
            "kicker": 12
        ]
    }

    // MARK: - The bundled faces

    func testEveryBundledPostScriptNameLoadsThroughUIKit() {
        for name in DrivyFontName.all {
            let font = UIFont(name: name, size: 17)

            XCTAssertNotNil(
                font,
                "\"\(name)\" does not load: check that the file is in Drivy/Resources/Fonts, that UIAppFonts lists it and that the PostScript name is exact"
            )
            XCTAssertEqual(
                font?.fontName,
                name,
                "the loaded face of \"\(name)\" reports a different PostScript name"
            )
        }
    }

    /// The file names of `UIAppFonts` are the PostScript names plus `.ttf`; the
    /// plist itself is pinned in `InfoPlistTests`.
    func testBundledFileNamesAreThePostScriptNamesWithTheFontExtension() {
        XCTAssertEqual(
            DrivyFontName.bundledFiles,
            DrivyFontName.all.map { "\($0).ttf" },
            "DrivyFontName.bundledFiles must stay the .ttf of every PostScript name"
        )
    }

    // MARK: - The type roles (S3)

    func testRoleTableHasOneEntryPerS3Role() {
        XCTAssertEqual(
            DrivyUIFont.roles.map { $0.name },
            Self.roleNames,
            "DrivyUIFont.roles must hold exactly one entry per S3 role, in the declared order"
        )
    }

    /// The interesting failure is not "wrong weight": it is a role quietly showing
    /// the system font because its Barlow face never registered.
    func testEveryRoleUsesABundledFaceInsteadOfTheSystemFallback() {
        for role in DrivyUIFont.roles {
            XCTAssertTrue(
                DrivyFontName.all.contains(role.font.fontName),
                "role \"\(role.name)\" resolved to \"\(role.font.fontName)\", which is not a bundled Barlow face: the face is missing and the system fallback is showing"
            )
        }
    }

    func testEveryRoleKeepsItsS3DesignSize() {
        for role in DrivyUIFont.roles {
            let expected = Self.roleSizes[role.name] ?? -1

            XCTAssertEqual(
                role.font.pointSize,
                expected,
                "role \"\(role.name)\" is drawn at \(role.font.pointSize) pt, S3 fixes it at \(expected) pt"
            )
        }
    }

    /// The SwiftUI half of the table: every role is declared, so screens never
    /// hand-roll a `Font.custom` of their own.
    func testSwiftUIRoleForEveryS3RoleIsDeclared() {
        let roles: [Font] = [
            .drivyDisplay,
            .drivyTitle,
            .drivyHeadline,
            .drivyBody,
            .drivyBodyStrong,
            .drivyFootnote,
            .drivyKicker
        ]

        XCTAssertEqual(
            roles.count,
            Self.roleNames.count,
            "every S3 role needs a matching `Font.drivy*` static"
        )
    }
}
