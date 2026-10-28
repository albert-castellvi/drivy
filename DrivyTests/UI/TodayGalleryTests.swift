import SwiftUI
import XCTest

@testable import Drivy

/// S8 on the road of the day: the four states Hoy and the Histórico have to prove
/// in light and dark — an empty day, a midday with drives and an earned quest, a
/// recording drive, and the history list with its hitos.
///
/// The screens render from fixtures: `TodayHeader` and `TodayRoadView` take the
/// plain values of `TodayRoad` and `TodayNowValues`, so the gallery shows the real
/// layout of the tab without a view model, a recorder or a network. The repair
/// block is conditional (`repairableDay != nil`) and lives in `TodayView`, so it is
/// deliberately outside the gallery; the mockup PNGs the parent reviews (T6) prove
/// the rest.
@MainActor
final class TodayGalleryTests: XCTestCase {

    private static let screenWidth: CGFloat = 390

    private static let todayHeight: CGFloat = 1_100

    private static let historyHeight: CGFloat = 844

    func testTodayEmptyGallery() {
        renderGallery(
            "today-empty",
            width: Self.screenWidth,
            height: Self.todayHeight
        ) {
            TodayGalleryScreen(snapshot: Self.emptyDay, isRecording: false)
        }
    }

    func testTodayMiddayGallery() {
        renderGallery(
            "today-midday",
            width: Self.screenWidth,
            height: Self.todayHeight
        ) {
            TodayGalleryScreen(snapshot: Self.midday, isRecording: false)
        }
    }

    func testTodayRecordingGallery() {
        renderGallery(
            "today-recording",
            width: Self.screenWidth,
            height: Self.todayHeight
        ) {
            TodayGalleryScreen(snapshot: Self.emptyDay, isRecording: true)
        }
    }

    func testHistoryGallery() {
        renderGallery(
            "history",
            width: Self.screenWidth,
            height: Self.historyHeight
        ) {
            NavigationStack {
                HistoryView(days: Self.historyDays)
            }
            .environmentObject(FreemiumService(anchorDate: Self.referenceDay))
        }
    }

    // MARK: - Fixtures

    /// Wednesday 28 October 2026, local noon: the day of the redesign.
    /// `fileprivate`: the fixture screen below reads it.
    fileprivate static var referenceDay: Date {
        Calendar.current.date(
            from: DateComponents(year: 2026, month: 10, day: 28, hour: 12, minute: 0)
        ) ?? Date(timeIntervalSince1970: 0)
    }

    private static func localDate(hour: Int, minute: Int) -> Date {
        Calendar.current.date(
            from: DateComponents(year: 2026, month: 10, day: 28, hour: hour, minute: minute)
        ) ?? referenceDay
    }

    private static var streak: Streak {
        Streak(
            days: 12,
            freezesUsedThisWeek: 2,
            freezesLeftThisWeek: 2,
            isTodayCounted: false,
            repairableDay: nil
        )
    }

    /// The two driving quests of the empty board and the lesson, all pending.
    private static var pendingQuests: [DailyQuestProgress] {
        let driving = QuestCatalog.all
            .filter { $0.requirement.needsDriving }
            .prefix(2)
            .map { DailyQuestProgress(quest: $0, isCompleted: false) }
        return Array(driving) + [DailyQuestProgress(quest: QuestCatalog.lesson, isCompleted: false)]
    }

    /// A day without drives yet: pending quests, no score, XP already earned on
    /// earlier days.
    private static var emptyDay: TodaySnapshot {
        TodaySnapshot(
            dayKey: "2026-10-28",
            score: nil,
            distanceKm: 0,
            drivesCount: 0,
            streak: streak,
            drives: [],
            days: historyDays,
            xp: XPTotals(totalXP: 1_240, weekXP: 180),
            quests: pendingQuests,
            pendingQuestIDs: [],
            hasLessonToday: false,
            lastStreakRepairAt: nil
        )
    }

    private static func drive(
        id: String,
        hour: Int,
        minute: Int,
        score: Int,
        durationSeconds: Int,
        harshBrakes: Int = 0
    ) -> DriveHistoryRow {
        let start = localDate(hour: hour, minute: minute)
        return DriveHistoryRow(
            id: id,
            startedAt: start,
            endedAt: start.addingTimeInterval(TimeInterval(durationSeconds)),
            distanceKm: 12,
            durationSeconds: durationSeconds,
            score: score,
            harshBrakes: harshBrakes,
            harshAccelerations: 0,
            phoneUseEvents: 0,
            speedingEvents: 0,
            connectedMode: false
        )
    }

