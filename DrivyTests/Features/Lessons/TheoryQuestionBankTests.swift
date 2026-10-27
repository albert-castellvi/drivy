import XCTest
@testable import Drivy

/// The bundled question bank (S2: "Banco de preguntas en JSON dentro de la app
/// (supuesto: 60 preguntas de redacción original, no copiadas de exámenes DGT)").
///
/// The tests pin the shape the quiz depends on — sixty questions, three different
/// options, an answer that exists and one explanation — and the validation that
/// keeps a hand-edited JSON from pairing a question with the wrong answer.
final class TheoryQuestionBankTests: XCTestCase {

    /// The tests run hosted in the app on CI (`TEST_HOST`), so `Bundle.main` is the
    /// Drivy bundle and its copy of the JSON is the one that ships. The repository
    /// file is only the fallback when the tests run outside the host.
    private func repositoryURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Lessons
            .deletingLastPathComponent() // Features
            .deletingLastPathComponent() // DrivyTests
            .deletingLastPathComponent() // repository root
            .appendingPathComponent("Drivy/Features/Lessons/TheoryQuestions.json")
    }

    private func shippedQuestions() throws -> [TheoryQuestion] {
        if let url = Bundle.main.url(
            forResource: TheoryQuestionBank.resourceName,
            withExtension: "json"
        ) {
            return try JSONDecoder().decode([TheoryQuestion].self, from: Data(contentsOf: url))
        }

        let data = try Data(contentsOf: repositoryURL())
        return try JSONDecoder().decode([TheoryQuestion].self, from: data)
    }

    private func question(
        id: String = "q1",
        text: String = "¿Pregunta?",
        options: [String] = ["uno", "dos", "tres"],
        correct: Int = 0,
        explanation: String = "Explicación."
    ) -> TheoryQuestion {
        TheoryQuestion(
            id: id,
            text: text,
            options: options,
            correct: correct,
            explanation: explanation
        )
    }

    private func bank(_ count: Int) -> [TheoryQuestion] {
        (0..<count).map { question(id: "q\($0)") }
    }

    // MARK: - The shipped bank

    func testTheBankHasTheSixtyQuestionsTheSpecAsksFor() throws {
        XCTAssertEqual(try shippedQuestions().count, TheoryQuestionBank.minimumQuestionCount)
    }

    func testTheShippedBankPassesValidation() throws {
        XCTAssertNoThrow(try TheoryQuestionBank.validate(try shippedQuestions()))
    }

    func testEveryQuestionHasThreeDifferentOptions() throws {
        for question in try shippedQuestions() {
            XCTAssertEqual(
                question.options.count,
                TheoryQuestionBank.optionsPerQuestion,
                "\(question.id) does not have three options"
            )
            XCTAssertEqual(Set(question.options).count, question.options.count, "\(question.id) repeats options")
            XCTAssertFalse(question.options.contains { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        }
    }

    func testEveryQuestionPointsAtAnExistingAnswer() throws {
        for question in try shippedQuestions() {
            XCTAssertTrue(
                question.options.indices.contains(question.correct),
                "\(question.id) points past its options"
            )
            XCTAssertEqual(question.correctOption, question.options[question.correct])
        }
    }

    func testIdsAreUniqueAndNotEmpty() throws {
        let ids = try shippedQuestions().map(\.id)

        XCTAssertEqual(Set(ids).count, ids.count, "duplicate question id")
        XCTAssertFalse(ids.contains(where: \.isEmpty))
    }

    func testEveryQuestionHasTextAndOneLineExplanation() throws {
        for question in try shippedQuestions() {
            XCTAssertFalse(question.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            XCTAssertFalse(question.explanation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            XCTAssertFalse(question.explanation.contains("\n"), "\(question.id) has a multi-paragraph explanation")
        }
    }

    /// S2 promises a lesson of about a minute: a question with a paragraph of text
    /// is not one.
    func testNoQuestionStretchesTheOneMinuteLesson() throws {
        for question in try shippedQuestions() {
            XCTAssertLessThan(question.text.count, 220, "\(question.id) is too long for a one-minute lesson")
            XCTAssertLessThan(question.explanation.count, 200, "\(question.id) explains too much")
        }
    }

    func testTheLoaderReadsTheBundleCopy() throws {
        guard Bundle.main.url(forResource: TheoryQuestionBank.resourceName, withExtension: "json") != nil else {
            throw XCTSkip("the app bundle is not the test host")
        }

        let questions = try TheoryQuestionBank.load()

        XCTAssertEqual(questions.count, TheoryQuestionBank.minimumQuestionCount)
    }

    // MARK: - Validation

    func testAValidBankPasses() {
        XCTAssertNoThrow(try TheoryQuestionBank.validate(bank(TheoryQuestionBank.minimumQuestionCount)))
    }

    func testAQuestionWithARepeatedIdIsRejected() {
        var questions = bank(TheoryQuestionBank.minimumQuestionCount)
        questions[1] = question(id: questions[0].id)

        XCTAssertThrowsError(try TheoryQuestionBank.validate(questions))
    }

    func testAQuestionWithTwoOptionsIsRejected() {
        var questions = bank(TheoryQuestionBank.minimumQuestionCount)
        questions[0] = question(id: "q0", options: ["uno", "dos"], correct: 1)

        XCTAssertThrowsError(try TheoryQuestionBank.validate(questions))
    }

    func testAnAnswerIndexOutsideTheOptionsIsRejected() {
        var questions = bank(TheoryQuestionBank.minimumQuestionCount)
        questions[0] = question(id: "q0", correct: 9)

        XCTAssertThrowsError(try TheoryQuestionBank.validate(questions))
    }

    func testAQuestionWithoutExplanationIsRejected() {
        var questions = bank(TheoryQuestionBank.minimumQuestionCount)
        questions[0] = question(id: "q0", explanation: "   ")

        XCTAssertThrowsError(try TheoryQuestionBank.validate(questions))
    }

    func testABankThatIsTooSmallIsRejected() {
        var questions = bank(TheoryQuestionBank.minimumQuestionCount)
        questions.removeLast()

        XCTAssertThrowsError(try TheoryQuestionBank.validate(questions)) { error in
            guard case TheoryQuestionBank.BankError.invalidBank = error else {
                return XCTFail("unexpected error \(error)")
            }
        }
    }

    func testAMissingResourceIsReported() {
        // A bundle without the JSON: the DrivyTests bundle itself.
        let bundle = Bundle(for: TheoryQuestionBankTests.self)

        XCTAssertThrowsError(try TheoryQuestionBank.load(bundle: bundle)) { error in
            XCTAssertEqual(error as? TheoryQuestionBank.BankError, .missingResource)
        }
    }
}
