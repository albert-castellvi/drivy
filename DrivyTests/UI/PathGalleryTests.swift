import SwiftUI
import XCTest
@testable import Drivy

/// T4 (S5, S6, S9): the rules the Camino road draws from, and the visual proof of
/// the two screens it owns.
///
/// `HabitRoad` is presentation only: it takes the `HabitUnitProgress` values
/// `HabitPathEngine` already produced and decides what each one looks like, so these
/// tests pin the claims the road is allowed to make — a locked unit has no level
/// within reach, a post never marks a level the engine did not count, the arrow
/// stands where the user is — without a screen, a network or a view model (S6).
@MainActor
final class HabitRoadTests: XCTestCase {

    // MARK: - The posts of a stretch

    func testAFreshUnitMakesItsFirstLevelTheCurrentOne() {
        let marks = HabitRoad.levelMarks(for: PathRoadFixture.unit(.smoothBraking, levels: 0, drives: 0))

        XCTAssertEqual(
            marks,
            [
                HabitRoad.LevelMark(level: 1, state: .current),
                HabitRoad.LevelMark(level: 2, state: .locked),
                HabitRoad.LevelMark(level: 3, state: .locked)
            ]
        )
    }

    func testAResetLevelIsAPostBehindAndTheNextOneIsCurrent() {
        let marks = HabitRoad.levelMarks(for: PathRoadFixture.unit(.smoothBraking, levels: 1, drives: 4))

        XCTAssertEqual(marks.map(\.state), [.completed, .current, .locked])
    }

    func testTheLastLevelOfAnOpenUnitIsCurrentAndNotLocked() {
        let marks = HabitRoad.levelMarks(for: PathRoadFixture.unit(.smoothBraking, levels: 2, drives: 9))

        XCTAssertEqual(marks.map(\.state), [.completed, .completed, .current])
    }

    func testACompletedUnitHasEveryPostBehindAndNoneCurrent() {
        let marks = HabitRoad.levelMarks(for: PathRoadFixture.unit(.smoothBraking, levels: 3, drives: 15))

        XCTAssertEqual(marks.map(\.state), [.completed, .completed, .completed])
    }

    func testALockedUnitHasNoCurrentPostAtAll() {
        // S3: a closed unit has not been opened, so nothing on the road may claim a
        // level within reach, not even its first one.
        let marks = HabitRoad.levelMarks(for: PathRoadFixture.locked(.noPhone))

        XCTAssertEqual(marks.map(\.state), [.locked, .locked, .locked])
    }

    func testTheRoadHoldsOnePostPerLevelOfTheEngine() {
        let levels = HabitPathEngine.levelRequirements.count
        let marks = HabitRoad.levelMarks(for: PathRoadFixture.unit(.speed, levels: 1, drives: 5))

        XCTAssertEqual(marks.count, levels)
        XCTAssertEqual(marks.map(\.level), Array(1...levels))
    }

    func testTheFadedRoadAheadStaysVisible() {
        // S5: locked stretches fade the road. A value of 1 would make them look
        // reached; 0 would erase the way ahead.
        XCTAssertGreaterThan(HabitRoad.lockedOpacity, 0)
        XCTAssertLessThan(HabitRoad.lockedOpacity, 1)
        // A post ahead fades too, but the two fades together must leave it readable.
        XCTAssertGreaterThan(HabitRoad.lockedPostOpacity, HabitRoad.lockedOpacity)
        XCTAssertGreaterThan(HabitRoad.lockedOpacity * HabitRoad.lockedPostOpacity, 0.5)
    }

    // MARK: - Where the user stands

    func testTheRoadNumbersTheUnitsInPathOrder() {
        let stretches = HabitRoad.stretches(in: PathRoadFixture.path([0]))

        XCTAssertEqual(stretches.map(\.number), Array(1...HabitUnit.allCases.count))
        XCTAssertEqual(stretches.map(\.progress.id), HabitUnit.allCases.map(\.id))
    }

    func testTheArrowStandsAtTheUnitBeingPlayed() {
        let stretches = HabitRoad.stretches(in: PathRoadFixture.path([3, 1]))

        XCTAssertEqual(stretches.filter(\.showsPosition).map(\.progress.unit), [.smoothAcceleration])
    }

    func testTheArrowStandsAtTheFirstUnitWhenNothingIsReached() {
        let stretches = HabitRoad.stretches(in: PathRoadFixture.path([0]))

        XCTAssertEqual(stretches.first?.number, 1)
        XCTAssertEqual(stretches.first?.progress.unit, .smoothBraking)
        XCTAssertEqual(stretches.filter(\.showsPosition).count, 1)
    }

    func testTheArrowStandsAtTheLastUnitWhenTheWholePathIsDone() {
        let stretches = HabitRoad.stretches(in: PathRoadFixture.path([3, 3, 3, 3, 3]))

        XCTAssertEqual(stretches.last?.number, HabitUnit.allCases.count)
        XCTAssertEqual(stretches.last?.showsPosition, true)
        XCTAssertEqual(stretches.filter(\.showsPosition).count, 1)
    }

    func testTheRoadDrawsNoArrowWithoutAnOpenUnit() {
        // A path whose first unit is closed is not something the engine returns today;
        // the road still must not invent a position for it.
        let closed = HabitUnit.allCases.map { PathRoadFixture.locked($0) }

        XCTAssertNil(HabitRoad.positionUnitID(in: closed))
        XCTAssertNil(HabitRoad.positionUnitID(in: []))
        XCTAssertFalse(HabitRoad.stretches(in: closed).contains(where: \.showsPosition))
    }
}

