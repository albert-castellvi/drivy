import SwiftUI
import UIKit

/// Tab "Hoy" (S4, S6): manual drive recording, today's Driver Score, the streak
/// and the list of the day's drives.
struct TodayView: View {

    @EnvironmentObject private var auth: AuthViewModel

    @StateObject private var recorder = DriveRecorder()
    @StateObject private var model = TodayViewModel()
    @State private var isShowingShareCard = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // T3: the manual button stays the primary action (S4).
                    DriveCard(recorder: recorder)

                    if model.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    }

                    scoreCard
                    streakCard
                    drivesSection

                    if let errorMessage = model.errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    shareButton
                }
                .padding()
            }
            .navigationTitle("Hoy")
            .refreshable { await reload() }
            .task(id: auth.signedInUser?.id) { await reload() }
            // A finished drive is written to `drives` and `daily_scores` by the
            // upload, so the day is read again as soon as the recorder has it.
            .onChange(of: recorder.lastCompletedDrive) { _, _ in
                Task { await reload() }
            }
            .sheet(isPresented: $isShowingShareCard) {
                ShareCardSheet(userID: signedInUserID)
            }
            // S5: coming back to the app during a drive means the phone was
            // unlocked and used, which is the closest available phone-use signal.
            .onReceive(
                NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            ) { _ in
                recorder.registerPhoneUseEvent()
            }
        }
    }

    // MARK: - Sections

    private var scoreCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Driver Score de hoy", systemImage: "speedometer")
                .font(.headline)

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(DriveFormat.score(model.snapshot.score))
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .monospacedDigit()

                VStack(alignment: .leading, spacing: 2) {
                    Text(DriveFormat.distance(model.snapshot.distanceKm))
                    Text(DriveFormat.drivesCount(model.snapshot.drivesCount))
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            if model.snapshot.score == nil {
                Text("Registra tu primer trayecto del día para tener nota.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .drivyCard()
    }

    private var streakCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Racha", systemImage: "flame.fill")
                .font(.headline)

            Text(model.snapshot.streak.headline)
                .font(.title3.weight(.semibold))

            Text(model.snapshot.streak.detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .drivyCard()
    }

    private var drivesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Trayectos de hoy")
                .font(.headline)

            if model.snapshot.drives.isEmpty {
                Text("Aún no hay trayectos hoy.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.snapshot.drives) { drive in
                    NavigationLink {
                        DriveDetailView(drive: drive)
                    } label: {
                        DriveSummaryRow(drive: drive)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .drivyCard()
    }

    private var shareButton: some View {
        Button {
            isShowingShareCard = true
        } label: {
            Label("Compartir mi tarjeta", systemImage: "square.and.arrow.up")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }

    // MARK: - Data

    private var signedInUserID: String {
        auth.signedInUser?.id ?? ""
    }

    private func reload() async {
        guard let userID = auth.signedInUser?.id else { return }
        await model.load(userID: userID)
    }
}

/// One line of today's list: time, distance and score, with the detail one tap
/// away.
private struct DriveSummaryRow: View {

    let drive: DriveHistoryRow

    var body: some View {
        HStack(spacing: 12) {
            Text(DriveFormat.time(drive.startedAt))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(DriveFormat.distance(drive.distanceKm))
                    .font(.subheadline.weight(.medium))
                Text(DriveFormat.duration(TimeInterval(drive.durationSeconds)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Text(DriveFormat.score(drive.score))
                .font(.title3.monospacedDigit().weight(.semibold))

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
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
        .environmentObject(AuthViewModel())
}
