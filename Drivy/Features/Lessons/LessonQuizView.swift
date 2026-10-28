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
        self.onFinished = onFinished
        _model = StateObject(wrappedValue: LessonQuizViewModel())
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Lección de teoría")
                    .font(.headline)

                Spacer(minLength: 8)

                Text(model.progressText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            ProgressView(
                value: Double(model.currentIndex),
                total: Double(max(model.questionCount, 1))
            )
        }
    }

    private func questionSection(_ question: TheoryQuestion) -> some View {
        Text(question.text)
            .font(.title3.weight(.semibold))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func optionsSection(_ question: TheoryQuestion) -> some View {
        VStack(spacing: 10) {
            ForEach(question.options.indices, id: \.self) { index in
                optionRow(index: index, text: question.options[index], question: question)
            }
        }
    }

    private func optionRow(index: Int, text: String, question: TheoryQuestion) -> some View {
        Button {
            model.select(option: index)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: optionSymbol(index: index, question: question))
                    .foregroundStyle(optionTint(index: index, question: question))

                Text(text)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.quaternary)
            )
        }
        .buttonStyle(.plain)
        .disabled(model.isAnswered)
    }

    /// S2: the correction is immediate, right under the options: whether the answer
    /// was right, which one was right when it was not, and why.
    private func feedbackSection(_ feedback: LessonFeedback) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(
                feedback.title,
                systemImage: feedback.isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill"
            )
            .font(.headline)
            .foregroundStyle(feedback.isCorrect ? Color.green : Color.red)

            if !feedback.isCorrect {
                Text(feedback.correctionText)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(feedback.explanation)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .drivyCard()
    }

    // MARK: - Summary

    private func summarySection(_ result: LessonResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(result.headline, systemImage: "checkmark.seal.fill")
                .font(.headline)
                .foregroundStyle(Color.accentColor)

            Text(result.scoreText)
                .font(.title2.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)

            Text(result.streakText)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)

            Text(result.adviceText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let errorMessage = model.errorMessage {
                // The lesson is over even when the write failed: the summary stays
                // and the retry writes it again, which the shared layer treats as a
                // no-op if it had actually arrived.
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Reintentar") {
                    Task { await model.retryRecording() }
                }
                .buttonStyle(.bordered)
                .disabled(model.isRecording)
            }

            Button(action: close) {
                Text("Terminar")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(model.isRecording)
        }
        .drivyCard()
    }

    // MARK: - Actions

    private var actionBar: some View {
        VStack(spacing: 8) {
            Button(action: advance) {
                Text(model.actionTitle)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .glassProminentOrBorderedProminent()
            .controlSize(.large)
            .disabled(!model.isAnswered || model.isRecording)
        }
        .padding()
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

    private func optionSymbol(index: Int, question: TheoryQuestion) -> String {
        guard let selected = model.selectedOption else { return "circle" }
        if index == question.correct { return "checkmark.circle.fill" }
        if index == selected { return "xmark.circle.fill" }
        return "circle"
    }

    private func optionTint(index: Int, question: TheoryQuestion) -> Color {
        guard let selected = model.selectedOption else { return .secondary }
        if index == question.correct { return .green }
        if index == selected { return .red }
        return .secondary
    }
}

#Preview {
    LessonQuizView(onFinished: { _, _ in })
}
