import SwiftUI

/// Tab "Camino" (S3, S4): the habit path of the user, unit by unit, plus the
/// one-minute theory lesson of the day.
///
/// It sits between Hoy and Ligas because it is the map of the loop: what to learn
/// next, and what each level pays. Nothing on this screen invites the user to
/// drive: every unit counts drives that already happened and the lesson needs no
/// car, which is the safety principle of the whole feature.
///
/// S5 (T4): the path is the same road Hoy draws, at habit scale. Each unit is a
/// stretch of it — a blue information sign with its number at the start, its three
/// levels as hitos along the asphalt — and the amber arrow says where the user
/// stands. The lesson and the summary keep their words and lose their cards: on a
/// road, a stretch of asphalt and proximity do the separating.
struct PathView: View {

    @EnvironmentObject private var auth: AuthViewModel

    @StateObject private var model = HabitPathViewModel()

    /// Sheet of the theory lesson (S2), opened from the entry of the tab.
    @State private var isPresentingLesson = false

    /// Whether the tab has already been on screen once.
    ///
    /// The first load belongs to the `.task(id:)` of the view; every later
    /// appearance is a re-entry into the tab and reloads the path (B4).
    @State private var hasAppearedOnce = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if model.isLoading && model.snapshot.units.isEmpty {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    }

                    PathBriefing(snapshot: model.snapshot) { isPresentingLesson = true }
                    roadSection

                    if let errorMessage = model.errorMessage {
                        Text(errorMessage)
                            .font(.drivyFootnote)
                            .foregroundStyle(Color.drivyAlertText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.drivyPaper)
            .navigationTitle("Camino")
            .refreshable { await reload() }
            .task(id: auth.signedInUser?.id) { await reload() }
            // S3/S4 (B4): the tab content stays alive inside `TabView`, so
            // `.task(id:)` does not fire again when the user comes back to Camino.
            // A drive finished in Hoy is what reaches the next level, and the level
            // is only recorded inside `load()`: without this reload the tab kept a
            // stale "7 de 15 trayectos", the reached level never paid its 50 XP (S4)
            // and the next unit stayed locked (S3) until a pull-to-refresh.
            .onAppear {
                guard hasAppearedOnce else {
                    // First appearance: `.task(id:)` above already loads.
                    hasAppearedOnce = true
                    return
                }
                Task { await reload() }
            }
            .sheet(
                isPresented: $isPresentingLesson,
                // The lesson makes the day count for the streak (S1), so the entry
                // states it as soon as the sheet closes.
                onDismiss: { Task { await reload() } }
            ) {
                LessonQuizView(onFinished: { _, _ in isPresentingLesson = false })
            }
        }
    }

    // MARK: - Sections

    /// S3/S5: the units as one stretch of road, locked ones included, so the whole
    /// way is visible from the start — the ahead part with its marks faded.
    private var roadSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Unidades")
                .font(.drivyHeadline)
                .foregroundStyle(Color.drivyInk)

            PathRoad(units: model.snapshot.units)

            Text(
                "Cada nivel superado suma \(HabitPathEngine.xpPerLevel) XP. "
                    + "Solo cuentan los trayectos de 2 km o más: ninguna unidad premia conducir más."
            )
            .font(.drivyFootnote)
            .foregroundStyle(Color.drivyInkMuted)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Data

    /// Reads the path again and, when that read recorded a level, once more.
    ///
    /// S3: the next unit opens at the `completedAt` the server stamped on the third
    /// level of the previous one, so the read that records the level cannot see the
    /// unit it unlocks (the engine says so: "while that write is in flight the next
    /// unit waits one refresh"). Both reads are idempotent, so the second one is
    /// what makes the reached level and the unlocked unit appear together, without a
    /// pull-to-refresh (B4). A stable path costs one read.
    private func reload() async {
        guard auth.signedInUser != nil else { return }

        await model.load()
        guard !model.snapshot.pendingLevels.isEmpty else { return }

        await model.load()
    }
}

// MARK: - The briefing

/// The two halves of Camino that are not the road: the theory lesson of the day and
/// the figures of the way.
///
/// It takes the snapshot the view model published and one action, so the gallery
/// (S8) can show this half of the screen with fixture data the same way it shows the
/// road. Its words are the words of the tab before the redesign, and they stay
/// byte-identical (S6).
struct PathBriefing: View {

    /// The path as the view model last read it.
    let snapshot: HabitPathSnapshot

