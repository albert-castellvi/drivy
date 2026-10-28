import XCTest
@testable import Drivy

/// The quiz of the day (S2) against the shared progress layer: the lesson is five
/// answers with immediate feedback, it is recorded once with the answers the user
/// gave, and finishing it is what makes the day count for the streak (S1) even when
/// questions are failed.
/// Fixed clock of the quiz tests: Europe/Madrid, so "day" means the Spanish day
/// and never the UTC one (L8).
private enum MadridClock {

    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(identifier: "Europe/Madrid") ?? .current
        return calendar
    }()

    static func date(day: Int, hour: Int, minute: Int = 0) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = day
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components) ?? Date(timeIntervalSince1970: 0)
    }

    /// Wednesday 2026-03-04 at 10:00 Europe/Madrid.
    static let now = date(day: 4, hour: 10)
}

@MainActor
final class LessonQuizViewModelTests: XCTestCase {

    /// Counts the S7 permission hooks of one test.
    private final class Counter {
        var value = 0
    }

    private func question(_ index: Int, correct: Int = 0) -> TheoryQuestion {
        TheoryQuestion(
            id: "q\(index)",
            text: "Pregunta \(index)",
            options: ["uno", "dos", "tres"],
            correct: correct,
            explanation: "Explicación \(index)."
        )
    }

    private func bank(count: Int = TheoryLessonPlanner.questionCount) -> [TheoryQuestion] {
        (0..<count).map { question($0) }
    }

    private func makeSUT(
        questions: [TheoryQuestion]? = nil,
        now: Date? = nil
    ) -> (sut: LessonQuizViewModel, fake: FakeProgressDataLoader, permission: Counter) {
        let fake = FakeProgressDataLoader()
        let counter = Counter()
        let sut = LessonQuizViewModel(
            questions: questions ?? bank(),
            calendar: MadridClock.calendar,
            now: { now ?? MadridClock.now },
            progressLoader: fake,
            requestNotificationPermission: { counter.value += 1 }
        )
        return (sut, fake, counter)
    }

    /// The wrong answer of the question on screen.
    private func wrongOption(of question: TheoryQuestion) -> Int {
        (question.correct + 1) % max(question.options.count, 1)
    }

    /// Answers the question on screen and moves on; the last call finishes the
    /// lesson.
    private func answer(_ sut: LessonQuizViewModel, correctly: Bool) async {
        guard let question = sut.question else { return }
        sut.select(option: correctly ? question.correct : wrongOption(of: question))
        await sut.advance()
    }

    // MARK: - Day key

    func testTheDayKeyComesFromTheInjectedClockAndCalendar() {
        let (sut, _, _) = makeSUT()

        XCTAssertEqual(sut.dayKey, "2026-03-04")
        XCTAssertEqual(sut.lesson.dayKey, sut.dayKey)
    }

    /// The day key is the local day (Europe/Madrid), not the UTC one: a lesson at
    /// 00:30 belongs to the new day, which is the day the streak counts (S1).
    func testALessonAfterMidnightBelongsToTheNewDay() {
        let (sut, _, _) = makeSUT(now: MadridClock.date(day: 5, hour: 0, minute: 30))

        XCTAssertEqual(sut.dayKey, "2026-03-05")
    }

    // MARK: - Immediate feedback

    func testACorrectAnswerShowsItsExplanation() {
        let (sut, _, _) = makeSUT()
        guard let question = sut.question else { return XCTFail("no question") }

        sut.select(option: question.correct)

        XCTAssertTrue(sut.isAnswered)
        XCTAssertEqual(sut.feedback?.isCorrect, true)
        XCTAssertEqual(sut.feedback?.explanation, question.explanation)
        XCTAssertEqual(sut.correctCount, 1)
    }

    func testAWrongAnswerNamesTheRightOptionAndKeepsTheCount() {
        let (sut, _, _) = makeSUT()
        guard let question = sut.question else { return XCTFail("no question") }

        sut.select(option: wrongOption(of: question))

        XCTAssertEqual(sut.feedback?.isCorrect, false)
        XCTAssertEqual(sut.feedback?.correctAnswer, question.options[question.correct])
        XCTAssertEqual(sut.correctCount, 0)
    }

    /// The first answer is the one that counts: tapping another option afterwards
    /// cannot turn a fail into a pass, and double tapping cannot add a point twice.
    func testTheFirstAnswerCannotBeChanged() {
        let (sut, _, _) = makeSUT()
        guard let question = sut.question else { return XCTFail("no question") }

        sut.select(option: wrongOption(of: question))
        sut.select(option: question.correct)

        XCTAssertEqual(sut.correctCount, 0)
        XCTAssertEqual(sut.feedback?.isCorrect, false)
    }

