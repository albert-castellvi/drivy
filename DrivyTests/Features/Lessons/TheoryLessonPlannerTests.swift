import XCTest
@testable import Drivy

/// The lesson of the day (S2): five questions, always the same five for the same
/// day, and never exactly yesterday's five when the bank has anything else to
/// offer. Deterministic without `hashValue`, which is seeded per process.
final class TheoryLessonPlannerTests: XCTestCase {

    private static let madrid: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(identifier: "Europe/Madrid") ?? .current
        return calendar
    }()

    /// `2026-03-01` plus `offset` days, in Europe/Madrid.
    private func day(_ offset: Int, from start: String = "2026-03-01") -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Self.madrid
        formatter.timeZone = Self.madrid.timeZone
        formatter.dateFormat = "yyyy-MM-dd"

        guard
            let startDate = formatter.date(from: start),
            let shifted = Self.madrid.date(byAdding: .day, value: offset, to: startDate)
        else {
            return start
        }
        return formatter.string(from: shifted)
    }

    private func bank(_ count: Int = TheoryQuestionBank.minimumQuestionCount) -> [TheoryQuestion] {
        (0..<count).map { index in
            TheoryQuestion(
                id: "q\(index)",
                text: "Pregunta \(index)",
                options: ["uno", "dos", "tres"],
                correct: 0,
                explanation: "Explicación \(index)."
            )
        }
    }

    // MARK: - The lesson of the day

    func testTheLessonHasFiveQuestionsFromTheBank() {
        let questions = bank()
        let lesson = TheoryLessonPlanner.lesson(dayKey: day(0), questions: questions)

        XCTAssertEqual(lesson.count, TheoryLessonPlanner.questionCount)
        XCTAssertEqual(lesson.dayKey, day(0))
        XCTAssertEqual(Set(lesson.questions.map(\.id)).count, lesson.count, "a question repeats inside the lesson")
        for question in lesson.questions {
            XCTAssertTrue(questions.contains { $0.id == question.id })
        }
    }

    /// The same day has to serve the same lesson on every launch and after a
    /// reinstall: nothing about it is stored.
    func testTheSameDayAlwaysGivesTheSameLesson() {
        let questions = bank()

        XCTAssertEqual(
            TheoryLessonPlanner.lesson(dayKey: day(3), questions: questions).questions.map(\.id),
            TheoryLessonPlanner.lesson(dayKey: day(3), questions: questions).questions.map(\.id)
        )
    }

    func testDifferentDaysDoNotAlwaysGiveTheSameLesson() {
        let questions = bank()
        let lessons = (0..<10).map { offset in
            TheoryLessonPlanner.lesson(dayKey: day(offset), questions: questions).questions.map(\.id)
        }

        XCTAssertGreaterThan(Set(lessons.map { $0.joined(separator: ",") }).count, 1)
    }

    /// S2 wants new material every day a user comes back: yesterday's five are never
    /// served twice in a row while the bank has another question to offer.
    func testTheLessonNeverRepeatsThePreviousDay() {
        let questions = bank()

        for offset in 1..<40 {
            let today = TheoryLessonPlanner.lesson(
                dayKey: day(offset),
                questions: questions,
                previousDayKey: day(offset - 1)
            )
            let yesterday = TheoryLessonPlanner.lesson(
                dayKey: day(offset - 1),
                questions: questions,
                previousDayKey: day(offset - 2)
            )

            // The order of a day's lesson is the day's own, so the rule is about
            // the set of questions, not their order.
            XCTAssertNotEqual(
                Set(today.questions.map(\.id)),
                Set(yesterday.questions.map(\.id)),
                "day \(offset) repeats the lesson of the day before"
            )
            XCTAssertEqual(today.count, TheoryLessonPlanner.questionCount)
        }
    }

    func testThePreviousDayOfTheSameDayDoesNotChangeTheLesson() {
        let questions = bank()

        XCTAssertEqual(
            TheoryLessonPlanner.lesson(dayKey: day(0), questions: questions).questions.map(\.id),
            TheoryLessonPlanner.lesson(
                dayKey: day(0),
                questions: questions,
                previousDayKey: day(0)
            ).questions.map(\.id)
        )
    }

    // MARK: - Edges of the bank

    func testABankSmallerThanALessonGivesWhatItHas() {
        let lesson = TheoryLessonPlanner.lesson(dayKey: day(0), questions: bank(3))

        XCTAssertEqual(lesson.count, 3)
        XCTAssertEqual(Set(lesson.questions.map(\.id)).count, 3)
    }

    func testABankOfExactlyOneLessonCannotAvoidRepeatingYesterday() {
        let questions = bank(TheoryLessonPlanner.questionCount)

        let today = TheoryLessonPlanner.lesson(
            dayKey: day(1),
            questions: questions,
            previousDayKey: day(0)
        )
        let yesterday = TheoryLessonPlanner.lesson(dayKey: day(0), questions: questions)

        XCTAssertEqual(today.count, TheoryLessonPlanner.questionCount)
        XCTAssertEqual(Set(today.questions.map(\.id)), Set(yesterday.questions.map(\.id)))
    }

    func testAnEmptyBankGivesAnEmptyLesson() {
        let lesson = TheoryLessonPlanner.lesson(dayKey: day(0), questions: [])

        XCTAssertTrue(lesson.isEmpty)
        XCTAssertEqual(lesson.count, 0)
    }

    // MARK: - Previous day key

    func testThePreviousDayKeyIsTheDayBefore() {
        XCTAssertEqual(
            TheoryLessonPlanner.previousDayKey(before: "2026-03-01", calendar: Self.madrid),
            "2026-02-28"
        )
    }

    /// The key follows the injected calendar, so a month and a DST change both
    /// walk one day, not 23 or 25 hours.
    func testThePreviousDayKeyFollowsTheInjectedCalendar() {
        XCTAssertEqual(
            TheoryLessonPlanner.previousDayKey(before: "2026-03-30", calendar: Self.madrid),
            "2026-03-29"
        )
        XCTAssertEqual(
            TheoryLessonPlanner.previousDayKey(before: "2026-01-01", calendar: Self.madrid),
            "2025-12-31"
        )
    }

    func testAnUnreadableDayKeyHasNoPreviousDay() {
        XCTAssertNil(TheoryLessonPlanner.previousDayKey(before: "no-es-un-día", calendar: Self.madrid))
    }

    // MARK: - Hash

    func testTheStableHashIsStableAndDiscriminates() {
        XCTAssertEqual(TheoryLessonPlanner.stableHash("2026-03-01|q1"), TheoryLessonPlanner.stableHash("2026-03-01|q1"))
        XCTAssertNotEqual(TheoryLessonPlanner.stableHash("2026-03-01|q1"), TheoryLessonPlanner.stableHash("2026-03-02|q1"))
    }
}
