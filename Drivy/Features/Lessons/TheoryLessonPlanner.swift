import Foundation

/// The five questions of one day's theory lesson (S2: "5 preguntas de opción
/// múltiple (~1 minuto)").
struct TheoryLesson: Equatable {

    /// `yyyy-MM-dd` of the day the lesson belongs to, the same key the streak (S1)
    /// and `public.lesson_completions.day` use.
    let dayKey: String

    /// The questions in display order, one per screen.
    let questions: [TheoryQuestion]

    var count: Int {
        questions.count
    }

    var isEmpty: Bool {
        questions.isEmpty
    }
}

/// Picks the questions of the day's lesson (S2).
///
/// Deterministic on purpose: the lesson is a function of the day key and the bank
/// alone, so the same day always serves the same five questions, on every launch
/// and after a reinstall, and nothing has to be stored to know what the lesson was.
/// `Swift.Hasher`/`hashValue` is seeded per process and would rotate the lesson on
/// every launch, hence the explicit FNV-1a below (the same one `DailyQuestBoard`
/// uses for the quests of the day).
///
/// Nothing here rewards driving and nothing invites the user to drive: a lesson is
/// answered wherever the user is, with or without a car (S1, S2, S7).
enum TheoryLessonPlanner {

    /// Questions per lesson (S2).
    static let questionCount = 5

    /// The lesson of `dayKey`.
    ///
    /// - Parameters:
    ///   - dayKey: `yyyy-MM-dd` of the day.
    ///   - questions: the bank; the app passes `TheoryQuestionBank.bundled`.
    ///   - previousDayKey: key of the day before, when known. Yesterday's set is
    ///     never served twice in a row while the bank has an unused question for
    ///     the day, so a user who does the lesson every day still sees new material.
    static func lesson(
        dayKey: String,
        questions: [TheoryQuestion],
        previousDayKey: String? = nil
    ) -> TheoryLesson {
        let ordered = orderedQuestions(dayKey: dayKey, questions: questions)
        guard !ordered.isEmpty else {
            return TheoryLesson(dayKey: dayKey, questions: [])
        }

        var chosen = Array(ordered.prefix(questionCount))

        if let previousDayKey, previousDayKey != dayKey, ordered.count > chosen.count {
            let previousIDs = Set(
                orderedQuestions(dayKey: previousDayKey, questions: questions)
                    .prefix(questionCount)
                    .map(\.id)
            )
            if Set(chosen.map(\.id)) == previousIDs {
                // One slot moves to the next question of the day's order: the
                // lesson stays a pure function of the day and yesterday's set is
                // never repeated back to back. A bank of exactly five questions
                // has nothing to move to, and only then the lesson repeats
                // (`ordered.count > chosen.count` above).
                chosen[chosen.count - 1] = ordered[chosen.count]
            }
        }

        return TheoryLesson(dayKey: dayKey, questions: chosen)
    }

    /// The whole bank in the day's order: the caller's picking and the
    /// previous-day comparison share this one ordering, which is what makes the
    /// "never yesterday's set" rule exact.
    static func orderedQuestions(dayKey: String, questions: [TheoryQuestion]) -> [TheoryQuestion] {
        questions.sorted { left, right in
            let leftOrder = stableHash("\(dayKey)|\(left.id)")
            let rightOrder = stableHash("\(dayKey)|\(right.id)")
            return leftOrder == rightOrder ? left.id < right.id : leftOrder < rightOrder
        }
    }

    /// `yyyy-MM-dd` of the day before `dayKey`, in the injected calendar (Europe/
    /// Madrid by default, like the day the lesson is written for). `nil` when
    /// `dayKey` is not a day.
    static func previousDayKey(before dayKey: String, calendar: Calendar = .madrid) -> String? {
        guard
            let date = DayKey.date(from: dayKey, calendar: calendar),
            let previous = calendar.date(byAdding: .day, value: -1, to: date)
        else {
            return nil
        }
        return DriveDay.key(for: previous, calendar: calendar)
    }

    /// FNV-1a over the UTF-8 bytes: small, dependency free and, unlike `hashValue`,
    /// identical in every process and every run.
    static func stableHash(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash
    }
}
