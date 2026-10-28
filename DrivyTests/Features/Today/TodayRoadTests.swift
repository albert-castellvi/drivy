import XCTest

@testable import Drivy

/// Rules of the road builder (T2, S5): what goes ahead, what goes behind, in
/// which order, and what the copy of the lesson stop says on a dirty day.
///
/// Everything is asserted through `TodayRoad.stops` and the plain value types it
/// returns — no view, no clock of its own: the reference moment and the local
/// dates are built through `Calendar.current`, so the formatted strings do not
/// depend on the zone of the runner.
final class TodayRoadTests: XCTestCase {

    /// Wednesday 28 October 2026, local noon: the day of the redesign.
    private var referenceDay: Date {
        localDate(year: 2026, month: 10, day: 28, hour: 12, minute: 0)
    }

    // MARK: - Ahead: pending quests and lesson, in board order

    func testPendingQuestsAndLessonGoAheadInBoardOrder() {
        let road = TodayRoad.stops(
            from: snapshot(quests: [
                quest(id: "cero_movil"),
                quest(id: "lesson", requirement: .lesson),
                quest(id: "sin_aceptos"),
            ]),
            now: referenceDay
        )

        XCTAssertEqual(road.ahead.map(\.id), ["cero_movil", "lesson", "sin_aceptos"])
        XCTAssertEqual(road.ahead.map(\.role), [.quest, .lesson, .quest])
        XCTAssertNil(road.ahead[0].actionTitle, "a plain quest has no action of its own")
        XCTAssertEqual(road.doneQuestStops.count, 0)
    }

    func testQuestStopCarriesItsOwnTitleAndDetail() {
        let road = TodayRoad.stops(
            from: snapshot(quests: [quest(id: "frenada_suave")]),
            now: referenceDay
        )

        XCTAssertEqual(road.ahead[0].title, "Título frenada_suave")
        XCTAssertEqual(road.ahead[0].detail, "Detalle frenada_suave")
    }

    func testLessonStopCarriesTheLessonSignAndTheStartAction() {
        let road = TodayRoad.stops(
            from: snapshot(quests: [quest(id: "lesson", requirement: .lesson)]),
            now: referenceDay
        )

        XCTAssertEqual(road.ahead[0].sign, .info(systemName: "book.closed"))
        XCTAssertEqual(road.ahead[0].actionTitle, TodayRoad.lessonStartTitle)
    }

    func testCompletedLessonStaysAheadWithTheReviewAction() {
        let road = TodayRoad.stops(
            from: snapshot(
                quests: [quest(id: "lesson", requirement: .lesson, completed: true)],
                hasLessonToday: true
            ),
            now: referenceDay
        )

        XCTAssertEqual(road.ahead.count, 1)
        XCTAssertEqual(road.ahead[0].role, .lesson)
        XCTAssertEqual(road.ahead[0].actionTitle, TodayRoad.lessonReviewTitle)
        XCTAssertEqual(
            road.ahead[0].detail,
            "Ya has hecho la lección de hoy: cuenta para tu racha."
        )
        XCTAssertTrue(road.behind.isEmpty, "a done lesson is not a completed quest behind")
    }

    func testLessonOnADirtyDayStatesTheRuleInsteadOfPromisingTheDay() {
        // B5: today already drove below the clean-day threshold.
        let road = TodayRoad.stops(
            from: snapshot(
                score: 60,
                drivesCount: 1,
                quests: [quest(id: "lesson", requirement: .lesson)]
            ),
            now: referenceDay
        )

        XCTAssertEqual(road.ahead[0].detail, Streak.notRescuedTodayMessage)
        XCTAssertEqual(road.ahead[0].actionTitle, TodayRoad.lessonStartTitle)
    }

    // MARK: - Behind: completed quests, drives newest first, drives first

    func testCompletedQuestsGoBehind() {
        let road = TodayRoad.stops(
            from: snapshot(quests: [
                quest(id: "trayecto_limpio", completed: true),
                quest(id: "pendiente"),
            ]),
            now: referenceDay
        )

        XCTAssertEqual(road.ahead.map(\.id), ["pendiente"])
        let done = road.doneQuestStops
        XCTAssertEqual(done.map(\.id), ["trayecto_limpio"])
        XCTAssertEqual(done[0].title, "Título trayecto_limpio")
        XCTAssertEqual(done[0].detail, "Detalle trayecto_limpio")
    }

