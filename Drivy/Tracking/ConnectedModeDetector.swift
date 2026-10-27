import AVFoundation
import Foundation

/// Boundary between the drive recorder and the audio route, so S13 detection
/// can be tested without an audio session.
protocol ConnectedModeDetecting: AnyObject {

    /// Whether the phone is currently routing audio through the car.
    var isConnected: Bool { get }

    /// Called on the main queue when the answer changes.
    var onChange: ((Bool) -> Void)? { get set }

    func start()

    func stop()
}

/// S13: connected driving is detected from the audio route — CarPlay reports
/// `.carAudio`, a car hands-free kit `.bluetoothHFP` (the Hands-Free Profile the
/// spec calls "bluetoothHandsfree") or `.bluetoothA2DP` — and needs no
/// entitlement.
///
/// The session is never activated on purpose: activating it would interrupt
/// whatever the user is listening to. Reading `currentRoute` and observing route
/// changes is enough for detection.
final class AudioRouteConnectedModeDetector: ConnectedModeDetecting {

    var onChange: ((Bool) -> Void)?

    private let session: AVAudioSession
    private var observer: NSObjectProtocol?
    private var lastValue = false

    init(session: AVAudioSession = .sharedInstance()) {
        self.session = session
    }

    var isConnected: Bool {
        Self.isCarAudioRoute(Set(session.currentRoute.outputs.map(\.portType)))
    }

    /// Pure mapping of output ports to "connected driving": testable without an
    /// audio session.
    static func isCarAudioRoute(_ ports: Set<AVAudioSession.Port>) -> Bool {
        ports.contains(.carAudio)
            || ports.contains(.bluetoothHFP)
            || ports.contains(.bluetoothA2DP)
    }

    func start() {
        guard observer == nil else { return }

        lastValue = isConnected
        observer = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: session,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            let isConnected = self.isConnected
            guard isConnected != self.lastValue else { return }
            self.lastValue = isConnected
            self.onChange?(isConnected)
        }
    }

    func stop() {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
        observer = nil
    }
}
