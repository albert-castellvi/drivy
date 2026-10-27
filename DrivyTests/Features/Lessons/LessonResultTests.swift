import XCTest
@testable import Drivy

/// The outcome of a lesson (S2). S2 is explicit about the rule these tests pin:
/// "Completar el test = lección del día (S1), aunque falles preguntas". There is no
/// pass mark, so the copy never talks about aprobar or suspender, and it never
/// invites the user to drive.
final class LessonResultTests: XCTestCase {

    private func question(
        correct: Int = 1,
        explanation: String = "Hay que ceder el paso."
    ) -> TheoryQuestion {
        TheoryQuestion(
            id: "q1",
            text: "¿Quién tiene prioridad?",
            options: ["uno", "dos", "tres"],
            correct: correct,
            explanation: explanation
        )
    }

    // MARK: - The result

    func testAPerfectLessonIsMarkedAsPerfect() {
        let result = LessonResult(correct: 5, total: 5, dayKey: "2026-03-04")

        XCTAssertTrue(result.isPerfect)
        XCTAssertEqual(result.headline, "Lección completada")
        XCTAssertEqual(result.scoreText, "5 de 5 respuestas correctas")
        XCTAssertEqual(result.adviceText, "Sin fallos. Vuelve mañana para una lección nueva.")
    }

    /// S2: failing questions still counts the day.
    func testALessonWithFailuresStillCountsForTheDay() {
        let result = LessonResult(correct: 2, total: 5, dayKey: "2026-03-04")

        XCTAssertFalse(result.isPerfect)
        XCTAssertTrue(result.countsForTheDay)
        XCTAssertEqual(result.scoreText, "2 de 5 respuestas correctas")
        XCTAssertEqual(result.streakText, "La lección de hoy ya cuenta para tu racha.")
        XCTAssertEqual(
            result.adviceText,
            "Repasa la explicación de las que has fallado; mañana habrá una lección nueva."
        )
    }

    func testALessonWithNoCorrectAnswerStillCountsForTheDay() {
        let result = LessonResult(correct: 0, total: 5, dayKey: "2026-03-04")

        XCTAssertFalse(result.isPerfect)
        XCTAssertTrue(result.countsForTheDay)
        XCTAssertEqual(result.scoreText, "0 de 5 respuestas correctas")
    }

    func testAnEmptyLessonIsNotPerfect() {
        XCTAssertFalse(LessonResult(correct: 0, total: 0, dayKey: "2026-03-04").isPerfect)
    }

    /// The safety principle of the whole feature: nothing invites the user to drive
    /// more, and no closing line of a lesson can do it either.
    func testTheSummaryNeverInvitesToDrive() {
        let results = [
            LessonResult(correct: 5, total: 5, dayKey: "2026-03-04"),
            LessonResult(correct: 0, total: 5, dayKey: "2026-03-04")
        ]

        for result in results {
            let copy = [result.headline, result.scoreText, result.streakText, result.adviceText]
                .joined(separator: " ")
                .lowercased()

            for invitation in ["conduce", "conducir más", "km", "trayecto", "sal a la carretera"] {
                XCTAssertFalse(copy.contains(invitation), "the summary invites to drive: \(invitation)")
            }
        }
    }

    // MARK: - Feedback

    func testACorrectAnswerGetsTheExplanation() {
        let feedback = LessonFeedback(question: question(), selectedOption: 1)

        XCTAssertTrue(feedback.isCorrect)
        XCTAssertEqual(feedback.title, "Correcto")
        XCTAssertEqual(feedback.explanation, "Hay que ceder el paso.")
        XCTAssertEqual(feedback.correctAnswer, "dos")
    }

    func testAWrongAnswerNamesTheCorrectOption() {
        let feedback = LessonFeedback(question: question(), selectedOption: 0)

        XCTAssertFalse(feedback.isCorrect)
        XCTAssertEqual(feedback.title, "No es correcto")
        XCTAssertEqual(feedback.correctionText, "La respuesta correcta es: dos")
        XCTAssertEqual(feedback.explanation, "Hay que ceder el paso.")
    }
}