    func testDrivesGoBehindNewestFirst() {
        let morning = localDate(year: 2026, month: 10, day: 28, hour: 8, minute: 12)
        let afternoon = localDate(year: 2026, month: 10, day: 28, hour: 13, minute: 40)

        let road = TodayRoad.stops(
            from: snapshot(drives: [
                drive(id: "old", startedAt: morning, score: 91),
                drive(id: "new", startedAt: afternoon, score: 83),
            ]),
            now: referenceDay
        )

        let stops = road.driveStops
        XCTAssertEqual(stops.map(\.id), ["new", "old"])
        XCTAssertEqual(stops[0].timeText, "13:40")
        XCTAssertEqual(stops[0].scoreText, "83")
        XCTAssertEqual(stops[0].durationText, "10:00")
        XCTAssertEqual(stops[0].drive.id, "new", "the stop keeps the row for the detail link")
    }

    func testDrivesComeBeforeTheCompletedQuests() {
        let road = TodayRoad.stops(
            from: snapshot(
                drives: [drive(id: "d1", startedAt: referenceDay)],
                quests: [quest(id: "completada", completed: true)]
            ),
            now: referenceDay
        )

        XCTAssertEqual(road.behind.count, 2)
        if case .drive = road.behind[0] {
            // expected
        } else {
            XCTFail("the drive comes first behind")
        }
        if case .quest = road.behind[1] {
            // expected
        } else {
            XCTFail("the completed quest follows the drives")
        }
    }

    // MARK: - Events of a drive

    func testDriveEventsKeepOnlyTheCountedKindsInTheirFixedOrder() {
        let row = drive(
            id: "d1",
            startedAt: referenceDay,
            harshBrakes: 2,
            harshAccelerations: 3,
            phoneUseEvents: 1,
            speedingEvents: 0
        )
        let events = TodayRoad.events(of: row)

        XCTAssertEqual(
            events,
            [
                TodayRoad.EventStop(kind: .harshBrake, count: 2),
                TodayRoad.EventStop(kind: .harshAcceleration, count: 3),
                TodayRoad.EventStop(kind: .phoneUse, count: 1),
            ]
        )
        XCTAssertEqual(events[0].sign, .warning(systemName: "exclamationmark"))
        XCTAssertEqual(events[2].sign, .prohibition(systemName: "iphone"))
    }

    func testEventAccessibilityLabelCountsInTheRightWords() {
        XCTAssertEqual(
            TodayRoad.EventStop(kind: .harshBrake, count: 1).accessibilityLabel,
            "1 frenada brusca"
        )
        XCTAssertEqual(
            TodayRoad.EventStop(kind: .harshBrake, count: 4).accessibilityLabel,
            "4 frenadas bruscas"
        )
        XCTAssertEqual(
            TodayRoad.EventStop(kind: .harshAcceleration, count: 2).accessibilityLabel,
            "2 aceleraciones bruscas"
        )
        XCTAssertEqual(
            TodayRoad.EventStop(kind: .speeding, count: 3).accessibilityLabel,
            "3 excesos de velocidad"
        )
        XCTAssertEqual(
            TodayRoad.EventStop(kind: .phoneUse, count: 1).accessibilityLabel,
            "1 uso del móvil"
        )
        XCTAssertEqual(
            TodayRoad.EventStop(kind: .phoneUse, count: 2).accessibilityLabel,
            "2 usos del móvil"
        )
    }

    func testDriveWithoutEventsHasNoSigns() {
        let events = TodayRoad.events(of: drive(id: "d1", startedAt: referenceDay))
        XCTAssertTrue(events.isEmpty)
    }

    // MARK: - Now

    func testEmptyDayIsJustThePosition() {
        let road = TodayRoad.stops(from: .empty, now: referenceDay)

        XCTAssertTrue(road.ahead.isEmpty)
        XCTAssertTrue(road.behind.isEmpty)
        XCTAssertEqual(road.now, TodayRoad.NowStop(action: .start, isRecording: false))
    }

    func testRecordingFlagIsCarriedIntoNow() {
        let recording = TodayRoad.stops(
            from: .empty,
            isRecording: true,
            now: referenceDay
        )
        XCTAssertEqual(recording.now.action, .stop)
        XCTAssertTrue(recording.now.isRecording)

        let saving = TodayRoad.stops(
            from: .empty,
            isRecording: true,
            isSaving: true,
            now: referenceDay
        )
        XCTAssertEqual(saving.now.action, .saving)

        let idle = TodayRoad.stops(from: .empty, now: referenceDay)
        XCTAssertEqual(idle.now.action, .start)
        XCTAssertFalse(idle.now.isRecording)
    }

    // MARK: - Header copy helpers

    func testDateTextIsTheLongSpanishDate() {
        XCTAssertEqual(TodayRoad.dateText(for: referenceDay), "miércoles, 28 de octubre")
    }

