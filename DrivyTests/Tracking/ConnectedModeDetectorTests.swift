import AVFoundation
import XCTest
@testable import Drivy

/// S13: the port mapping is the whole rule, so it is tested without an audio
/// session. `.bluetoothHFP` is the Hands-Free Profile port ("bluetoothHandsfree"
/// in the spec): a car kit, not a pair of headphones.
final class ConnectedModeDetectorTests: XCTestCase {

    func testCarPlayCountsAsConnectedDriving() {
        XCTAssertTrue(AudioRouteConnectedModeDetector.isCarAudioRoute([.carAudio]))
    }

    func testCarHandsFreeBluetoothCountsAsConnectedDriving() {
        XCTAssertTrue(AudioRouteConnectedModeDetector.isCarAudioRoute([.bluetoothHFP]))
    }

    func testCarStereoBluetoothCountsAsConnectedDriving() {
        XCTAssertTrue(AudioRouteConnectedModeDetector.isCarAudioRoute([.bluetoothA2DP]))
    }

    func testAnyCarPortInTheRouteIsEnough() {
        XCTAssertTrue(
            AudioRouteConnectedModeDetector.isCarAudioRoute([.builtInSpeaker, .bluetoothA2DP])
        )
    }

    func testNonCarRoutesAreNotConnectedDriving() {
        XCTAssertFalse(AudioRouteConnectedModeDetector.isCarAudioRoute([]))
        XCTAssertFalse(AudioRouteConnectedModeDetector.isCarAudioRoute([.builtInSpeaker]))
        XCTAssertFalse(AudioRouteConnectedModeDetector.isCarAudioRoute([.headphones]))
        XCTAssertFalse(AudioRouteConnectedModeDetector.isCarAudioRoute([.bluetoothLE]))
    }
}
