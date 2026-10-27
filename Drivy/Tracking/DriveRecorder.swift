import Combine
import Foundation

/// Records one drive end to end.
///
/// It owns the live state the UI shows, feeds the injected samples to the pure
/// scoring engine, and hands the finished drive to `DriveUploading`. Every
/// dependency is a protocol so the whole flow is unit-tested with fakes: no
/// device, no network.
///
/// S4: the manual start/stop button is the guarantee; automatic detection is best
/// effort and silent, so nothing here ever blocks a manual drive.
@MainActor
final class DriveRecorder: ObservableObject {

    /// Copy shown in the UI. Kept here so tests assert the exact strings.
    static let locationDeniedMessage = "Activa la ubicación en Ajustes para registrar trayectos."
    static let uploadFailureMessage = "No hemos podido subir el trayecto."

    @Published private(set) var isRecording = false

    @Published private(set) var isSaving = false

    @Published private(set) var startedAt: Date?

    @Published private(set) var distanceKm: Double = 0

    /// Live score so far; `nil` until the first GPS fix arrives.
    @Published private(set) var liveScore: Int?

    /// Connected driving (S13), read at start and kept up to date by route changes.
    @Published private(set) var connectedMode = false

    @Published private(set) var errorMessage: String?

    /// Summary of the drive that just ended, so the UI can show how it went.
    @Published private(set) var lastCompletedDrive: DriveRecord?

    private let locationSampler: LocationSampling
    private let motionSampler: MotionSampling
    private let connectedModeDetector: ConnectedModeDetecting
    private let uploader: DriveUploading
    private let engine: ScoringEngine
    private let now: () -> Date

    private var samples = DriveSamples()
    // The two streams use different monotonic clocks (wall clock reference vs.
    // seconds since boot), so each one is rebased to its own first sample.
    private var locationOrigin: TimeInterval?
    private var motionOrigin: TimeInterval?
    private var phoneUseEvents = 0

    init(
        locationSampler: LocationSampling = CoreLocationSampler(),
        motionSampler: MotionSampling = CoreMotionSampler(),
        connectedModeDetector: ConnectedModeDetecting = AudioRouteConnectedModeDetector(),
        uploader: DriveUploading = SupabaseDriveRepository(),
        engine: ScoringEngine = ScoringEngine(),
        now: @escaping () -> Date = Date.init
    ) {
        self.locationSampler = locationSampler
        self.motionSampler = motionSampler
        self.connectedModeDetector = connectedModeDetector
        self.uploader = uploader
        self.engine = engine
        self.now = now
    }

    /// Seconds since the drive started, measured with the injected clock so tests
    /// are deterministic. Zero when no drive is in progress.
    func elapsed(at date: Date) -> TimeInterval {
        guard isRecording, let startedAt else { return 0 }
        return max(0, date.timeIntervalSince(startedAt))
    }

    // MARK: - Session

    func start() {
        guard !isRecording else { return }
        guard !locationSampler.isDenied else {
            // Without location there is no distance and no score, so the drive
            // is not started at all (and nothing is uploaded).
            errorMessage = Self.locationDeniedMessage
            return
        }

        samples = DriveSamples()
        locationOrigin = nil
        motionOrigin = nil
        phoneUseEvents = 0
        distanceKm = 0
        liveScore = nil
        lastCompletedDrive = nil
        errorMessage = nil
        startedAt = now()
        isRecording = true

        connectedMode = connectedModeDetector.isConnected
        samples.connectedMode = connectedMode

        locationSampler.onSample = { [weak self] sample in self?.append(location: sample) }
        motionSampler.onSample = { [weak self] sample in self?.append(motion: sample) }
        connectedModeDetector.onChange = { [weak self] isConnected in
            self?.updateConnectedMode(isConnected)
        }

        locationSampler.start()
        motionSampler.start()
        connectedModeDetector.start()
    }

    func stop() async {
        guard isRecording else { return }

        isRecording = false
        locationSampler.onSample = nil
        motionSampler.onSample = nil
        connectedModeDetector.onChange = nil
        locationSampler.stop()
        motionSampler.stop()
        connectedModeDetector.stop()

        samples.phoneUseEvents = phoneUseEvents
        samples.connectedMode = connectedMode

        guard let startedAt, let driveScore = engine.score(samples) else {
            // No usable fix: nothing to score and nothing to upload.
            finishSession(keepingSummary: false)
            return
        }

        let record = DriveRecord(score: driveScore, startedAt: startedAt)
        lastCompletedDrive = record
        distanceKm = driveScore.distanceKm
        liveScore = driveScore.score

        // The session ends before the network call, so a slow or failed upload
        // can never leave the UI in a half-recorded state.
        finishSession(keepingSummary: true)

        isSaving = true
        do {
            try await uploader.upload(record)
        } catch {
            // The summary stays in `lastCompletedDrive`; a retry queue is out of
            // scope for the MVP (S10 only requires the summarized upload).
            errorMessage = Self.uploadFailureMessage
        }
        isSaving = false
    }

    /// Best-effort "uso del móvil al volante" signal (S5).
    ///
    /// iOS does not tell a running app that the phone was unlocked, so the
    /// closest available proxy is the app coming back to the foreground during a
    /// drive: the phone was taken out, unlocked and used. See `TodayView`.
    func registerPhoneUseEvent() {
        guard isRecording else { return }

        phoneUseEvents += 1
        samples.phoneUseEvents = phoneUseEvents
        refreshLiveScore()
    }

    // MARK: - Samples

    private func append(location: LocationSample) {
        guard isRecording else { return }

        let origin = locationOrigin ?? location.timestamp
        locationOrigin = origin

        samples.locations.append(
            LocationSample(
                timestamp: location.timestamp - origin,
                speedMetersPerSecond: location.speedMetersPerSecond,
                speedLimitKmh: location.speedLimitKmh
            )
        )
        refreshLiveScore()
    }

    private func append(motion: MotionSample) {
        guard isRecording else { return }

        let origin = motionOrigin ?? motion.timestamp
        motionOrigin = origin

        samples.motions.append(
            MotionSample(
                timestamp: motion.timestamp - origin,
                longitudinalAcceleration: motion.longitudinalAcceleration
            )
        )
    }

    private func updateConnectedMode(_ isConnected: Bool) {
        guard isRecording else { return }

        connectedMode = isConnected
        samples.connectedMode = isConnected
        refreshLiveScore()
    }

    private func refreshLiveScore() {
        guard let live = engine.score(samples) else { return }

        distanceKm = live.distanceKm
        liveScore = live.score
    }

    private func finishSession(keepingSummary: Bool) {
        startedAt = nil
        connectedMode = false
        samples = DriveSamples()
        locationOrigin = nil
        motionOrigin = nil
        phoneUseEvents = 0

        if !keepingSummary {
            distanceKm = 0
            liveScore = nil
        }
    }
}