    func testFreezesCountText() {
        XCTAssertEqual(TodayRoad.freezesCountText(1), "1 hielo")
        XCTAssertEqual(TodayRoad.freezesCountText(2), "2 hielos")
        XCTAssertEqual(TodayRoad.freezesCountText(0), "0 hielos")
    }

    // MARK: - S6: the copy of the screen, byte-identical

    /// S6 guard: the promise strings the tests pin survive the redesign verbatim,
    /// the removed section headers do not come back, and the road files keep the
    /// forbidden decoration out (S4). Read from the source of the three screen
    /// files, because what matters is the exact bytes the user sees.
    func testScreenCopyStaysByteIdenticalAndDecorationStaysOut() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Today
            .deletingLastPathComponent()   // Features
            .deletingLastPathComponent()   // DrivyTests
            .deletingLastPathComponent()   // repo root
        let screens = [
            "Drivy/Features/Today/TodayRoad.swift",
            "Drivy/Features/Today/TodayView.swift",
            "Drivy/Features/Today/HistoryView.swift",
        ]
        let source = try screens
            .map { try String(contentsOf: root.appendingPathComponent($0), encoding: .utf8) }
            .joined(separator: "\n")

        for promise in [
            "Driver Score de hoy",
            "Registra tu primer trayecto del día para tener nota.",
            "El XP premia cómo conduces y lo que aprendes, nunca los kilómetros.",
            "Se renuevan cada día. Ninguna misión pide conducir más.",
            "Aún no hay trayectos hoy.",
            "Trayectos de hoy",
            "Histórico",
            "Compartir mi tarjeta",
            "Conducción conectada",
            "Empezar trayecto",
            "Terminar trayecto",
            "Guardando…",
            "Trayecto en curso",
            "Registrar trayecto",
            "Último trayecto",
            "Aún no hay días registrados. En cuanto completes un trayecto, aparecerá aquí.",
            "1 día bloqueado",
            "\\(hiddenDays) días bloqueados",
        ] {
            XCTAssertTrue(source.contains(promise), "S6 promise lost: \(promise)")
        }

        for gone in [
            "Misiones de hoy",
            "Label(\"Racha\"",
            "Label(\"XP\"",
            "flame",
            "sparkles",
            "snowflake",
            "text.book.closed.fill",
            "checkmark.circle.fill",
        ] {
            XCTAssertFalse(source.contains(gone), "old header of the screen is back: \(gone)")
        }

        for decoration in ["Gradient", ".shadow(", ".secondary", "accentColor", "UIColor(red:"] {
            XCTAssertFalse(source.contains(decoration), "S3/S4 decoration forbidden: \(decoration)")
        }
    }

    func testLessonTitlesStayByteIdentical() {
        XCTAssertEqual(TodayRoad.lessonStartTitle, "Hacer la lección (1 minuto)")
        XCTAssertEqual(TodayRoad.lessonReviewTitle, "Repasar la lección")
    }

    // MARK: - Fixtures

    private func localDate(year: Int, month: Int, day: Int, hour: Int, minute: Int) -> Date {
        Calendar.current.date(
            from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        ) ?? Date(timeIntervalSince1970: 0)
    }

    private func quest(
        id: String,
        requirement: QuestRequirement = .driveWithoutHarshBrakes,
        completed: Bool = false
    ) -> DailyQuestProgress {
        DailyQuestProgress(
            quest: DailyQuest(
                id: id,
                title: "Título \(id)",
                detail: "Detalle \(id)",
                requirement: requirement
            ),
            isCompleted: completed
        )
    }

    private func drive(
        id: String,
        startedAt: Date,
        score: Int = 80,
        harshBrakes: Int = 0,
        harshAccelerations: Int = 0,
        phoneUseEvents: Int = 0,
        speedingEvents: Int = 0
    ) -> DriveHistoryRow {
        DriveHistoryRow(
            id: id,
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(600),
            distanceKm: 10,
            durationSeconds: 600,
            score: score,
            harshBrakes: harshBrakes,
            harshAccelerations: harshAccelerations,
            phoneUseEvents: phoneUseEvents,
            speedingEvents: speedingEvents,
            connectedMode: false
        )
    }

    private func snapshot(
        score: Int? = nil,
        drivesCount: Int = 0,
        drives: [DriveHistoryRow] = [],
        quests: [DailyQuestProgress] = [],
        hasLessonToday: Bool = false
    ) -> TodaySnapshot {
        TodaySnapshot(
            dayKey: "2026-10-28",
            score: score,
            distanceKm: 0,
            drivesCount: drivesCount,
            streak: .empty,
            drives: drives,
            days: [],
            xp: nil,
            quests: quests,
            pendingQuestIDs: [],
            hasLessonToday: hasLessonToday,
            lastStreakRepairAt: nil
        )
    }
}
