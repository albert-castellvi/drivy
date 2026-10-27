import Foundation

/// Picks the three quests of the day (S6).
///
/// Deterministic on purpose: the board is a function of the user id and the day
/// key only, so the same day shows the same quests on every launch, on every
/// device and after a reinstall, and no state has to be stored to know what the
/// board was. The alternative, `Swift.Hasher`/`hashValue`, is seeded per process
/// and would rotate the board on every launch.
///
/// The board always contains at least one quest that needs no driving, which is
/// what lets a day without a car still be completed (S6, and S7's reminder that
/// only ever invites to the lesson).
enum DailyQuestBoard {

    /// Quests per day (S6).
    static let dailyCount = 3

    /// The quests of `dayKey` for `userID`, in display order.
    ///
    /// `catalog` is injectable so a test can pin a small board; the app always
    /// uses `QuestCatalog.all`.
    static func quests(
        for userID: String,
        dayKey: String,
        catalog: [DailyQuest] = QuestCatalog.all
    ) -> [DailyQuest] {
        let seed = stableHash("\(userID)|\(dayKey)")
        let withoutDriving = catalog.filter { !$0.requirement.needsDriving }.sorted { $0.id < $1.id }
        let withDriving = catalog.filter { $0.requirement.needsDriving }.sorted { $0.id < $1.id }

        guard catalog.count > dailyCount else {
            return ordered(catalog, seed: seed)
        }

        var chosen: [DailyQuest] = []

        // S6: always one quest that needs no driving. There is one in the catalog
        // today; taking it by index keeps the rule true if more are added.
        if !withoutDriving.isEmpty {
            let index = Int(seed % UInt64(withoutDriving.count))
            chosen.append(withoutDriving[index])
        }

        // The remaining slots rotate: the pool is ordered by a hash that depends on
        // the user and the day, so two days rarely repeat the same board.
        let pool = withDriving.sorted {
            let left = stableHash("\(userID)|\(dayKey)|\($0.id)")
            let right = stableHash("\(userID)|\(dayKey)|\($1.id)")
            return left == right ? $0.id < $1.id : left < right
        }

        for quest in pool where chosen.count < dailyCount {
            chosen.append(quest)
        }

        // Only reachable with a catalogue of mostly no-driving quests, but the
        // board is always full.
        for quest in withoutDriving where chosen.count < dailyCount {
            guard !chosen.contains(where: { $0.id == quest.id }) else { continue }
            chosen.append(quest)
        }

        return ordered(chosen, seed: seed)
    }

    /// FNV-1a over the UTF-8 bytes: small, dependency free and, unlike
    /// `hashValue`, identical in every process and every run.
    static func stableHash(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash
    }

    /// Display order of the chosen quests, also hashed so it is stable but not
    /// alphabetical (which would always put the lesson first or last).
    private static func ordered(_ quests: [DailyQuest], seed: UInt64) -> [DailyQuest] {
        quests
            .map { (quest: $0, order: stableHash("\(seed)|\($0.id)")) }
            .sorted { left, right in
                left.order == right.order ? left.quest.id < right.quest.id : left.order < right.order
            }
            .map { $0.quest }
    }
}
