import SwiftUI
import UIKit

/// Tab "Hoy" (S1, S4, S6): manual drive recording, today's Driver Score, the streak
/// v2, the XP, the quests of the day, the theory lesson and the list of the day's
/// drives.
///
/// It is also where S9 shows up: the paywall after the first completed drive (once
/// ever, never blocking) and the entry point to the Histórico, which is gated by the
/// plan in force.
///
/// Nothing on this screen invites the user to drive: the streak, the quests and the
/// lesson are all reachable without a car (S1, S6, S7).
struct TodayView: View {

    @EnvironmentObject private var auth: AuthViewModel

    /// Plan and gating rules of the session (S9), owned by `RootView`.
    @EnvironmentObject private var freemium: FreemiumService

    /// Session owner of the freemium service: needed to move the free window to the
    /// first drive date (L10).
    @EnvironmentObject private var freemiumSession: FreemiumSessionCoordinator

    @StateObject private var recorder = DriveRecorder()
    @StateObject private var model = TodayViewModel()
    @State private var activeSheet: ActiveSheet?

    /// Size of the hero Driver Score, scaled with Dynamic Type instead of frozen
    /// at 44 pt: the score is the main number of the screen and has to grow with
    /// the reader's preferred text size.
    @ScaledMetric(relativeTo: .largeTitle) private var scoreSize: CGFloat = 44

    /// "Presented once ever" flag of the paywall (S9).
    private let paywallGate = FirstDrivePaywallGate()

    /// Sheets of the tab, in one enum so two `.sheet` modifiers cannot fight.
    private enum ActiveSheet: Identifiable {
        /// Share card (S9).
        case shareCard
        /// Paywall after the first drive and from the gating hook points (S9).
        case paywall
        /// Post-drive summary (S2): shown before the paywall, never instead of it.
        case debrief(DriveRecord)
        /// Theory lesson of the day (S2).
        case lesson

