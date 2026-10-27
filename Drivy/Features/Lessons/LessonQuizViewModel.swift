import Combine
import Foundation

/// State and the only write of the theory lesson of the day (S2).
///
/// The lesson is five questions, one per screen, with immediate feedback and a
/// summary at the end. Completing it records the day through the shared progress
/// layer (`ProgressDataLoading.recordLesson`), which is what makes a day without a
/// car count for the streak (S1). Failing questions never blocks that: S2 counts
/// the completed lesson, not the score.
///
/// Nothing in here rewards driving more, and no copy invites the user to drive: the
/// lesson is the one part of the loop that needs no car at all (S1, S2, S7).
@MainActor
final class LessonQuizViewModel: ObservableObject {

    /// Copy shown in the UI. Kept here so tests assert the exact string.
    static let recordFailureMessage = "No hemos podido guardar la lección de hoy. Inténtalo de nuevo."

    /// Titles of the primary button of the quiz.
    static let nextTitle = "Siguiente"
    static let finishTitle = "Terminar"

    /// Question on screen (0-based).
    @Published private(set) var currentIndex = 0

    /// Option the user picked for the question on screen; `nil` while it is open.
    @Published private(set) var selectedOption: Int?

    /// Answers that were right so far.
    @Published private(set) var correctCount = 0

    /// Set once the lesson is over. From then on the screen shows the summary and
    /// the quiz no longer accepts answers.
    @Published private(set) var result: LessonResult?

    /// True while the write of the lesson is in flight, so the button cannot fire
    /// twice.
    @Published private(set) var isRecording = false

    /// Error of the last write, kept next to the summary so the user can retry.
    @Published private(set) var errorMessage: String?

    /// The questions of the day, in display order.
    let lesson: TheoryLesson

    /// `yyyy-MM-dd` the lesson is recorded for (S1, S2).
    let dayKey: String

    private let progressLoader: ProgressDataLoading
    private let requestNotificationPermission: @MainActor () -> Void

    /// S7 asks for the notification permission once, after the first lesson. A
    /// retry of the same lesson must not ask again.
    private var didRequestPermission = false

    /// - Parameters:
    ///   - questions: the bank; the app passes `TheoryQuestionBank.bundled`, the
    ///     tests a handful of questions.
    ///   - calendar: day grouping, injected so tests pin Europe/Madrid.
    ///   - now: clock of the day key.
    ///   - progressLoader: the shared progress layer; the lesson is never written
    ///     anywhere else.
    ///   - requestNotificationPermission: `nil` in the app, which asks for the real
    ///     permission (S7); tests inject a counter.
    init(
        questions: [TheoryQuestion] = TheoryQuestionBank.bundled,
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init,
        progressLoader: ProgressDataLoading = SupabaseProgressRepository(),
        requestNotificationPermission: (@MainActor () -> Void)? = nil
    ) {
        let dayKey = DriveDay.key(for: now(), calendar: calendar)
        self.dayKey = dayKey
        self.lesson = TheoryLessonPlanner.lesson(
            dayKey: dayKey,
            questions: questions,
            previousDayKey: TheoryLessonPlanner.previousDayKey(before: dayKey, calendar: calendar)
        )
        self.progressLoader = progressLoader
        self.requestNotificationPermission = requestNotificationPermission ?? {
            NotificationPermission.requestAfterFirstLesson()
        }
    }

    // MARK: - State of the quiz

    var questionCount: Int {
        lesson.count
    }

    /// Question on screen; `nil` only when the bundled bank could not be read.
    var question: TheoryQuestion? {
        lesson.questions.indices.contains(currentIndex) ? lesson.questions[currentIndex] : nil
    }

    /// Feedback of the question on screen (S2), `nil` while it is still open.
    var feedback: LessonFeedback? {
        guard let question, let selectedOption else { return nil }
        return LessonFeedback(question: question, selectedOption: selectedOption)
    }

    var isAnswered: Bool {
        selectedOption != nil
    }

    var isLastQuestion: Bool {
        currentIndex + 1 >= questionCount
    }

    /// "Pregunta 2 de 5".
    var progressText: String {
        "Pregunta \(currentIndex + 1) de \(questionCount)"
    }

    /// Title of the primary button: the last question finishes the lesson.
    var actionTitle: String {
        isLastQuestion ? Self.finishTitle : Self.nextTitle
    }

    // MARK: - Actions

    /// Answers the open question. The first answer is the one that counts: tapping
    /// another option afterwards cannot turn a fail into a pass.
    func select(option index: Int) {
        guard result == nil, selectedOption == nil, let question,
              question.options.indices.contains(index) else {
            return
        }

        selectedOption = index
        if question.isCorrect(index) {
            correctCount += 1
        }
    }

    /// Moves to the next question, or finishes the lesson after the last one.
    func advance() async {
        guard result == nil, selectedOption != nil else { return }

        guard !isLastQuestion else {
            await finish()
            return
        }

        currentIndex += 1
        selectedOption = nil
    }

    /// S2: the completed lesson is written with what the user answered, and only
    /// then the day counts for the streak (S1). A write that fails does not cancel
    /// the lesson: the summary appears with `errorMessage` and `retryRecording()`
    /// can try again, because recording the same lesson twice is a no-op in the
    /// shared layer.
    func finish() async {
        // An empty lesson has nothing to record (and the table refuses totals of
        // zero), which only happens with a broken bundle.
        guard result == nil, !isRecording, questionCount > 0 else { return }

        let finished = LessonResult(correct: correctCount, total: questionCount, dayKey: dayKey)
        isRecording = true

        do {
            try await progressLoader.recordLesson(day: dayKey, correct: finished.correct, total: finished.total)
            errorMessage = nil
            requestPermissionOnce()
        } catch {
            errorMessage = Self.recordFailureMessage
        }

        result = finished
        isRecording = false
    }

    /// Retries the write of a finished lesson whose first attempt failed.
    func retryRecording() async {
        guard let result, !isRecording else { return }

        isRecording = true
        do {
            try await progressLoader.recordLesson(day: result.dayKey, correct: result.correct, total: result.total)
            errorMessage = nil
            requestPermissionOnce()
        } catch {
            errorMessage = Self.recordFailureMessage
        }
        isRecording = false
    }

    /// S7: the permission is asked once, after the lesson is actually recorded.
    private func requestPermissionOnce() {
        guard !didRequestPermission else { return }
        didRequestPermission = true
        requestNotificationPermission()
    }
}