// MARK: - The gallery (S8)

/// The two screens T4 owns, rendered with fixtures in light and dark: the road at
/// its two honest moments and the lesson at the three states a user passes through.
@MainActor
final class PathGalleryTests: XCTestCase {

    /// Taller than a phone on purpose: the road is a scroll, and the reviewer has to
    /// see all five units — the reached ones and the faded ones ahead — in one image.
    private static let roadHeight: CGFloat = 1_700

    private static let screenWidth: CGFloat = 390

    func testPathStartRendersInLightAndDark() {
        renderGallery("path-start", width: Self.screenWidth, height: Self.roadHeight) {
            PathRoad(units: PathRoadFixture.path([0]))
                .padding()
        }
    }

    func testPathProgressRendersInLightAndDark() {
        renderGallery("path-progress", width: Self.screenWidth, height: Self.roadHeight) {
            PathRoad(units: PathRoadFixture.path([3, 1]))
                .padding()
        }
    }

    /// The other half of the tab: the lesson entry and the figures, which the road
    /// alone cannot show (S8 asks for each redesigned screen).
    func testPathBriefingRendersInLightAndDark() {
        let snapshot = HabitPathSnapshot(
            units: PathRoadFixture.path([3, 1]),
            pendingLevels: [],
            hasLessonToday: false
        )

        renderGallery("path-briefing", width: Self.screenWidth, height: 420) {
            PathBriefing(snapshot: snapshot) {}
                .padding()
        }
    }

    func testQuizQuestionRendersInLightAndDark() {
        let model = makeQuizModel()
        XCTAssertNotNil(model.question, "the bundled bank served no question to the gallery")

        renderGallery("quiz-question", width: Self.screenWidth) {
            LessonQuizView(model: model, onFinished: { _, _ in })
        }
    }

    func testQuizAnsweredWrongRendersInLightAndDark() {
        let model = makeQuizModel()
        guard let question = model.question else {
            XCTFail("the bundled bank served no question to the gallery")
            return
        }
        model.select(option: wrongOption(of: question))

        guard let feedback = model.feedback else {
            XCTFail("answering the lesson left the quiz without feedback")
            return
        }
        XCTAssertFalse(feedback.isCorrect, "the gallery fixture answered correctly")

        renderGallery("quiz-answered-wrong", width: Self.screenWidth) {
            LessonQuizView(model: model, onFinished: { _, _ in })
        }
    }

    func testQuizDoneRendersInLightAndDark() async {
        let model = makeQuizModel()
        await answerLesson(model, correct: 3)
        XCTAssertNotNil(model.result, "the lesson did not reach its summary")

        renderGallery("quiz-done", width: Self.screenWidth) {
            LessonQuizView(model: model, onFinished: { _, _ in })
        }
    }

    // MARK: - Quiz fixtures

    /// The real bank of the app, without its network or its permission prompt: the
    /// gallery has to show the words users actually read.
    private func makeQuizModel() -> LessonQuizViewModel {
        LessonQuizViewModel(
            progressLoader: FakeProgressDataLoader(),
            requestNotificationPermission: {}
        )
    }

    /// The wrong answer of a question, the same way the quiz tests pick one.
    private func wrongOption(of question: TheoryQuestion) -> Int {
        (question.correct + 1) % max(question.options.count, 1)
    }

    /// Plays the lesson to its summary: `correct` right answers first, the rest
    /// wrong, which is the state S2 says still counts as a completed lesson.
    private func answerLesson(_ model: LessonQuizViewModel, correct: Int) async {
        for index in 0..<model.questionCount {
            guard let question = model.question else { return }
            let choice = index < correct ? question.correct : wrongOption(of: question)
            model.select(option: choice)
            await model.advance()
        }
    }
}

// MARK: - Path fixtures

/// `HabitUnitProgress` values the road can be drawn from, without a read. They
/// follow the order `HabitPathEngine` returns: the units that were played, then every
/// unit after them closed.
private enum PathRoadFixture {

    /// One open unit with `levels` reached and `drives` qualifying drives counted.
    static func unit(_ unit: HabitUnit, levels: Int, drives: Int) -> HabitUnitProgress {
        HabitUnitProgress(
            unit: unit,
            completedLevels: levels,
            qualifyingDrives: drives,
            isUnlocked: true
        )
    }

    /// A unit the path has not opened yet.
    static func locked(_ unit: HabitUnit) -> HabitUnitProgress {
        HabitUnitProgress(unit: unit, completedLevels: 0, qualifyingDrives: 0, isUnlocked: false)
    }

    /// The Camino at one moment: the reached levels of the leading units, every unit
    /// after them closed. `path([0])` is a brand-new user, `path([3, 1])` one who
    /// finished the first unit and is inside the second.
    static func path(_ levels: [Int]) -> [HabitUnitProgress] {
        HabitUnit.allCases.enumerated().map { index, habit in
            guard index < levels.count else { return locked(habit) }
            let level = min(max(levels[index], 0), HabitPathEngine.levelRequirements.count)

            return unit(habit, levels: level, drives: drives(forLevel: level))
        }
    }

    /// Qualifying drives that reach exactly `level` levels of
    /// `HabitPathEngine.levelRequirements`, so the road's caption reads true.
    private static func drives(forLevel level: Int) -> Int {
        switch level {
        case 0: return 0
        case 1: return 4
        case 2: return 9
        default: return 15
        }
    }
}