        var id: String {
            switch self {
            case .shareCard:
                return "shareCard"
            case .paywall:
                return "paywall"
            case .debrief(let record):
                return "debrief-\(record.startedAt.timeIntervalSince1970)"
            case .lesson:
                return "lesson"
            }
        }
    }

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
                    xpCard
                    questsSection
                    lessonCard
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
            .onChange(of: recorder.lastCompletedDrive) { _, drive in
                guard let drive else { return }
                handleCompletedDrive(drive)
            }
            // The plan can arrive after the drive (StoreKit is read at sign-in and
            // on every transaction update), and S9 asks for the paywall once the
            // plan is known to be Free. The freezes of the streak (S1/S8) also
            // depend on it.
            .onChange(of: freemium.plan) { _, _ in
                Task {
                    await reload()
                    presentPaywallIfNeeded()
                }
            }
            .sheet(item: $activeSheet, onDismiss: sheetDidClose) { sheet in
                switch sheet {
                case .shareCard:
                    ShareCardSheet(userID: signedInUserID)
                case .paywall:
                    PaywallPresenter(freemium: freemium)
                        .makePaywallView(onClose: { activeSheet = nil })
                case .debrief(let record):
                    DriveDebriefView(record: record, onClose: { activeSheet = nil })
                case .lesson:
                    LessonQuizView(onFinished: { _, _ in activeSheet = nil })
                }
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
                    .font(.system(size: scoreSize, weight: .bold, design: .rounded))
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

    /// Streak v2 (S1): the run, what today needs, the freezes of the week and,
    /// when a break is inside the S8 window, the premium repair or its upsell.
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

            Label(model.snapshot.streak.freezeText, systemImage: "snowflake")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            repairSection
        }
        .drivyCard()
    }

    /// S8: the repair is a Premium advantage, so the free plan sees the upsell
    /// here instead of the action.
    @ViewBuilder
    private var repairSection: some View {
        if model.snapshot.streak.repairableDay != nil {
            VStack(alignment: .leading, spacing: 8) {
                Text(PaywallCopy.streakRepairWindowMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                switch StreakRepairGate.decision(
                    streak: model.snapshot.streak,
                    access: freemium.access,
                    lastRepairAt: model.snapshot.lastStreakRepairAt,
                    now: Date()
                ) {
                case .allowed:
                    Button {
                        Task { await repairStreak() }
                    } label: {
                        Text(StreakRepairGate.buttonTitle)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                case .locked:
                    Text(StreakRepairGate.upsellMessage)
                        .font(.footnote)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        activeSheet = .paywall
                    } label: {
                        Text(PaywallCopy.title)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                case .coolingDown(_):
                    Text(PaywallCopy.streakRepairCoolingDownMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                case .nothingToRepair, .unavailable:
                    EmptyView()
                }
            }
        }
    }

    /// S4: lifetime XP and the XP of this week. It is a figure that only grows and
    /// never scales with km.
    @ViewBuilder
    private var xpCard: some View {
        if let xp = model.snapshot.xp {
            VStack(alignment: .leading, spacing: 8) {
                Label("XP", systemImage: "sparkles")
                    .font(.headline)

                HStack(spacing: 12) {
                    DriveMetric(title: "Total", value: "\(xp.totalXP) XP")
                    DriveMetric(title: "Esta semana", value: "\(xp.weekXP) XP")
                }

                Text("El XP premia cómo conduces y lo que aprendes, nunca los kilómetros.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .drivyCard()
        }
    }

    /// S6: the three quests of the day.
    @ViewBuilder
    private var questsSection: some View {
        if !model.snapshot.quests.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Label("Misiones de hoy", systemImage: "target")
                    .font(.headline)

                ForEach(model.snapshot.quests) { progress in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: progress.isCompleted ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(progress.isCompleted ? Color.accentColor : Color.secondary)
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(progress.quest.title)
                                .font(.subheadline.weight(.medium))

                            Text(progress.quest.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 0)
                    }
                    // One element per quest: the icon only repeats the state the
                    // title already has next to it.
                    .accessibilityElement(children: .combine)
                }

                Text("Se renuevan cada día. Ninguna misión pide conducir más.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .drivyCard()
        }
    }

    /// S2: the one-minute theory lesson, which is also a way to make the day count
    /// without a car (S1).
    private var lessonCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Lección de hoy", systemImage: "text.book.closed.fill")
                .font(.headline)

            Text(lessonMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                activeSheet = .lesson
            } label: {
                Text(lessonButtonTitle)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .drivyCard()
    }

    private var drivesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Trayectos de hoy")
                    .font(.headline)

                Spacer(minLength: 0)

                // S9: the full history lives here, gated by the plan in force.
                NavigationLink {
                    HistoryView(days: model.snapshot.days)
                } label: {
                    Text("Histórico")
                        .font(.subheadline)
                        // HIG touch target: the bare text label was only ~20 pt
                        // tall. The frame keeps it trailing, the shape makes the
                        // whole 44 pt tappable.
                        .frame(minHeight: 44, alignment: .trailing)
                        .contentShape(Rectangle())
                }
            }

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
            activeSheet = .shareCard
        } label: {
            Label("Compartir mi tarjeta", systemImage: "square.and.arrow.up")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }

    // MARK: - Copy of the lesson card

    private var lessonMessage: String {
        model.snapshot.hasLessonToday
            ? "Ya has hecho la lección de hoy: cuenta para tu racha."
            : "Un minuto de teoría. Hacerla ya hace que el día cuente para la racha, aunque no cojas el coche."
    }

    private var lessonButtonTitle: String {
        model.snapshot.hasLessonToday ? "Repasar la lección" : "Hacer la lección (1 minuto)"
    }

    // MARK: - S9 hooks

    /// Everything that has to happen once the recorder has a finished drive.
    ///
    /// The route is handed over first (L11): it only exists in the recorder of this
    /// session, and the detail screen of the drive that just finished reads it from
    /// `LocalRouteStore`. Nothing here can block the recording that already ended
    /// (S9/S12).
    ///
    /// The post-drive summary (S2) comes first and the paywall waits for it: L9
    /// fixed the order debrief → paywall, and two sheets cannot be on screen at the
    /// same time.
    private func handleCompletedDrive(_ drive: DriveRecord) {
        RouteHandoff.store(coordinates: recorder.routeCoordinates, startedAt: drive.startedAt)

        // L10: the free history window starts at the first drive date when the
        // profile is older. Done once per account.
        freemiumSession.recordCompletedDrive(startedAt: drive.startedAt)

        activeSheet = .debrief(drive)

        Task { await reload() }
    }

    /// Any sheet of the tab closed.
    ///
    /// It runs after the dismissal, so the S9 paywall that follows the debrief of a
    /// drive never races the animation, and the day is read again (the lesson, the
    /// repair and the quests all change what Hoy shows).
    private func sheetDidClose() {
        presentPaywallIfNeeded()
        Task { await reload() }
    }

    /// S9: the paywall appears after the first completed drive, once ever, and only
    /// on the free plan. It is presentation state only: it never gates recording.
    private func presentPaywallIfNeeded() {
        // Only a drive finished in this session triggers the paywall: a plan that
        // arrives later (StoreKit is slow, or the user just purchased) must not turn
        // a launch into an ad for drives recorded days ago.
        guard recorder.lastCompletedDrive != nil else { return }

        // One sheet at a time: while the debrief or the lesson owns the screen the
        // paywall waits, and it is offered again as soon as it closes.
        guard activeSheet == nil else { return }

        let completedDriveCount = max(model.snapshot.drivesCount, 1)

        guard paywallGate.shouldPresent(
            completedDriveCount: completedDriveCount,
            plan: freemium.plan
        ) else { return }

        paywallGate.markPresented()
        activeSheet = .paywall
    }

    // MARK: - Data

    private var signedInUserID: String {
        auth.signedInUser?.id ?? ""
    }

    private func reload() async {
        guard let userID = auth.signedInUser?.id else { return }
        await model.load(userID: userID, plan: freemium.plan)
    }

    /// S8: records the repair of the broken day and reads the day again so the run
    /// comes back on screen.
    private func repairStreak() async {
        guard let brokenDay = model.snapshot.streak.repairableDay else { return }

        await model.repairStreak(brokenDay: brokenDay)
        // A failed repair keeps its message on screen: reloading would clear it.
        guard model.errorMessage == nil else { return }

        await reload()
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

            // The chevron only says "there is a detail screen": the row already
            // opens it, so announcing "chevron right" only adds noise.
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        // One element per row: the numbers are read in the order they are shown.
        .accessibilityElement(children: .combine)
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
                    // One element instead of three stops while the drive runs;
                    // the labels are already in reading order.
                    .accessibilityElement(children: .combine)
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
        .environmentObject(FreemiumService(anchorDate: Date()))
        .environmentObject(FreemiumSessionCoordinator())
}