    /// Two drives (the afternoon one with a harsh brake), one quest earned this
    /// morning, two still pending and the lesson to do.
    private static var midday: TodaySnapshot {
        let earned = QuestCatalog.all.first { $0.requirement == .driveWithoutPhoneUse }
            ?? QuestCatalog.all.first { $0.requirement.needsDriving }!

        var quests = pendingQuests
        quests[0] = DailyQuestProgress(quest: earned, isCompleted: true)

        return TodaySnapshot(
            dayKey: "2026-10-28",
            score: 87,
            distanceKm: 24.5,
            drivesCount: 2,
            streak: Streak(
                days: 12,
                freezesUsedThisWeek: 2,
                freezesLeftThisWeek: 2,
                isTodayCounted: true,
                repairableDay: nil
            ),
            drives: [
                drive(id: "tarde", hour: 13, minute: 40, score: 83, durationSeconds: 1_320, harshBrakes: 1),
                drive(id: "manana", hour: 8, minute: 12, score: 91, durationSeconds: 1_500),
            ],
            days: historyDays,
            xp: XPTotals(totalXP: 1_240, weekXP: 180),
            quests: quests,
            pendingQuestIDs: [],
            hasLessonToday: false,
            lastStreakRepairAt: nil
        )
    }

    /// Days for the Histórico list and for the link under the road.
    private static var historyDays: [HistoryDay] {
        let entries: [(key: String, day: Int, score: Int, km: Double, drives: Int)] = [
            ("2026-10-28", 28, 87, 24.5, 2),
            ("2026-10-27", 27, 91, 18.2, 1),
            ("2026-10-26", 26, 64, 30.0, 3),
            ("2026-10-23", 23, 78, 12.4, 1),
            ("2026-10-22", 22, 85, 9.8, 1),
            ("2026-10-21", 21, 93, 41.6, 4),
        ]
        return entries.map { entry in
            HistoryDay(
                dayKey: entry.key,
                date: Calendar.current.date(
                    from: DateComponents(year: 2026, month: 10, day: entry.day)
                ) ?? referenceDay,
                score: entry.score,
                distanceKm: entry.km,
                drivesCount: entry.drives
            )
        }
    }
}

// MARK: - The fixture screen

/// The Hoy tab without its view model: the same `TodayHeader` + `TodayRoadView`
/// the tab renders, fed by a fixture snapshot. The road and the «Ahora» state come
/// from `TodayRoad.stops`, exactly like the live screen.
private struct TodayGalleryScreen: View {

    let snapshot: TodaySnapshot

    let isRecording: Bool

    var body: some View {
        let road = TodayRoad.stops(
            from: snapshot,
            isRecording: isRecording,
            now: TodayGalleryTests.referenceDay
        )

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    TodayHeader(dateText: road.dateText, snapshot: snapshot)

                    TodayRoadView(
                        road: road,
                        now: nowValues,
                        historyDays: snapshot.days
                    )
                }
                .padding()
            }
            .background(Color.drivyPaper)
            .navigationTitle("Hoy")
        }
    }

    /// The recorder is not part of the gallery: the same fields, given directly,
    /// with the copy the live tab uses.
    private var nowValues: TodayNowValues {
        if isRecording {
            return TodayNowValues(
                stateTitle: "Trayecto en curso",
                buttonTitle: "Terminar trayecto",
                isRecording: true,
                showsStats: true,
                showsConnectedModeLabel: true,
                distanceText: "2,4 km",
                scoreText: "81",
                elapsedText: { _ in "07:12" },
                errorMessage: nil
            )
        }

        let finishedDrive = snapshot.drivesCount > 0
        return TodayNowValues(
            stateTitle: finishedDrive ? "Último trayecto" : "Registrar trayecto",
            buttonTitle: "Empezar trayecto",
            isRecording: false,
            showsStats: finishedDrive,
            showsConnectedModeLabel: false,
            distanceText: String(format: "%.1f km", snapshot.drives.first?.distanceKm ?? 0),
            scoreText: snapshot.drives.first.map { String($0.score) } ?? "—",
            elapsedText: { _ in DriveFormat.duration(TimeInterval(snapshot.drives.first?.durationSeconds ?? 0)) },
            errorMessage: nil
        )
    }
}
