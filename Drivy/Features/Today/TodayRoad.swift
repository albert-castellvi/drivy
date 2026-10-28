import Foundation

/// The day as one ordered road (S5): what waits ahead of the driver, the position
/// «Ahora», and what is already behind.
///
/// Pure values, no clock of its own and no view model: `TodayView` reads the same
/// `TodaySnapshot` it already had and renders from the result, so the order of the
/// screen is a tested rule instead of a view detail.
///
/// The rules the builder pins (S5):
/// - pending quests and the lesson go **ahead**, in the order of the board;
/// - the lesson stays ahead even when it is done — its card always offered the
///   review («Repasar la lección»), so it is never a closed thing;
/// - completed quests go **behind** with their sign in a done state;
/// - today's drives go behind, newest first, with their events as signs;
/// - a completed quest never hides behind the drives: drives come first, the done
///   quests after them (no completion time exists to interleave them).
struct TodayRoad: Equatable {

    /// A quest or the lesson that the driver has not finished yet.
    struct AheadStop: Equatable, Identifiable {

        /// What the stop is, so the view can give the lesson its action.
        enum Role: Equatable {
            case quest
            case lesson
        }

        let id: String

        let role: Role

        /// The sign of the quest (`QuestSign`), already resolved so the view
        /// never re-maps a requirement.
        let sign: RoadSign.Kind

        let title: String

        let detail: String

        /// Title of the action the stop owns. Only the lesson has one.
        let actionTitle: String?
    }

    /// The position of the driver on the road («Ahora»).
    struct NowStop: Equatable {

        /// The state of the recording action, the same three the recorder shows.
        enum Action: Equatable {
            case start
            case stop
            case saving
        }

        let action: Action

        /// `true` while a drive records: the road moves and the live metrics
        /// belong to this stop (S9).
        let isRecording: Bool
    }

    /// One kind of event of a finished drive, with how many times it happened.
    struct EventStop: Equatable, Identifiable {

        let kind: DriveEventKind

        let count: Int

        var id: String { kind.rawValue }

        /// The sign this event wears (S3), resolved through `EventSign`.
        var sign: RoadSign.Kind { EventSign.sign(for: kind) }

        /// VoiceOver label with the count: the signs are small and identical at a
        /// glance, so the number has to be spoken.
        var accessibilityLabel: String {
            switch kind {
            case .harshBrake:
                return Self.plural(count, "frenada brusca", "frenadas bruscas")
            case .harshAcceleration:
                return Self.plural(count, "aceleración brusca", "aceleraciones bruscas")
            case .speeding:
                return Self.plural(count, "exceso de velocidad", "excesos de velocidad")
            case .phoneUse:
                return Self.plural(count, "uso del móvil", "usos del móvil")
            }
        }

        /// `1 frenada brusca` / `3 frenadas bruscas` — the singular only at one.
        private static func plural(_ count: Int, _ singular: String, _ plural: String) -> String {
            count == 1 ? "1 \(singular)" : "\(count) \(plural)"
        }
    }

    /// A drive of today, already finished, newest first.
    struct DriveStop: Equatable, Identifiable {

        /// The row behind the stop: the navigation to the detail needs it whole.
        let drive: DriveHistoryRow

        let timeText: String

        let scoreText: String

        let durationText: String

        /// The events with a count above zero, in the fixed order of the kinds.
        let events: [EventStop]

        var id: String { drive.id }
    }

    /// A quest of today already earned, shown behind with its sign muted.
    struct DoneQuestStop: Equatable, Identifiable {

        let id: String

        let sign: RoadSign.Kind

        let title: String

        let detail: String
    }

    /// One stop behind the driver: a drive or a completed quest.
    enum BehindStop: Equatable, Identifiable {
        case drive(DriveStop)
        case quest(DoneQuestStop)

        var id: String {
            switch self {
            case .drive(let stop):
                return stop.id
            case .quest(let stop):
                return stop.id
            }
        }
    }

    /// Long Spanish date of the header, e.g. `martes, 28 de octubre`.
    let dateText: String

    let ahead: [AheadStop]

    let now: NowStop

    let behind: [BehindStop]

    var driveStops: [DriveStop] {
        behind.compactMap { stop in
            if case .drive(let drive) = stop { return drive }
            return nil
        }
    }

    var doneQuestStops: [DoneQuestStop] {
        behind.compactMap { stop in
            if case .quest(let quest) = stop { return quest }
            return nil
        }
    }
}