    /// Opens the lesson sheet (S2).
    let onLesson: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            lessonSection
            summarySection
        }
    }

    /// S2/S3: the theory lesson, which is also the way to keep the streak without
    /// a car. Blue information sign, the day's words, one direction sign to act —
    /// no card, because the road below is the one focal point.
    private var lessonSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                RoadSign(kind: .info(systemName: "book.closed"), size: RoadMetrics.minSignSize)

                Text("Lección de hoy")
                    .font(.drivyHeadline)
                    .foregroundStyle(Color.drivyInk)

                Spacer(minLength: 0)
            }

            Text(lessonMessage)
                .font(.drivyBody)
                .foregroundStyle(Color.drivyInkMuted)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: onLesson) {
                Text(lessonButtonTitle)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.directionSign)
        }
    }

    /// S3/S4: how far the road is and what the levels have paid.
    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 20) {
                PathFigure(
                    title: "Niveles",
                    value: "\(snapshot.completedLevels) de \(snapshot.totalLevels)"
                )

                PathFigure(
                    title: "XP de niveles",
                    value: "\(snapshot.xpFromLevels) XP"
                )
            }

            if let current = snapshot.currentUnit {
                Text("Ahora: «\(current.unit.title)». \(current.unit.tip)")
                    .font(.drivyFootnote)
                    .foregroundStyle(Color.drivyInkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Camino does not know today's driving score, so the copy states only what
    /// is always true (S1): the lesson keeps the streak on a day without driving,
    /// and it never rescues a day of driving below the threshold.
    private var lessonMessage: String {
        snapshot.hasLessonToday
            ? "Ya has hecho la lección de hoy y has sumado XP."
            : "Un minuto de teoría. En un día sin coche, la lección hace que el día cuente para la racha."
    }

    private var lessonButtonTitle: String {
        snapshot.hasLessonToday ? "Repasar la lección" : "Hacer la lección (1 minuto)"
    }
}

// MARK: - The road

/// The Camino as one road (S5): the units in path order, each one a stretch with
/// its sign and its level posts, and the amber arrow at the unit being played.
///
/// It takes the `HabitUnitProgress` values the view model publishes and nothing
/// else, so it is the whole of the screen's drawing and can be rendered on its own
/// with fixtures (S8).
///
/// Every stretch carries its own `RoadTimeline`, laid out with no gap so the asphalt
/// reads as one continuous road down the screen. It has to be per stretch, not one
/// band for the whole path: the road ahead is faded, and the band of a timeline sits
/// behind all of its stops, so a single band could never fade only the part the user
/// has not reached yet (S5).
struct PathRoad: View {

    /// Every unit of the path, locked ones included, in path order.
    let units: [HabitUnitProgress]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(HabitRoad.stretches(in: units)) { stretch in
                RoadTimeline(isMoving: false) {
                    // The gap belongs inside the stretch: the band of a timeline is as
                    // tall as its stops, so padding here keeps the asphalt continuous
                    // from one unit to the next instead of cutting it between them.
                    PathUnitStretch(stretch: stretch)
                        .padding(.bottom, RoadMetrics.stopSpacing)
                }
                .opacity(stretch.progress.isUnlocked ? 1 : HabitRoad.lockedOpacity)
            }
        }
    }
}

/// The presentation rules of the road (S5), kept apart from the view so they can
/// be tested without a screen. Pure: it reads the same `HabitUnitProgress` values
/// the engine produced and decides only what they look like (S6).
enum HabitRoad {

    /// How a locked stretch reads: the same asphalt with its marks faded, so the
    /// way ahead is visible without claiming progress.
    static let lockedOpacity: CGFloat = 0.7

    /// How a level post that is not within reach reads, on top of whatever its
    /// stretch already is. A hollow dashed post is the shape of the claim; the fade
    /// only keeps it from competing with the level being played.
    static let lockedPostOpacity: CGFloat = 0.8

    /// One level of a unit, as the post that marks it.
    struct LevelMark: Identifiable, Equatable {

        /// 1…3 (`HabitPathEngine.levelRequirements`).
        let level: Int

        let state: LevelState

        var id: Int { level }
    }

    /// What a level post says.
    enum LevelState: Equatable {

        /// The level is behind: a red cap on the white post.
        case completed

        /// The level being played: the post outlined in `drivyTint`.
        case current

        /// Not reached yet: a hollow post with a dashed rule, faded.
        case locked
    }

    /// One unit as the road draws it.
    struct Stretch: Identifiable, Equatable {

