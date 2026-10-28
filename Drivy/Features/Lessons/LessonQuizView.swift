import SwiftUI

/// La lección de teoría de hoy (S2): five multiple-choice questions, one per
/// screen, immediate feedback with the explanation of the bank and a summary that
/// closes the screen.
///
/// It is the part of the loop that needs no car: S1 makes a completed lesson count
/// as the day's driving, and S2 counts the lesson even when questions are failed.
/// Nothing here invites the user to drive, and there is no way to answer twice.
///
/// The view has no `NavigationStack` of its own on purpose: Hoy presents it in a
/// sheet and the Camino tab can push it, and both cases must lay out the same.
///
/// S5/S9 (T4): the question is the headline of the screen, the options are plates
/// on the paper, the progress is a line of lane marks and the pinned action is the
/// direction sign. The answer is felt as well as seen (S9): success on a right one,
/// error on a wrong one.
struct LessonQuizView: View {

    /// Called when the user leaves the finished summary, with the answers already
    /// recorded in the shared progress layer. The caller dismisses there, which is
    /// why the summary waits for this callback instead of calling it on the last
    /// answer.
    let onFinished: (_ correct: Int, _ total: Int) -> Void

    @StateObject private var model: LessonQuizViewModel

    /// The summary reports once, even if the user taps and then swipes.
    @State private var didFinish = false

    /// - Parameter onFinished: report of the finished lesson, `correct` answers out
    ///   of `total` questions.
    init(onFinished: @escaping (_ correct: Int, _ total: Int) -> Void) {
        self.init(model: LessonQuizViewModel(), onFinished: onFinished)
    }

    /// The same screen over a quiz already in progress.
    ///
    /// The gallery (S8) needs an answered question and a finished lesson without a
    /// network, and a screen whose state comes from a view model can only be shown
    /// in those states by handing it that view model. Production call sites use
    /// `init(onFinished:)`.
    init(model: LessonQuizViewModel, onFinished: @escaping (_ correct: Int, _ total: Int) -> Void) {
        self.onFinished = onFinished
        _model = StateObject(wrappedValue: model)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    content
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .background(Color.drivyPaper)
            // S9: the answer is the only thing on this screen worth feeling, and it
            // is felt once per answer — the counts move when an answer lands and
            // never when the quiz merely moves to the next question.
            .sensoryFeedback(.success, trigger: model.correctCount)
            .sensoryFeedback(.error, trigger: wrongAnswerCount)

            // The quiz keeps its action pinned at the bottom; the summary carries
            // its own button, because it is the end of the flow.
            if model.result == nil && model.question != nil {
                actionBar
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if let result = model.result {
            summarySection(result)
        } else if let question = model.question {
            headerSection
            questionSection(question)
            optionsSection(question)

            if let feedback = model.feedback {
                feedbackSection(feedback)
            }
        } else {
            // Only reachable with a broken bundle: the quiz says so instead of
            // showing five empty questions.
            PlaceholderCard(
                systemImage: "text.book.closed",
                title: "Lección no disponible",
                message: "No hemos podido cargar las preguntas de hoy. Vuelve a intentarlo más tarde."
            )
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Lección de teoría")
                    .font(.drivyHeadline)
                    .foregroundStyle(Color.drivyInk)

                Spacer(minLength: 8)

                Text(model.progressText)
                    .font(.drivyKicker)
                    .foregroundStyle(Color.drivyInkMuted)
                    .monospacedDigit()
            }

            QuizLaneMarks(
                marks: model.questionCount,
                filled: model.currentIndex
            )
            // The same accessibility element the linear `ProgressView` was: the bar
            // is a drawing of its value, not a new thing to describe (S6).
            .accessibilityRepresentation {
                ProgressView(
                    value: Double(model.currentIndex),
                    total: Double(max(model.questionCount, 1))
                )
            }
        }
    }

