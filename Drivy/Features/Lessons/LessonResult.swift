import Foundation

/// Immediate feedback of one answered question (S2: "feedback inmediato con la
/// explicación").
///
/// Pure value type: it only chooses which of the bank's strings the screen shows,
/// so the copy is asserted in tests and the view lays it out.
struct LessonFeedback: Equatable {

    /// True when the option the user picked is the bank's answer.
    let isCorrect: Bool

    /// The one-sentence explanation of the bank.
    let explanation: String

    /// Text of the right option, used to correct a wrong answer.
    let correctAnswer: String

    /// Spanish: the app has no localization, like the rest of the copy.
    var title: String {
        isCorrect ? "Correcto" : "No es correcto"
    }

    /// Sentence naming the right option. Only shown for a wrong answer: repeating
    /// it after a correct one would say nothing new.
    var correctionText: String {
        "La respuesta correcta es: \(correctAnswer)"
    }

    init(question: TheoryQuestion, selectedOption: Int) {
        self.isCorrect = question.isCorrect(selectedOption)
        self.explanation = question.explanation
        self.correctAnswer = question.correctOption ?? ""
    }
}

/// Outcome of a finished theory lesson (S2).
///
/// S2 makes completing the lesson the thing that counts, not passing it: "Completar
/// el test = lección del día (S1), aunque falles preguntas". That is why the type
/// carries no pass mark and why `countsForTheDay` is always true.
struct LessonResult: Equatable {

    /// Answers that were right.
    let correct: Int

    /// Questions of the lesson (`TheoryLessonPlanner.questionCount` for a full
    /// bank).
    let total: Int

    /// `yyyy-MM-dd` of the day the lesson is recorded for, so the summary can be
    /// shown after the write failed and the retry still knows its day.
    let dayKey: String

    /// True when nothing was failed. Only the copy depends on it.
    var isPerfect: Bool {
        total > 0 && correct == total
    }

    /// S2/S1: a lesson only ever adds a day to the streak; failing questions does
    /// not take the day away.
    var countsForTheDay: Bool {
        true
    }

    var headline: String {
        "Lección completada"
    }

    /// The score as one line, e.g. "3 de 5 respuestas correctas".
    var scoreText: String {
        "\(correct) de \(total) respuestas correctas"
    }

    /// What the lesson just did for the streak (S1).
    var streakText: String {
        "La lección de hoy ya cuenta para tu racha."
    }

    /// One closing line. It never invites the user to drive: the loop rewards
    /// driving better and lets a day without a car count (S1, S2, S7).
    var adviceText: String {
        if isPerfect {
            return "Sin fallos. Vuelve mañana para una lección nueva."
        }
        return "Repasa la explicación de las que has fallado; mañana habrá una lección nueva."
    }
}
