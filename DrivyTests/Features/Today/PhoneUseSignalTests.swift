import UIKit
import XCTest
@testable import Drivy

/// S5: the phone-use signal of a drive.
///
/// iOS does not tell a running app that the phone was unlocked, so the app infers
/// it from coming back to the foreground during a drive. Which notification means
/// that is the whole rule, so it lives behind `PhoneUseSignal` and is pinned here.
final class PhoneUseSignalTests: XCTestCase {

    /// S5: only coming back **from the background** during a drive is a phone-use
    /// event: locking the screen or switching apps sends the app to the background,
    /// so every real use still counts.
    func testTheSignalIsTheReturnFromTheBackground() {
        XCTAssertEqual(PhoneUseSignal.notification, UIApplication.willEnterForegroundNotification)
    }

    /// The defect: `didBecomeActive` also fires when a system alert closes — the
    /// app's own location permission prompt, Control Center, a notification pull —
    /// without the phone being unlocked for the app, so the first drive was charged
    /// a phone-use event for the app's own dialog.
    func testTheActivationNotificationIsNotTheSignal() {
        XCTAssertNotEqual(PhoneUseSignal.notification, UIApplication.didBecomeActiveNotification)
    }
}