    private func questionSection(_ question: TheoryQuestion) -> some View {
        Text(question.text)
            .font(.drivyTitle)
            .foregroundStyle(Color.drivyInk)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func optionsSection(_ question: TheoryQuestion) -> some View {
        VStack(spacing: 10) {
            ForEach(question.options.indices, id: \.self) { index in
                optionRow(index: index, text: question.options[index], question: question)
            }
        }
    }

    /// One answer as a plate: raised paper, a hairline rule, and the border of its
    /// state. The mark and the words of the feedback say what the colour says, so
    /// colour is never the only signal (S6).
    private func optionRow(index: Int, text: String, question: TheoryQuestion) -> some View {
        let state = optionState(index: index, question: question)

        return Button {
            model.select(option: index)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: state.symbolName)
                    .imageScale(.large)
                    .foregroundStyle(state.color)
                    // The plate says in words what the mark draws; reading the mark
                    // first would only get in the way.
                    .accessibilityHidden(true)

                Text(text)
                    .font(.drivyBody)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(Color.drivyInk)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.drivyPaperRaised)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(state.borderColor, lineWidth: state.borderWidth)
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(model.isAnswered)
        // The mark is decoration; the state is said in words, so a wrong answer is
        // not something the border and the checkmark carry alone (S6).
        .accessibilityValue(state.accessibilityValue)
    }

    /// S2: the correction is immediate, right under the options: whether the answer
    /// was right, which one was right when it was not, and why.
    ///
    /// A rule and proximity separate it from the plates instead of a second card:
    /// the plates and the answer are one exchange, not two boxes.
    private func feedbackSection(_ feedback: LessonFeedback) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            QuizRule()

            Label(
                feedback.title,
                systemImage: feedback.isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill"
            )
            .font(.drivyHeadline)
            .foregroundStyle(feedback.isCorrect ? Color.drivyGo : Color.drivyAlertText)