extension TodayRoad {

    /// Titles of the lesson action, the two strings the lesson card of Hoy has
    /// always used (S6: byte-identical).
    static let lessonStartTitle = "Hacer la lección (1 minuto)"
    static let lessonReviewTitle = "Repasar la lección"

    /// The road of the day from the values `TodayView` already reads.
    ///
    /// - Parameters:
    ///   - snapshot: today's snapshot, quests in board order.
    ///   - isRecording / isSaving: the recorder state, carried into `now` (S9).
    ///   - now: the moment the road is drawn at; it decides only `dateText`.
    static func stops(
        from snapshot: TodaySnapshot,
        isRecording: Bool = false,
        isSaving: Bool = false,
        now: Date = Date()
    ) -> TodayRoad {
        let todayHasDirtyDriving = Streak.hasDirtyDrivingToday(
            dayScore: snapshot.score,
            drivesCount: snapshot.drivesCount
        )

        var ahead: [AheadStop] = []
        var doneQuests: [DoneQuestStop] = []

        for progress in snapshot.quests {
            let quest = progress.quest
            let isLesson = quest.requirement == .lesson

            // A completed lesson is not a closed thing: it stays ahead with the
            // review action, exactly as the old lesson card did.
            if progress.isCompleted, !isLesson {
                doneQuests.append(
                    DoneQuestStop(
                        id: quest.id,
                        sign: QuestSign.sign(for: quest),
                        title: quest.title,
                        detail: quest.detail
                    )
                )
                continue
            }

            let lessonDetail = Streak.lessonMessage(
                hasLessonToday: snapshot.hasLessonToday,
                todayHasDirtyDriving: todayHasDirtyDriving
            )

            ahead.append(
                AheadStop(
                    id: quest.id,
                    role: isLesson ? .lesson : .quest,
                    sign: QuestSign.sign(for: quest),
                    title: quest.title,
                    detail: isLesson ? lessonDetail : quest.detail,
                    actionTitle: isLesson
                        ? (snapshot.hasLessonToday ? lessonReviewTitle : lessonStartTitle)
                        : nil
                )
            )
        }

        let drives = snapshot.drives
            .sorted { $0.startedAt > $1.startedAt }
            .map { drive in
                DriveStop(
                    drive: drive,
                    timeText: DriveFormat.time(drive.startedAt),
                    scoreText: DriveFormat.score(drive.score),
                    durationText: DriveFormat.duration(TimeInterval(drive.durationSeconds)),
                    events: events(of: drive)
                )
            }

        let action: NowStop.Action
        if isSaving {
            action = .saving
        } else if isRecording {
            action = .stop
        } else {
            action = .start
        }

        return TodayRoad(
            dateText: dateText(for: now),
            ahead: ahead,
            now: NowStop(action: action, isRecording: isRecording),
            behind: drives.map(BehindStop.drive) + doneQuests.map(BehindStop.quest)
        )
    }

    /// Compact count of the freezes still left this week, for the streak line of
    /// the header («2 hielos»). The full sentence of `Streak.freezeText` stays on
    /// screen when there are none, because that is when it warns.
    static func freezesCountText(_ freezesLeftThisWeek: Int) -> String {
        freezesLeftThisWeek == 1 ? "1 hielo" : "\(freezesLeftThisWeek) hielos"
    }

    /// The header date: weekday, day and month in Spanish, e.g.
    /// `martes, 28 de octubre`. A new element of the redesign, so a new format.
    static func dateText(for date: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_ES")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "EEEE, d 'de' MMMM"
        return formatter.string(from: date)
    }

    /// The events of a stored drive row, kinds with a count above zero, in the
    /// fixed `sortOrder` of the kinds (brakes, accelerations, speeding, phone).
    static func events(of drive: DriveHistoryRow) -> [EventStop] {
        var events: [EventStop] = []
        if drive.harshBrakes > 0 {
            events.append(EventStop(kind: .harshBrake, count: drive.harshBrakes))
        }
        if drive.harshAccelerations > 0 {
            events.append(EventStop(kind: .harshAcceleration, count: drive.harshAccelerations))
        }
        if drive.speedingEvents > 0 {
            events.append(EventStop(kind: .speeding, count: drive.speedingEvents))
        }
        if drive.phoneUseEvents > 0 {
            events.append(EventStop(kind: .phoneUse, count: drive.phoneUseEvents))
        }
        return events
    }
}
