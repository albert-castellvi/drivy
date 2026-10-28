import XCTest
@testable import Drivy

/// U2: the copy of the drive detail is what the driver reads, so it must not leak
/// a specification id. The connected-mode note is the string that used to end in
/// "(S13)"; it lives in one constant so it can be pinned without rendering the
/// screen.
final class DriveDetailCopyTests: XCTestCase {

    /// U2 verbatim: the note of a connected drive, with nothing else on it.
    func testTheConnectedModeNoteKeepsItsWordsAndDropsTheSpecificationID() {
        let note = DriveDetailView.connectedModeNote

        XCTAssertEqual(note, "Conducción conectada: el uso del móvil no penaliza.")
        XCTAssertFalse(note.contains("(S13)"))
    }

    /// The same rule as a shape, so a future spec id of another number is caught
    /// too: user copy never carries a "(S#)" marker.
    func testTheCopyCarriesNoSpecificationIDMarker() {
        let note = DriveDetailView.connectedModeNote

        XCTAssertNil(
            note.range(of: #"\(S\d+\)"#, options: .regularExpression),
            "user copy must not carry a specification id: \(note)"
        )
    }
}
