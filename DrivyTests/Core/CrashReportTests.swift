import XCTest
@testable import Drivy

/// S5: what the app sends to Sentry when something fails is a stable code with a
/// fixed sentence, never the description of the upstream error.
final class CrashReportTests: XCTestCase {

    // MARK: - The report itself

    func testEveryReportHasAStableCode() {
        // The codes are the grouping key of the dashboard: pinning them keeps a
        // reworded sentence from splitting an issue in two.
        XCTAssertEqual(CrashReport.authSignInFailed.code, "auth.signInFailed")
        XCTAssertEqual(CrashReport.authSignOutFailed.code, "auth.signOutFailed")
        XCTAssertEqual(CrashReport.appleSignInFailed.code, "appleSignIn.failed")
    }

    func testEveryReportStartsWithItsCode() {
        for report in CrashReport.allCases {
            XCTAssertTrue(report.reportedText.hasPrefix(report.code), report.code)
            XCTAssertFalse(report.message.isEmpty, report.code)
        }
    }

    func testNoReportCarriesTheDescriptionOfAnotherError() {
        // A report is a value of the enum: it has no field to smuggle text into.
        XCTAssertEqual(CrashReport.authSignInFailed, .authSignInFailed)
        XCTAssertNotEqual(CrashReport.authSignInFailed, .authSignOutFailed)
    }

    // MARK: - Sanitized text

    func testTheTextOfAReportIsKept() {
        for report in CrashReport.allCases {
            XCTAssertEqual(
                CrashReportSanitizer.sanitizedMessage(for: report.reportedText),
                report.reportedText
            )
        }
    }

    func testAnUpstreamDescriptionIsReplacedByTheFallback() {
        // The shape of what a Supabase `AuthError` or a `URLError` description
        // looks like, with the body of the failed request in it.
        let upstream = "The operation couldn't be completed. (Drivy.FakeError error 0.) ana@example.com"

        let text = CrashReportSanitizer.sanitizedMessage(for: upstream)

        XCTAssertEqual(text, CrashReportSanitizer.fallbackText)
        XCTAssertFalse(text.contains("ana@example.com"))
        XCTAssertFalse(text.contains("FakeError"))
    }

    func testAMissingTextBecomesTheFallback() {
        XCTAssertEqual(CrashReportSanitizer.sanitizedMessage(for: nil), CrashReportSanitizer.fallbackText)
    }

    func testTheFallbackIsItsOwnCode() {
        XCTAssertTrue(CrashReportSanitizer.isOwn(CrashReportSanitizer.fallbackText))
        XCTAssertTrue(CrashReportSanitizer.fallbackText.hasPrefix(CrashReportSanitizer.fallbackCode))
    }

    func testAnUnrelatedTextIsNotOwn() {
        XCTAssertFalse(CrashReportSanitizer.isOwn(""))
        XCTAssertFalse(
            CrashReportSanitizer.isOwn("https://thsqgdaadhnnwsadjhrj.supabase.co/auth/v1/token?grant=apple")
        )
        XCTAssertFalse(CrashReportSanitizer.isOwn("league_not_found"))
    }

    /// No capture path may drop its own event: the text the app sends survives the
    /// scrubber, and a second pass changes nothing.
    func testTheSanitizerNeverDropsWhatTheAppSends() {
        var texts = CrashReport.allCases.map(\.reportedText)
        texts.append(CrashReportSanitizer.fallbackText)

        for text in texts {
            XCTAssertTrue(CrashReportSanitizer.isOwn(text), text)
            XCTAssertEqual(CrashReportSanitizer.sanitizedMessage(for: text), text)
            XCTAssertEqual(
                CrashReportSanitizer.sanitizedMessage(for: CrashReportSanitizer.sanitizedMessage(for: text)),
                text,
                "sanitizing is idempotent: a second pass must not fall back"
            )
        }
    }

    // MARK: - What the app reports

    /// The fake of the reporting boundary only sees sanitized reports, so a test
    /// cannot pass by asserting on an error the app never sends.
    func testTheFakeReporterDistinguishesReportsFromRawErrors() {
        let reporter = FakeCrashReporter()
        XCTAssertTrue(reporter.reportedReports.isEmpty)

        reporter.report(UpstreamError())
        XCTAssertTrue(reporter.reportedReports.isEmpty)
        XCTAssertEqual(reporter.reportedErrors.count, 1)

        reporter.report(CrashReport.authSignOutFailed)
        XCTAssertEqual(reporter.reportedReports, [.authSignOutFailed])
        XCTAssertEqual(reporter.reportedErrors.count, 2)
    }

    /// The failures the app can report are the three of the auth flow; anything
    /// else is a text the sanitizer would throw away, so it is not worth a code.
    func testTheSanitizerKnowsOnlyOurCodes() {
        XCTAssertEqual(
            CrashReport.allCases.map(\.code),
            ["auth.signInFailed", "auth.signOutFailed", "appleSignIn.failed"]
        )
        XCTAssertTrue(CrashReport.allCases.allSatisfy { CrashReportSanitizer.isOwn($0.reportedText) })
    }

    /// An error that is not one of ours, used to prove the fake keeps it apart
    /// from a sanitized report.
    private struct UpstreamError: Error {}
}