    func testAdvancingWithoutAnAnswerStaysOnTheQuestion() async {
        let (sut, _, _) = makeSUT()
        let text = sut.question?.text

        await sut.advance()

        XCTAssertEqual(sut.currentIndex, 0)
        XCTAssertEqual(sut.question?.text, text)
        XCTAssertNil(sut.result)
    }

    func testTheCopyOfTheQuizIsTheOneTheScreenShows() async {
        let (sut, _, _) = makeSUT()

        XCTAssertEqual(sut.progressText, "Pregunta 1 de 5")
        XCTAssertEqual(sut.actionTitle, LessonQuizViewModel.nextTitle)
        XCTAssertFalse(sut.isLastQuestion)

        for _ in 0..<4 {
            await answer(sut, correctly: true)
        }

        XCTAssertEqual(sut.progressText, "Pregunta 5 de 5")
        XCTAssertEqual(sut.actionTitle, LessonQuizViewModel.finishTitle)
        XCTAssertTrue(sut.isLastQuestion)
    }

    // MARK: - Recording (S2, S1)

    func testTheFinishedLessonIsRecordedWithTheAnswersOfTheDay() async {
        let (sut, fake, _) = makeSUT()

        await answer(sut, correctly: true)
        await answer(sut, correctly: true)
        await answer(sut, correctly: false)
        await answer(sut, correctly: false)
        await answer(sut, correctly: false)

        XCTAssertEqual(fake.lessons["2026-03-04"]?.correct, 2)
        XCTAssertEqual(fake.lessons["2026-03-04"]?.total, 5)
        XCTAssertEqual(sut.result, LessonResult(correct: 2, total: 5, dayKey: "2026-03-04"))
        XCTAssertNil(sut.errorMessage)
    }

    /// S2, verbatim: "Completar el test = lección del día (S1), aunque falles
    /// preguntas".
    func testALessonWithEveryAnswerWrongIsStillRecorded() async {
        let (sut, fake, _) = makeSUT()

        for _ in 0..<5 {
            await answer(sut, correctly: false)
        }

        XCTAssertEqual(fake.lessons["2026-03-04"]?.correct, 0)
        XCTAssertEqual(fake.lessons["2026-03-04"]?.total, 5)
        XCTAssertEqual(sut.result?.countsForTheDay, true)
    }

    func testTheLessonIsRecordedOnlyOnce() async {
        let (sut, fake, _) = makeSUT()

        for _ in 0..<5 {
            await answer(sut, correctly: true)
        }
        await sut.finish()
        await sut.advance()
        await sut.retryRecording()

        XCTAssertEqual(fake.lessons.count, 1)
        XCTAssertEqual(fake.lessons["2026-03-04"]?.total, 5)
    }

    func testAFailedWriteKeepsTheLessonAndCanBeRetried() async {
        let (sut, fake, _) = makeSUT()
        fake.failure = FakeProgressDataLoader.FakeError.network

        for _ in 0..<5 {
            await answer(sut, correctly: true)
        }

        XCTAssertEqual(sut.result, LessonResult(correct: 5, total: 5, dayKey: "2026-03-04"))
        XCTAssertEqual(sut.errorMessage, LessonQuizViewModel.recordFailureMessage)
        XCTAssertTrue(fake.lessons.isEmpty)

        fake.failure = nil
        await sut.retryRecording()

        XCTAssertNil(sut.errorMessage)
        XCTAssertEqual(fake.lessons["2026-03-04"]?.correct, 5)
    }

    // MARK: - Notification permission (S7)

    func testThePermissionIsAskedOnceAndOnlyAfterTheLessonIsRecorded() async {
        let (sut, _, permission) = makeSUT()

        await answer(sut, correctly: true)
        XCTAssertEqual(permission.value, 0)

        for _ in 0..<4 {
            await answer(sut, correctly: true)
        }

        XCTAssertEqual(permission.value, 1)

        // A retry of the same lesson must not ask again.
        await sut.retryRecording()
        XCTAssertEqual(permission.value, 1)
    }

    func testAFailedWriteDoesNotAskForThePermission() async {
        let (sut, fake, permission) = makeSUT()
        fake.failure = FakeProgressDataLoader.FakeError.network

        for _ in 0..<5 {
            await answer(sut, correctly: true)
        }

        XCTAssertEqual(permission.value, 0)
    }

    // MARK: - Unreadable bank

    func testAnEmptyBankHasNoQuestionAndRecordsNothing() async {
        let (sut, fake, _) = makeSUT(questions: [])

        XCTAssertNil(sut.question)
        XCTAssertEqual(sut.questionCount, 0)

        await sut.advance()
        await sut.finish()

        XCTAssertTrue(fake.lessons.isEmpty)
    }
}
