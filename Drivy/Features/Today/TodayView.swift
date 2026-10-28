import SwiftUI
import UIKit

/// S5: the notification whose delivery counts as using the phone during a drive.
///
/// `willEnterForeground` and not `didBecomeActive`: both fire when the user comes
/// back to the app, but only the first one starts in the background. A system alert
/// — the app's own location permission prompt, Control Center, a notification pull —
/// makes the app inactive and active again while it stays on screen, so
/// `didBecomeActive` charged the first drive's own permission dialog as phone use.
/// Locking the screen or switching apps does send the app to the background, so every
/// real use of the phone still counts.
///
/// A value instead of an inline constant so the choice is one line to pin in a test.
enum PhoneUseSignal {

    /// The signal `TodayView` turns into `DriveRecorder.registerPhoneUseEvent()`.
    static let notification: Notification.Name = UIApplication.willEnterForegroundNotification
}

/// Tab "Hoy" (S1, S4, S6, S5): the day as a stretch of road (mockup C).
///
/// The header carries the date, the Driver Score of the day on a `KmPost`, and
/// one line with the streak, the freezes and the XP. The road itself — built by
/// `TodayRoad` from the same snapshot the screen already read — puts the pending
/// quests and the lesson ahead as signs, «Ahora» with the start/stop action and
/// the live drive at the driver's position, and today's drives plus the earned
/// quests behind, newest first.
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
    @State private var activeSheet: TodaySheet?

    /// Done quests as of the last finished load; `nil` until the first one (S9).
    @State private var knownDoneQuestIDs: Set<String>?

    /// Bumped when a reload completes a new quest; drives the success haptic.
    @State private var questCompletedPulse = 0

    /// Sheet the tab still owes once the one on screen closes (U3): the debrief of a
    /// drive that ended while the lesson was being answered.
    @State private var deferredSheet: TodaySheet?

    /// "Presented once ever" flag of the paywall (S9).
    private let paywallGate = FirstDrivePaywallGate()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    TodayHeader(dateText: road.dateText, snapshot: model.snapshot)

                    if model.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    }

                    repairSection

                    TodayRoadView(
                        road: road,
                        now: TodayNowValues(recorder: recorder),
                        historyDays: model.snapshot.days,
                        toggleRecording: toggleRecording,
                        onLesson: { activeSheet = .lesson }
                    )

                    if let errorMessage = model.errorMessage {
                        Text(errorMessage)
                            .font(.drivyFootnote)
                            .foregroundStyle(Color.drivyAlertText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    shareButton
                }
                .padding()
            }
            .background(Color.drivyPaper)
            .navigationTitle("Hoy")
            .refreshable { await reload() }
            // D4: drives whose upload failed earlier are retried before the day is read.
            .task(id: auth.signedInUser?.id) {
                await recorder.retryPendingUploads()
                await reload()
            }
            // A finished drive is written to `drives` and `daily_scores` by the
            // upload, so the day is read again as soon as the recorder has it.
            // S9: a success haptic when a reload shows a newly completed quest.
            .onChange(of: model.isLoading) { _, isLoading in
                guard !isLoading else { return }
                let ids = Set(road.doneQuestStops.map(\.id))
                if TodayRoad.completesNewQuest(known: knownDoneQuestIDs, current: ids) {
                    questCompletedPulse += 1
                }
                knownDoneQuestIDs = ids
            }
            .sensoryFeedback(.success, trigger: questCompletedPulse)
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
            // S5: coming back to the app **from the background** during a drive means
            // the phone was unlocked and used, which is the closest available
            // phone-use signal. Becoming active is deliberately not the trigger: a
            // system alert only makes the app inactive, so it would charge the drive
            // for the app's own dialog (`PhoneUseSignal`).
            .onReceive(NotificationCenter.default.publisher(for: PhoneUseSignal.notification)) { _ in
                recorder.registerPhoneUseEvent()
            }
        }
    }

    // MARK: - The road and its values

    /// The ordered road of the day (S5), rebuilt from the snapshot the screen
    /// already holds plus the recorder state.
    private var road: TodayRoad {
        TodayRoad.stops(
            from: model.snapshot,
            isRecording: recorder.isRecording,
            isSaving: recorder.isSaving,
            now: Date()
        )
    }

    private func toggleRecording() {
        if recorder.isRecording {
            Task { await recorder.stop() }
        } else {
            recorder.start()
        }
    }

    /// S8: the repair is a Premium advantage, so the free plan sees the upsell
    /// here instead of the action. It is conditional, so it lives between the
    /// header and the road only when a day is actually repairable.
    @ViewBuilder
    private var repairSection: some View {
        if model.snapshot.streak.repairableDay != nil {
            VStack(alignment: .leading, spacing: 8) {
                Text(PaywallCopy.streakRepairWindowMessage)
                    .font(.drivyFootnote)
                    .foregroundStyle(Color.drivyInkMuted)
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
                            .font(.drivyBodyStrong)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                case .locked:
                    Text(StreakRepairGate.upsellMessage)
                        .font(.drivyFootnote)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        activeSheet = .paywall
                    } label: {
                        Text(PaywallCopy.title)
                            .font(.drivyBodyStrong)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    // Filled with the sign blue: the light dark-mode tint is for text, not fills.
                    .tint(Color.drivySignBlue)

                case .coolingDown(_):
                    Text(PaywallCopy.streakRepairCoolingDownMessage)
                        .font(.drivyFootnote)
                        .foregroundStyle(Color.drivyInkMuted)
                        .fixedSize(horizontal: false, vertical: true)

                case .nothingToRepair, .unavailable:
                    EmptyView()
                }
            }
        }
    }

    private var shareButton: some View {
        Button {
            activeSheet = .shareCard
        } label: {
            Label("Compartir mi tarjeta", systemImage: "square.and.arrow.up")
                .font(.drivyBodyStrong)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
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
    /// fixed the order debrief → paywall, two sheets cannot be on screen at the same
    /// time, and the order itself lives in `PostDriveSheetScheduler` so it is tested.
    ///
    /// U3: an open lesson is not replaced. Its quiz keeps the answers in memory until
    /// the user finishes it, so the debrief waits for the lesson to close.
    private func handleCompletedDrive(_ drive: DriveRecord) {
        RouteHandoff.store(coordinates: recorder.routeCoordinates, startedAt: drive.startedAt)

        // L10: the free history window starts at the first drive date when the
        // profile is older. Done once per account.
        freemiumSession.recordCompletedDrive(startedAt: drive.startedAt)

        let step = PostDriveSheetScheduler.driveDidComplete(drive, shownSheet: activeSheet)
        deferredSheet = step.deferredSheet
        apply(step)

        Task { await reload() }
    }

    /// Any sheet of the tab closed.
    ///
    /// It runs after the dismissal, so the S9 paywall that follows the debrief of a
    /// drive never races the animation, and the day is read again (the lesson, the
    /// repair and the quests all change what Hoy shows).
    ///
    /// U3: a debrief the tab owed while the lesson was open is what shows up here, and
    /// the paywall still waits behind it (S2).
    private func sheetDidClose() {
        let step = PostDriveSheetScheduler.afterSheetClosed(
            deferred: deferredSheet,
            paywall: paywallState
        )
        deferredSheet = nil
        apply(step)

        Task { await reload() }
    }

    /// S9: the paywall appears after the first completed drive, once ever, and only
    /// on the free plan. It is presentation state only: it never gates recording.
    ///
    /// The guards that make it wait for the debrief live in
    /// `PostDriveSheetScheduler`: this function only feeds it the gate's own state
    /// and applies the step it returns.
    private func presentPaywallIfNeeded() {
        // One sheet at a time: while the debrief or the lesson owns the screen the
        // paywall waits, and it is offered again as soon as it closes.
        apply(PostDriveSheetScheduler.paywallIfDue(shownSheet: activeSheet, paywall: paywallState))
    }

    /// What the tab knows about the S9 paywall right now.
    private var paywallState: PostDriveSheetScheduler.PaywallState {
        PostDriveSheetScheduler.PaywallState(
            // Only a drive finished in this session triggers the paywall: a plan that
            // arrives later (StoreKit is slow, or the user just purchased) must not
            // turn a launch into an ad for drives recorded days ago.
            hasCompletedDriveThisSession: recorder.lastCompletedDrive != nil,
            wasPresented: paywallGate.wasPresented,
            isDue: paywallGate.shouldPresent(
                completedDriveCount: max(model.snapshot.drivesCount, 1),
                plan: freemium.plan
            )
        )
    }

    /// Applies a step of the schedule: records the gate when only the paywall does it
    /// and moves the tab to the sheet the step names, if any.
    private func apply(_ step: PostDriveSheetScheduler.Step) {
        guard let nextSheet = step.nextSheet else { return }

        if step.consumesPaywallGate {
            paywallGate.markPresented()
        }
        activeSheet = nextSheet
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

// MARK: - Header of the road

/// The header of Hoy (S5): the date, the Driver Score of the day on a `KmPost`,
/// and one line with the streak, the freezes and the XP. The score post is empty
/// (pending) until the day has a drive, exactly like a hito without a number.
struct TodayHeader: View {

    /// Long Spanish date of the day, from `TodayRoad.dateText`.
    let dateText: String

    /// The same snapshot `TodayView` renders the road from: the header and the
    /// road can never disagree about a number.
    let snapshot: TodaySnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(dateText)
                        .font(.drivyFootnote)
                        .foregroundStyle(Color.drivyInkMuted)

                    Text("Tu día en la carretera")
                        .font(.drivyTitle)
                        .foregroundStyle(Color.drivyInk)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 4) {
                    scorePost

                    Text("Driver Score de hoy")
                        .font(.drivyKicker)
                        .foregroundStyle(Color.drivyInkMuted)
                }
            }

            if snapshot.score == nil {
                Text("Registra tu primer trayecto del día para tener nota.")
                    .font(.drivyFootnote)
                    .foregroundStyle(Color.drivyInkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            streakLine

            Text(snapshot.streak.detail(todayHasDirtyDriving: todayHasDirtyDriving))
                .font(.drivyFootnote)
                .foregroundStyle(Color.drivyInkMuted)
                .fixedSize(horizontal: false, vertical: true)

            // The full sentence of the freezes only when there are none: that is
            // when it warns, and the compact count would hide the warning.
            if snapshot.streak.freezesLeftThisWeek == 0 {
                Text(snapshot.streak.freezeText)
                    .font(.drivyFootnote)
                    .foregroundStyle(Color.drivyCautionText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if snapshot.xp != nil {
                Text("El XP premia cómo conduces y lo que aprendes, nunca los kilómetros.")
                    .font(.drivyFootnote)
                    .foregroundStyle(Color.drivyInkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Today's score on the hito of the day, or an empty pending post when the
    /// day has no drive yet.
    @ViewBuilder
    private var scorePost: some View {
        if let score = snapshot.score {
            KmPost(value: DriveFormat.score(score), size: KmPostSize.score)
        } else {
            KmPost(isPending: true, size: KmPostSize.score) {
                EmptyView()
            }
        }
    }

    /// One line: the streak run, the freezes left this week, the lifetime XP and
    /// this week's XP (the figure the weekly leagues rank by).
    private var streakLine: Text {
        var line = Text(snapshot.streak.headline)
            .font(.drivyBodyStrong)
            .foregroundStyle(Color.drivyInk)

        if snapshot.streak.freezesLeftThisWeek > 0 {
            line = line + Text(" · \(TodayRoad.freezesCountText(snapshot.streak.freezesLeftThisWeek))")
                .font(.drivyFootnote)
                .foregroundStyle(Color.drivyInkMuted)
        }

        if let xp = snapshot.xp {
            line = line + Text(" · \(xp.totalXP) XP · +\(xp.weekXP) esta semana")
                .font(.drivyFootnote)
                .foregroundStyle(Color.drivyInkMuted)
        }

        return line
    }

    /// S1: the same dirty-day test `TodayRoad.stops` uses for the lesson copy, so
    /// the streak line and the lesson stop never promise different things (B5).
    private var todayHasDirtyDriving: Bool {
        Streak.hasDirtyDrivingToday(
            dayScore: snapshot.score,
            drivesCount: snapshot.drivesCount
        )
    }
}

// MARK: - The road

/// The plain values the «Ahora» stop renders, built by `TodayView` from the
/// recorder so the stop (and the gallery) never needs the recorder itself.
@MainActor
struct TodayNowValues {

    /// «Trayecto en curso» / «Registrar trayecto» / «Último trayecto».
    var stateTitle: String

    /// «Empezar trayecto» / «Terminar trayecto» / «Guardando…».
    var buttonTitle: String

    var isRecording: Bool

    /// `true` while recording or right after a finished drive, as the old live
    /// card did.
    var showsStats: Bool

    var showsConnectedModeLabel: Bool

    var distanceText: String

    var scoreText: String

    /// The live elapsed clock, redrawn by the `TimelineView` of the stop.
    var elapsedText: (Date) -> String

    var errorMessage: String?

    /// The recorder-backed values, with the copy the manual button has always
    /// used (S6: byte-identical titles).
    init(recorder: DriveRecorder) {
        let recording = recorder.isRecording

        if recording {
            stateTitle = "Trayecto en curso"
        } else if recorder.lastCompletedDrive == nil {
            stateTitle = "Registrar trayecto"
        } else {
            stateTitle = "Último trayecto"
        }

        if recorder.isSaving {
            buttonTitle = "Guardando…"
        } else if recording {
            buttonTitle = "Terminar trayecto"
        } else {
            buttonTitle = "Empezar trayecto"
        }

        isRecording = recording
        showsStats = recording || recorder.lastCompletedDrive != nil
        showsConnectedModeLabel = recording && recorder.connectedMode
        distanceText = String(format: "%.1f km", recorder.distanceKm)
        scoreText = recorder.liveScore.map(String.init) ?? "—"
        errorMessage = recorder.errorMessage
        elapsedText = { date in
            let seconds = recording
                ? recorder.elapsed(at: date)
                : TimeInterval(recorder.lastCompletedDrive?.durationSeconds ?? 0)
            return Self.formattedDuration(seconds)
        }
    }

    /// The fixture path of the gallery: the same fields, given directly.
    init(
        stateTitle: String,
        buttonTitle: String,
        isRecording: Bool,
        showsStats: Bool,
        showsConnectedModeLabel: Bool,
        distanceText: String,
        scoreText: String,
        elapsedText: @escaping (Date) -> String,
        errorMessage: String?
    ) {
        self.stateTitle = stateTitle
        self.buttonTitle = buttonTitle
        self.isRecording = isRecording
        self.showsStats = showsStats
        self.showsConnectedModeLabel = showsConnectedModeLabel
        self.distanceText = distanceText
        self.scoreText = scoreText
        self.elapsedText = elapsedText
        self.errorMessage = errorMessage
    }

    static func formattedDuration(_ seconds: TimeInterval) -> String {
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

/// The road of the day itself (S5): `RoadTimeline` with the stops of `TodayRoad`
/// in order — pending quests and lesson ahead, «Ahora» with the live drive, the
/// drives of today and the earned quests behind — plus the navigation to the
/// Histórico the old section header carried.
///
/// S9: the dashes move and a haptic marks the start and the end of a recording.
struct TodayRoadView: View {

    let road: TodayRoad

    let now: TodayNowValues

    /// Days for the Histórico link, the same the snapshot carries (S9).
    let historyDays: [HistoryDay]

    var toggleRecording: () -> Void = {}

    var onLesson: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            RoadTimeline(isMoving: road.now.isRecording) {
                ForEach(road.ahead) { stop in
                    if stop.role == .lesson {
                        lessonStop(stop, showsKicker: stop.id == road.ahead.first?.id)
                    } else {
                        aheadStop(stop, showsKicker: stop.id == road.ahead.first?.id)
                    }
                }

                if !road.ahead.isEmpty {
                    // The old promise of the quest section, kept after the stops
                    // it belongs to (S6: byte-identical).
                    plainStop {
                        Text("Se renuevan cada día. Ninguna misión pide conducir más.")
                            .font(.drivyFootnote)
                            .foregroundStyle(Color.drivyInkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                nowStop

                ForEach(road.driveStops) { stop in
                    driveStop(stop)
                }

                ForEach(road.doneQuestStops) { stop in
                    doneQuestStop(stop)
                }
            }
            .sensoryFeedback(.start, trigger: road.now.isRecording) { _, isRecording in isRecording }
            .sensoryFeedback(.stop, trigger: road.now.isRecording) { _, isRecording in !isRecording }

            HStack(alignment: .firstTextBaseline) {
                Text("Trayectos de hoy")
                    .font(.drivyBodyStrong)
                    .foregroundStyle(Color.drivyInk)

                Spacer(minLength: 0)

                // S9: the full history lives here, gated by the plan in force.
                NavigationLink {
                    HistoryView(days: historyDays)
                } label: {
                    Text("Histórico")
                        .font(.drivyBody)
                        // HIG touch target: the frame keeps it trailing, the shape
                        // makes the whole 44 pt tappable.
                        .frame(minHeight: 44, alignment: .trailing)
                        .contentShape(Rectangle())
                }
            }

            if road.driveStops.isEmpty {
                Text("Aún no hay trayectos hoy.")
                    .font(.drivyFootnote)
                    .foregroundStyle(Color.drivyInkMuted)
            }
        }
    }

    // MARK: - Stops

    /// A pending quest ahead: its sign, its title, what it asks for.
    /// Only the first stop ahead carries the «Por delante» kicker.
    private func aheadStop(_ stop: TodayRoad.AheadStop, showsKicker: Bool) -> some View {
        RoadStop(sign: stop.sign) {
            VStack(alignment: .leading, spacing: 2) {
                if showsKicker {
                    Text("Por delante")
                        .font(.drivyKicker)
                        .foregroundStyle(Color.drivyInkMuted)
                }

                Text(stop.title)
                    .font(.drivyHeadline)
                    .foregroundStyle(Color.drivyInk)

                Text(stop.detail)
                    .font(.drivyFootnote)
                    .foregroundStyle(Color.drivyInkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The lesson ahead, with the action that opens it. The stop owns a control,
    /// so its text is not combined into the button's element.
    private func lessonStop(_ stop: TodayRoad.AheadStop, showsKicker: Bool) -> some View {
        RoadStop(sign: stop.sign, combinesText: false) {
            VStack(alignment: .leading, spacing: 8) {
                if showsKicker {
                    Text("Por delante")
                        .font(.drivyKicker)
                        .foregroundStyle(Color.drivyInkMuted)
                }

                Text(stop.title)
                    .font(.drivyHeadline)
                    .foregroundStyle(Color.drivyInk)

                Text(stop.detail)
                    .font(.drivyFootnote)
                    .foregroundStyle(Color.drivyInkMuted)
                    .fixedSize(horizontal: false, vertical: true)

                if let actionTitle = stop.actionTitle {
                    Button(action: onLesson) {
                        Text(actionTitle)
                            .font(.drivyBodyStrong)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    /// «Ahora»: the position pin, the live drive while it records, and the
    /// manual start/stop action as the directional sign of the road (S3, S9).
    private var nowStop: some View {
        RoadStop(combinesText: false, pin: { PositionPin() }) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Ahora")
                    .font(.drivyKicker)
                    .foregroundStyle(Color.drivyInkMuted)

                Text(now.stateTitle)
                    .font(.drivyHeadline)
                    .foregroundStyle(Color.drivyInk)

                if now.showsStats {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        HStack(alignment: .top, spacing: 16) {
                            nowMetric("Tiempo", value: now.elapsedText(context.date))
                            nowMetric("Distancia", value: now.distanceText)
                            nowMetric("Nota", value: now.scoreText)
                        }
                        // One element instead of three stops while the drive runs;
                        // the labels are already in reading order.
                        .accessibilityElement(children: .combine)
                    }
                }

                if now.showsConnectedModeLabel {
                    Text("Conducción conectada")
                        .font(.drivyFootnote)
                        .foregroundStyle(Color.drivyTint)
                }

                Button(action: toggleRecording) {
                    Text(now.buttonTitle)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.directionSign)
                .disabled(road.now.action == .saving)

                if let errorMessage = now.errorMessage {
                    Text(errorMessage)
                        .font(.drivyFootnote)
                        .foregroundStyle(Color.drivyAlertText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// A finished drive behind the position, newest first: time · score ·
    /// duration, its events as small signs, and the detail one tap away.
    private func driveStop(_ stop: TodayRoad.DriveStop) -> some View {
        RoadStop(combinesText: false, pin: { DriveDotPin() }) {
            NavigationLink {
                DriveDetailView(drive: stop.drive)
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(stop.timeText) · \(stop.scoreText) · \(stop.durationText)")
                        .font(.drivyHeadline)
                        .foregroundStyle(Color.drivyInk)

                    if !stop.events.isEmpty {
                        HStack(spacing: 8) {
                            ForEach(stop.events) { event in
                                RoadSign(
                                    kind: event.sign,
                                    size: RoadMetrics.minSignSize,
                                    accessibilityLabel: event.accessibilityLabel
                                )
                            }
                        }
                    }
                }
                // One element per row: the numbers and the event counts are read
                // in the order they are shown.
                .accessibilityElement(children: .combine)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    /// A quest earned today, behind the drives, with its sign muted and the
    /// green tick of the completed thing it is.
    private func doneQuestStop(_ stop: TodayRoad.DoneQuestStop) -> some View {
        RoadStop(pin: { DoneQuestPin(sign: stop.sign) }) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Completada")
                    .font(.drivyKicker)
                    .foregroundStyle(Color.drivyGo)

                Text(stop.title)
                    .font(.drivyHeadline)
                    .foregroundStyle(Color.drivyInk)

                Text(stop.detail)
                    .font(.drivyFootnote)
                    .foregroundStyle(Color.drivyInkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// A line of the road that is not a stop: its pin slot stays empty, so the
    /// asphalt runs behind it uninterrupted.
    private func plainStop<Content: View>(
        @ViewBuilder _ content: () -> Content
    ) -> some View {
        RoadStop(pin: { Color.clear.frame(width: 1, height: 1) }, content: content)
    }

    private func nowMetric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.drivyKicker)
                .foregroundStyle(Color.drivyInkMuted)

            Text(value)
                .font(.drivyHeadline)
                .monospacedDigit()
                .foregroundStyle(Color.drivyInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Pins of the road

/// The position of the driver on the road (S5): an amber arrow on a dark disc,
/// the way the mockup marks «you are here». The disc is `signGlyph` — fixed dark
/// in both appearances — because the arrow sits on it, exactly like a sign face:
/// `drivyInk` would flip to near-white in dark mode and swallow the amber.
private struct PositionPin: View {

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.drivySignGlyph)

            Circle()
                .stroke(Color.drivyLaneMark, lineWidth: 3)

            Image(systemName: "location.north.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.drivyCaution)
        }
        .frame(width: 44, height: 44)
        .accessibilityHidden(true)
    }
}

/// The small neutral mark of a drive that already happened.
private struct DriveDotPin: View {

    var body: some View {
        Circle()
            .fill(Color.drivySignFace)
            .overlay(
                Circle()
                    .stroke(Color.drivyInkMuted, lineWidth: 2.5)
            )
            .frame(width: 18, height: 18)
            .accessibilityHidden(true)
    }
}

/// The sign of a completed quest, muted, with the green tick of the done thing
/// (S5). Decorative: the stop reads «Completada» in words.
private struct DoneQuestPin: View {

    let sign: RoadSign.Kind

    var body: some View {
        RoadSign(kind: sign, size: 32)
            .opacity(0.65)
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.drivyGoTick)
                    .frame(width: 16, height: 16)
                    .background(Circle().fill(Color.drivyGo))
                    .offset(x: 4, y: 2)
            }
            .accessibilityHidden(true)
    }
}

fileprivate extension Color {

    /// The tick of a completed quest sits on `go`, which flips to a light green
    /// in dark mode; the tick takes the ink of the opposite appearance so the
    /// pair stays readable in both (S7: the road never fixes a colour pair the
    /// tokens cannot serve).
    static let drivyGoTick = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? DrivyToken.ink.light
            : DrivyToken.ink.dark
    })
}

#Preview {
    TodayView()
        .environmentObject(AuthViewModel())
        .environmentObject(FreemiumService(anchorDate: Date()))
        .environmentObject(FreemiumSessionCoordinator())
}
