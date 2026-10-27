import SwiftUI
import UIKit

/// Tab "Hoy": manual drive recording lives here (S4); the daily Driver Score and
/// the streak are filled in by T4.
struct TodayView: View {

    @StateObject private var recorder = DriveRecorder()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    DriveCard(recorder: recorder)

                    PlaceholderCard(
                        systemImage: "speedometer",
                        title: "Driver Score",
                        message: "Tu nota de hoy aparecerá aquí en cuanto registres tu primer trayecto."
                    )

                    PlaceholderCard(
                        systemImage: "flame.fill",
                        title: "Racha",
                        message: "Conduce cada día para mantener la racha. Tienes un día de margen antes de perderla."
                    )
                }
                .padding()
            }
            .navigationTitle("Hoy")
            // S5: coming back to the app during a drive means the phone was
            // unlocked and used, which is the closest available phone-use signal.
            .onReceive(
                NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            ) { _ in
                recorder.registerPhoneUseEvent()
            }
        }
    }
}

/// Manual start/stop button plus the live state of the drive (S4).
private struct DriveCard: View {

    @ObservedObject var recorder: DriveRecorder

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: "car.fill")
                .font(.headline)

            if showsStats {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    HStack(alignment: .top, spacing: 16) {
                        metric("Tiempo", value: elapsedText(at: context.date))
                        metric("Distancia", value: distanceText)
                        metric("Nota", value: scoreText)
                    }
                }
            }

            if recorder.isRecording && recorder.connectedMode {
                Label("Conducción conectada", systemImage: "iphone.radiowaves.left.and.right")
                    .font(.subheadline)
                    .foregroundStyle(.tint)
            }

            Button(action: toggleRecording) {
                Text(buttonTitle)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(recorder.isSaving)

            if let errorMessage = recorder.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.quaternary)
        )
    }

    // MARK: - Copy

    private var title: String {
        if recorder.isRecording {
            return "Trayecto en curso"
        }
        return recorder.lastCompletedDrive == nil ? "Registrar trayecto" : "Último trayecto"
    }

    private var buttonTitle: String {
        if recorder.isSaving {
            return "Guardando…"
        }
        return recorder.isRecording ? "Terminar trayecto" : "Empezar trayecto"
    }

    private var showsStats: Bool {
        recorder.isRecording || recorder.lastCompletedDrive != nil
    }

    private var distanceText: String {
        String(format: "%.1f km", recorder.distanceKm)
    }

    private var scoreText: String {
        recorder.liveScore.map(String.init) ?? "—"
    }

    private func elapsedText(at date: Date) -> String {
        let seconds = recorder.isRecording
            ? recorder.elapsed(at: date)
            : TimeInterval(recorder.lastCompletedDrive?.durationSeconds ?? 0)
        return Self.formattedDuration(seconds)
    }

    // MARK: - Actions

    private func toggleRecording() {
        if recorder.isRecording {
            Task { await recorder.stop() }
        } else {
            recorder.start()
        }
    }

    // MARK: - Layout

    private func metric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.title3.monospacedDigit())
                .fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static func formattedDuration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let remaining = total % 60

        let twoDigits: (Int) -> String = { $0 < 10 ? "0\($0)" : "\($0)" }
        if hours > 0 {
            return "\(hours):\(twoDigits(minutes)):\(twoDigits(remaining))"
        }
        return "\(twoDigits(minutes)):\(twoDigits(remaining))"
    }
}

#Preview {
    TodayView()
}