        /// 1…`HabitUnit.allCases.count`, in path order: the number on the sign.
        let number: Int

        let progress: HabitUnitProgress

        /// `true` where the amber "Estás aquí" arrow stands.
        let showsPosition: Bool

        var id: String { progress.id }
    }

    /// The units, numbered from 1 and with the position arrow at the unit the user
    /// is playing.
    static func stretches(in units: [HabitUnitProgress]) -> [Stretch] {
        let positionID = positionUnitID(in: units)

        return units.enumerated().map { index, progress in
            Stretch(
                number: index + 1,
                progress: progress,
                showsPosition: progress.id == positionID
            )
        }
    }

    /// The three posts of one unit, in path order: the levels it has, the level it
    /// is on, and the ones still out of reach.
    static func levelMarks(for progress: HabitUnitProgress) -> [LevelMark] {
        let levels = HabitPathEngine.levelRequirements.count
        guard levels > 0 else { return [] }

        return (1...levels).map { level in
            LevelMark(level: level, state: levelState(level, in: progress))
        }
    }

    /// The state of one level post.
    ///
    /// A locked unit has no current post at all: nothing on the road may say a
    /// level is within reach before the unit opens (S3).
    static func levelState(_ level: Int, in progress: HabitUnitProgress) -> LevelState {
        guard progress.isUnlocked else { return .locked }
        if level <= progress.completedLevels { return .completed }
        if level == progress.completedLevels + 1, !progress.isCompleted { return .current }
        return .locked
    }

    /// The unit the amber arrow marks: the one being played; when the whole path is
    /// done, the last unit, which is where the road ends; and nothing at all when
    /// there is no open unit to stand on.
    static func positionUnitID(in units: [HabitUnitProgress]) -> String? {
        if let current = units.first(where: { $0.isUnlocked && !$0.isCompleted }) {
            return current.id
        }
        guard let last = units.last, last.isCompleted else { return nil }

        return last.id
    }
}

/// One unit of the road: the sign of the stretch, the row that says what it is, and
/// its three level posts pinned along the asphalt.
private struct PathUnitStretch: View {

    let stretch: HabitRoad.Stretch

    var body: some View {
        VStack(alignment: .leading, spacing: RoadMetrics.stopSpacing) {
            if stretch.showsPosition {
                RoadStop(pin: { CaminoPositionPin() }) {
                    Text("Estás aquí")
                        .font(.drivyHeadline)
                        .foregroundStyle(Color.drivyCautionText)
                }
            }

            RoadStop(combinesText: false, pin: { PathUnitSign(number: stretch.number) }) {
                HabitPathRow(progress: stretch.progress)
            }

            ForEach(HabitRoad.levelMarks(for: stretch.progress)) { mark in
                RoadStop(combinesText: false, pin: { PathLevelPost(mark: mark) }) {
                    EmptyView()
                }
            }
        }
    }
}

/// One unit of the path: what it teaches, how far the level being played is, and
/// where the unit stands (S3).
///
/// The words of the row, not the paint of the sign or the posts: one combined
/// VoiceOver element per unit, exactly as the trail had before the road.
private struct HabitPathRow: View {

    let progress: HabitUnitProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(progress.unit.title)
                .font(.drivyHeadline)
                .foregroundStyle(Color.drivyInk)

            Text(progress.unit.tip)
                .font(.drivyFootnote)
                .foregroundStyle(secondaryColor)
                .fixedSize(horizontal: false, vertical: true)

            if let progressText = progress.progressText {
                Text(progressText)
                    .font(.drivyFootnote)
                    .monospacedDigit()
                    .foregroundStyle(secondaryColor)
            }

            Text(progress.statusText)
                .font(.drivyKicker)
                .foregroundStyle(statusColor)
        }
        // One element per unit: the sign and the posts only repeat what the row says.
        .accessibilityElement(children: .combine)
    }

    /// The words of a closed stretch: `PathRoad` fades the whole stretch, so they
    /// start from full ink and read as a muted grey after the fade, which still meets
    /// S7 — `drivyInkMuted` faded on top of it would not.
    private var secondaryColor: Color {
        progress.isUnlocked ? Color.drivyInkMuted : Color.drivyInk
    }

    /// Green for a unit behind, tint blue for the one being played, muted for the
    /// ones still closed. The word of `statusText` says the same thing, so colour
    /// never carries it alone (S6).
    private var statusColor: Color {
        if !progress.isUnlocked { return Color.drivyInk }
        if progress.isCompleted { return Color.drivyGo }

        return Color.drivyTint
    }
}

