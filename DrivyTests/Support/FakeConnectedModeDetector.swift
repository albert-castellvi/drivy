import Foundation
@testable import Drivy

/// Test double for the audio-route boundary (S13).
final class FakeConnectedModeDetector: ConnectedModeDetecting {

    var isConnected = false

    var onChange: ((Bool) -> Void)?

    private(set) var startCount = 0
    private(set) var stopCount = 0

    func start() {
        startCount += 1
    }

    func stop() {
        stopCount += 1
    }

    /// Simulates the car being plugged in (or unplugged) mid-drive.
    func change(to isConnected: Bool) {
        self.isConnected = isConnected
        onChange?(isConnected)
    }
}