            if !feedback.isCorrect {
                Text(feedback.correctionText)
                    .font(.drivyBodyStrong)
                    .foregroundStyle(Color.drivyInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(feedback.explanation)
                .font(.drivyBody)
                .foregroundStyle(Color.drivyInkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Summary

    private func summarySection(_ result: LessonResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(result.headline, systemImage: "checkmark.seal.fill")
                .font(.drivyHeadline)
                .foregroundStyle(Color.drivyGo)

            Text(result.scoreText)
                .font(.drivyTitle)
                .monospacedDigit()
                .foregroundStyle(Color.drivyInk)
                .fixedSize(horizontal: false, vertical: true)

            Text(result.streakText)
                .font(.drivyBody)
                .foregroundStyle(Color.drivyInk)
                .fixedSize(horizontal: false, vertical: true)

            Text(result.adviceText)
                .font(.drivyBody)
                .foregroundStyle(Color.drivyInkMuted)
                .fixedSize(horizontal: false, vertical: true)

            if let errorMessage = model.errorMessage {
                // The lesson is over even when the write failed: the summary stays
                // and the retry writes it again, which the shared layer treats as a
                // no-op if it had actually arrived.
                Text(errorMessage)
                    .font(.drivyFootnote)
                    .foregroundStyle(Color.drivyAlertText)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Reintentar") {
                    Task { await model.retryRecording() }
                }
                .buttonStyle(.bordered)
                .disabled(model.isRecording)
            }

            Button(action: close) {
                Text("Terminar")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.directionSign)
            .disabled(model.isRecording)
        }
    }

    // MARK: - Actions

    private var actionBar: some View {
        VStack(spacing: 8) {
            Button(action: advance) {
                Text(model.actionTitle)
                    .frame(maxWidth: .infinity)
            }
            .modifier(QuizActionChrome())
            .disabled(!model.isAnswered || model.isRecording)
            .opacity(model.isAnswered && !model.isRecording ? 1 : 0.5)
        }
        .padding()
        // Fixed chrome keeps its own ground: the paper of the screen and a hairline
        // where the road of the questions ends.
        .background(alignment: .top) {
            Color.drivyPaper
                .overlay(alignment: .top) {
                    QuizRule()
                        .frame(maxWidth: .infinity)
                }
        }
    }

    private func advance() {
        Task { await model.advance() }
    }

    /// Reports the finished lesson once. A swipe-down of the sheet also ends the
    /// screen without going through here, and the write has already happened by
    /// then, so nothing is lost.
    private func close() {
        guard let result = model.result, !didFinish else { return }
        didFinish = true
        onFinished(result.correct, result.total)
    }

    // MARK: - Option presentation

    /// How far the wrong answers have reached. The view model counts the right ones;
    /// the wrong ones are what is left of the answers given, which is what the error
    /// haptic of S9 needs as a trigger that moves only when one lands.
    private var wrongAnswerCount: Int {
        let answered = model.currentIndex + (model.isAnswered ? 1 : 0)
        return answered - model.correctCount
    }

    /// The look of one option: the bank's answer, the answer that missed it, the one
    /// picked while it is still open, or a plate at rest.
    private struct OptionState {

        let symbolName: String

        /// The colour of the mark, and of the border when the border says more than
        /// the hairline of a resting plate.
        let color: Color

        let borderColor: Color

        let borderWidth: CGFloat

        /// What VoiceOver adds to the words of the plate. Empty while the question is
        /// still open: there is nothing to say about an answer not given.
        let accessibilityValue: String
    }

    private func optionState(index: Int, question: TheoryQuestion) -> OptionState {
        if model.isAnswered, index == question.correct {
            return OptionState(
                symbolName: "checkmark.circle.fill",
                color: Color.drivyGo,
                borderColor: Color.drivyGo,
                borderWidth: 2,
                accessibilityValue: "respuesta correcta"
            )
        }
        if model.isAnswered, index == model.selectedOption {
            return OptionState(
                symbolName: "xmark.circle.fill",
                color: Color.drivyAlertText,
                borderColor: Color.drivyAlertText,
                borderWidth: 2,
                accessibilityValue: "tu respuesta, fallada"
            )
        }
        if index == model.selectedOption {
            // Reachable only if an answer ever stops being final: the pick before
            // the correction lands.
            return OptionState(
                symbolName: "circle",
                color: Color.drivyTint,
                borderColor: Color.drivyTint,
                borderWidth: 2,
                accessibilityValue: "elegida"
            )
        }

        return OptionState(
            symbolName: "circle",
            color: Color.drivyInkMuted,
            borderColor: Color.drivyRule,
            borderWidth: 1,
            accessibilityValue: ""
        )
    }
}

// MARK: - Pieces of the quiz

/// The progress of the lesson as lane marks: one dash per question, the ones behind
/// the user painted in ink, the ones ahead in rule.
///
/// It borrows the language of `RoadSurface` for a strip of five marks, which is what
/// a lesson is: the road itself paints a continuous band and is the wrong tool here
/// (T1 owns it, so the marks are drawn from its tokens instead).
private struct QuizLaneMarks: View {

    /// Height of a mark, the width of the road's centre line.
    private static let markHeight = RoadMetrics.centreLineWidth

    /// Gap between two marks.
    private static let markGap: CGFloat = 6

    /// Questions of the lesson.
    let marks: Int

    /// Questions already behind the user.
    let filled: Int

    var body: some View {
        HStack(spacing: Self.markGap) {
            ForEach(0..<max(marks, 1), id: \.self) { index in
                Rectangle()
                    .fill(index < filled ? Color.drivyInk : Color.drivyRule)
                    .frame(height: Self.markHeight)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: Self.markHeight)
    }
}

/// The hairline of the system: one `drivyRule` where a card used to be.
private struct QuizRule: View {

    var body: some View {
        Rectangle()
            .fill(Color.drivyRule)
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}

/// The chrome of the pinned action: the direction sign of the system, and on iOS 26
/// the Liquid Glass this screen already used (S6: glass only on fixed chrome).
private struct QuizActionChrome: ViewModifier {

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassProminentOrBorderedProminent()
                .controlSize(.large)
        } else {
            content
                .buttonStyle(.directionSign)
        }
    }
}

#Preview {
    LessonQuizView(onFinished: { _, _ in })
}