/// The blue information panel that opens a unit: the face of `RoadSign`'s `.info`
/// case with the number of the unit on it.
///
/// T1 paints numbers only on the speed-limit disc, and a unit is not a limit, so
/// the panel is drawn here from the same tokens and the same measurements as the
/// sign. It never edits the design system; it borrows its geometry.
private struct PathUnitSign: View {

    let number: Int

    var body: some View {
        let side = RoadMetrics.signSize
        let inset = side * 0.07
        let rule = side * 0.05

        return ZStack {
            RoundedRectangle(cornerRadius: side * 0.12, style: .continuous)
                .fill(Color.drivySignBlue)

            RoundedRectangle(cornerRadius: side * 0.07, style: .continuous)
                .stroke(Color.drivySignFace, lineWidth: rule)
                .padding(inset)

            Text("\(number)")
                .font(
                    Font.custom(
                        DrivyFontName.condensedBold,
                        size: side * 0.46,
                        relativeTo: .body
                    )
                )
                .monospacedDigit()
                .foregroundStyle(Color.drivySignFace)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(.horizontal, side * 0.16)
        }
        .frame(width: side, height: side)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Unidad \(number)")
    }
}

/// One level of a unit as a hito: the cap of the ones behind, the tint ring of the
/// one being played, the dashed hollow post of the ones not reached yet.
///
/// A post that is still closed carries no number: `KmPost` leaves a pending post
/// unpainted, and a digit there would sit on the asphalt, where `drivyInk` is not
/// readable (S7). The row above already says which level is next.
private struct PathLevelPost: View {

    let mark: HabitRoad.LevelMark

    var body: some View {
        let isLocked = mark.state == .locked

        return KmPost(
            capColor: Color.drivySignRed,
            isToday: mark.state == .current,
            isPending: isLocked,
            size: KmPostSize.marker,
            accessibilityLabel: "Nivel \(mark.level), \(stateWords)"
        ) {
            if isLocked {
                EmptyView()
            } else {
                // The post is a sign face: white in both appearances, so its number
                // is the fixed dark of a painted sign, never `drivyInk`, which turns
                // near-white in the dark mode.
                Text("\(mark.level)")
                    .font(.drivyHeadline)
                    .monospacedDigit()
                    .foregroundStyle(Color.drivySignGlyph)
            }
        }
        // A level that is not within reach yet says so by being faint, the same way
        // the stretch it belongs to is faint.
        .opacity(isLocked ? HabitRoad.lockedPostOpacity : 1)
    }

    /// The state in words, so the ring and the cap are not the only signal (S6).
    private var stateWords: String {
        switch mark.state {
        case .completed: return "superado"
        case .current: return "en curso"
        case .locked: return "sin alcanzar"
        }
    }
}

/// The amber arrow of the user's position (S5): a dark disc with the road's own
/// edge line around it and an arrow in caution amber. Hoy marks «Ahora» the same
/// way; T1 has no component for it yet, so the drawing lives in this screen.
///
/// The disc is `drivySignGlyph` and not `drivyInk` for the same reason the km posts
/// are white in both appearances: the arrow sits on it, and `drivyInk` turns
/// near-white in dark mode, which would swallow the amber.
private struct CaminoPositionPin: View {

    var body: some View {
        let side = RoadMetrics.signSize

        return ZStack {
            Circle()
                .fill(Color.drivySignGlyph)

            Circle()
                .stroke(Color.drivyLaneMark, lineWidth: RoadMetrics.edgeLineWidth)

            Image(systemName: "location.north.fill")
                .font(.system(size: side * 0.45, weight: .semibold))
                .foregroundStyle(Color.drivyCaution)
        }
        .frame(width: side, height: side)
        // The words next to it say what it is; the arrow is the decoration.
        .accessibilityHidden(true)
    }
}

/// One labelled figure of the summary, in the type roles of the system.
///
/// `DriveMetric` still carries the system look of the MVP; this screen does not use
/// it so that the road can be read in Barlow (T1 left the rest of the surfaces for
/// their own tasks).
private struct PathFigure: View {

    let title: String

    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.drivyKicker)
                .foregroundStyle(Color.drivyInkMuted)

            Text(value)
                .font(.drivyTitle)
                .monospacedDigit()
                .foregroundStyle(Color.drivyInk)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

#Preview {
    PathView()
        .environmentObject(AuthViewModel())
}
