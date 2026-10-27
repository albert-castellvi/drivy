import Foundation

/// One multiple-choice question of the theory lesson (S2: "5 preguntas de opción
/// múltiple").
///
/// The wording is original and in Spanish, and every fact is a general safe rule
/// of the Spanish traffic code rather than an edge case: the bank ships inside the
/// app and the user reviews it before release (S2). A sign that would need a
/// picture is described in words, because the bank has no images.
struct TheoryQuestion: Decodable, Equatable, Identifiable {

    /// Stable key. A question is removed or reworded, never re-identified, so a
    /// test can pin one question across releases.
    let id: String

    /// The question, in Spanish.
    let text: String

    /// The three options, in display order (`TheoryQuestionBank.optionsPerQuestion`).
    let options: [String]

    /// Index into `options` of the correct answer.
    let correct: Int

    /// One sentence shown right after answering (S2: immediate feedback).
    let explanation: String

    /// Text of the correct option, or `nil` when the bank is malformed. Only a
    /// hand-edited bank can be malformed, and `TheoryQuestionBank.validate`
    /// rejects it before it reaches the screen.
    var correctOption: String? {
        options.indices.contains(correct) ? options[correct] : nil
    }

    /// True when `optionIndex` is the answer the bank marks as correct.
    func isCorrect(_ optionIndex: Int) -> Bool {
        optionIndex == correct
    }
}

/// The bundled question bank (S2: "Banco de preguntas en JSON dentro de la app
/// (supuesto: 60 preguntas de redacción original)").
///
/// The file is `Drivy/Features/Lessons/TheoryQuestions.json`, which XcodeGen
/// copies into the app bundle as a resource, so the bank is read without a
/// network and works offline.
enum TheoryQuestionBank {

    /// Resource name of the JSON file, without its extension.
    static let resourceName = "TheoryQuestions"

    /// S2 asks for sixty questions: enough for a year of five-question lessons
    /// without the bank forcing repeats.
    static let minimumQuestionCount = 60

    /// Options of every question (S2: multiple choice; three keeps a lesson inside
    /// the one minute the spec promises).
    static let optionsPerQuestion = 3

    enum BankError: Error, Equatable {
        /// The JSON is not in the bundle: a build or resource problem, never a user
        /// problem.
        case missingResource

        /// The JSON decodes but breaks the shape of the bank.
        case invalidBank(reason: String)
    }

    /// The bank of the running app, decoded once. Empty when the resource is
    /// missing or malformed: the quiz then shows "lección no disponible" instead of
    /// crashing, which is the honest behaviour for a build problem.
    static let bundled: [TheoryQuestion] = (try? load()) ?? []

    /// Reads and validates the bank.
    ///
    /// - Parameter bundle: injectable so a test can point at the app bundle, which
    ///   is where the resource lives when the tests run hosted on CI.
    static func load(bundle: Bundle = .main) throws -> [TheoryQuestion] {
        guard let url = bundle.url(forResource: resourceName, withExtension: "json") else {
            throw BankError.missingResource
        }

        let data = try Data(contentsOf: url)
        let questions = try JSONDecoder().decode([TheoryQuestion].self, from: data)
        try validate(questions)
        return questions
    }

    /// Rejects a bank the quiz cannot trust: fewer questions than S2 asks for,
    /// repeated ids, missing text or explanation, or an option count and correct
    /// index that do not line up. A hand-edited JSON is the only way in, and this
    /// is what keeps the screen from pairing a question with the wrong answer.
    static func validate(_ questions: [TheoryQuestion]) throws {
        guard questions.count >= minimumQuestionCount else {
            throw BankError.invalidBank(
                reason: "the bank has \(questions.count) questions, \(minimumQuestionCount) expected"
            )
        }

        var seen: Set<String> = []
        for question in questions {
            guard !question.id.isEmpty else {
                throw BankError.invalidBank(reason: "a question has no id")
            }
            guard seen.insert(question.id).inserted else {
                throw BankError.invalidBank(reason: "duplicate id \(question.id)")
            }
            guard !question.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw BankError.invalidBank(reason: "\(question.id) has no text")
            }
            guard question.options.count == optionsPerQuestion else {
                throw BankError.invalidBank(
                    reason: "\(question.id) has \(question.options.count) options, \(optionsPerQuestion) expected"
                )
            }
            guard Set(question.options).count == question.options.count else {
                throw BankError.invalidBank(reason: "\(question.id) repeats an option")
            }
            guard question.options.indices.contains(question.correct) else {
                throw BankError.invalidBank(reason: "\(question.id) points past its options")
            }
            guard !question.explanation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw BankError.invalidBank(reason: "\(question.id) has no explanation")
            }
        }
    }
}
