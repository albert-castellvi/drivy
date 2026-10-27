import Foundation

/// One level of the habit path that is reached but not stored yet (S3).
///
/// The owner of the write path (`HabitPathViewModel`) records these through
/// `ProgressDataLoading.recordHabitLevel`, which is idempotent, so a refresh that
/// finds the same level again is harmless.
struct PendingHabitLevel: Equatable, Identifiable {

    let unit: HabitUnit

    /// 1…3.
    let level: Int

    var id: String { "\(unit.id)-\(level)" }
}

/// State of one unit of the path (S3), ready to be drawn.
struct HabitUnitProgress: Equatable, Identifiable {

    let unit: HabitUnit

    /// Levels reached, the already recorded ones counted in (0…3).
    let completedLevels: Int

    /// Drives that satisfy the unit since it opened, capped at the last level
    /// requirement so the copy never reads "37 de 15".
    let qualifyingDrives: Int

    /// `false` while the previous unit has not recorded its third level.
    let isUnlocked: Bool

    var id: String { unit.id }
}

/// The habit path (S3) as one value: what the Camino tab draws and what the view
/// model still has to record.
struct HabitPathSnapshot: Equatable {

    /// Every unit, in path order, locked ones included.
    let units: [HabitUnitProgress]

    /// Levels the engine found reached that still have to be stored. Each one pays
    /// its XP on the server (S4).
    let pendingLevels: [PendingHabitLevel]

    /// True when today's theory lesson is already done (S2); the entry card of the
    /// tab states it.
    let hasLessonToday: Bool

    static let empty = HabitPathSnapshot(units: [], pendingLevels: [], hasLessonToday: false)
}

/// The S3 rule, as a pure and deterministic function of the drives and the stored
/// levels.
///
/// S3, verbatim: "Cada unidad se supera con retos medidos con las métricas que ya
/// calcula el scoring, por ejemplo '5 trayectos sin frenadas bruscas'". The approved
/// reading, decided here:
///
/// - the five units play in order, each one opening when the previous one records
///   its third level, and the first one open from the start;
/// - a level needs 3, 7 or 15 qualifying drives counted **since the unit opened**,
///   so the count is cumulative: every level is a wider sample of the same habit;
/// - a drive qualifies when it is at least 2 km long and satisfied the rule of the
///   unit (`HabitUnit.isQualified`); a shorter drive is simply not judged;
/// - nothing is granted here. The engine reports the levels it found reached and
///   whoever owns the write path stores them, because the server is the only source
///   of XP (S4) and of the `completedAt` that opens the next unit.
///
/// No unit rewards driving more: every rule is about how a drive went, and a unit
/// is completed by drives that already happened.
enum HabitPathEngine {

    /// S3: a drive counts for any unit only from 2 km. The same floor the quests
    /// use (`QuestCatalog.minimumDistanceKm`), so the two surfaces never disagree
    /// about which drives count.
    static let qualifyingDistanceKm = 2.0

    /// S3: drives needed at each level, counted since the unit opened.
    static let levelRequirements = [3, 7, 15]

    /// S4: what one level pays, decided by the server (`xp_ledger` in
    /// `0002_duolingo_loop.sql`). Shown here, never granted here.
    static let xpPerLevel = 50

    /// Floor of the `drives(since:)` read. Unit 1 counts every drive (S3) and the
    /// app did not exist before 1970, so this is "all drives" without an unbounded
    /// query and without a lookback window that could hide older drives.
    static let allDrivesSince = Date(timeIntervalSince1970: 0)

    /// Path of the user as of `now`.
    ///
    /// - Parameters:
    ///   - drives: the drives read through `ProgressDataLoading.drives(since:)`,
    ///     oldest first (the order the shared layer returns).
    ///   - levels: `public.habit_levels` of the user, any order.
    ///   - hasLessonToday: whether today's lesson is recorded (S2).
    ///   - now: reference date; a drive that starts later than this does not count,
    ///     which keeps an upload from the future out of the path.
    static func path(
        drives: [DriveHistoryRow],
        levels: [HabitLevelRecord],
        hasLessonToday: Bool = false,
        now: Date
    ) -> HabitPathSnapshot {
        let lastRequirement = levelRequirements.last ?? 0
        let lastLevel = levelRequirements.count

        var units: [HabitUnitProgress] = []
        var pendingLevels: [PendingHabitLevel] = []

        // Opening date of the unit being computed: the start of time for the first
        // unit, the recorded `completedAt` of the previous unit's third level after
        // that (S3). `nil` means "never", which locks this unit and every unit after
        // it.
        var openedAt: Date? = allDrivesSince

        for unit in HabitUnit.allCases {
            let storedLevels = levels.filter { $0.unit == unit.id }
            let recordedLevel = storedLevels
                .map(\.level)
                .filter { $0 >= 1 && $0 <= lastLevel }
                .max() ?? 0

            guard let opened = openedAt else {
                units.append(
                    HabitUnitProgress(
                        unit: unit,
                        completedLevels: 0,
                        qualifyingDrives: 0,
                        isUnlocked: false
                    )
                )
                continue
            }

            let qualifying = drives.filter { drive in
                drive.startedAt >= opened
                    && drive.startedAt <= now
                    && drive.distanceKm >= qualifyingDistanceKm
                    && unit.isQualified(drive)
            }
            let count = min(qualifying.count, lastRequirement)

            // Cumulative thresholds: 3 drives reach level 1, 7 reach level 2, 15
            // reach level 3.
            let reached = levelRequirements.filter { count >= $0 }.count
            // A stored level is a reached level even if the drives of that period
            // are no longer readable, so the path never goes backwards.
            let effectiveLevel = max(reached, recordedLevel)

            if reached > recordedLevel {
                for level in (recordedLevel + 1)...reached {
                    pendingLevels.append(PendingHabitLevel(unit: unit, level: level))
                }
            }

            units.append(
                HabitUnitProgress(
                    unit: unit,
                    completedLevels: effectiveLevel,
                    qualifyingDrives: count,
                    isUnlocked: true
                )
            )

            // The next unit opens at the third level's `completedAt` and at nothing
            // else: while that write is in flight the next unit waits one refresh,
            // and an unrecorded level can never unlock it.
            openedAt = storedLevels.first { $0.level == lastLevel }?.completedAt
        }

        return HabitPathSnapshot(
            units: units,
            pendingLevels: pendingLevels,
            hasLessonToday: hasLessonToday
        )
    }
}

// MARK: - Copy of the path

extension HabitUnitProgress {

    /// S3: the three levels of the unit are behind.
    var isCompleted: Bool {
        completedLevels >= HabitPathEngine.levelRequirements.count
    }

    /// Level being played (1…3); `nil` while the unit is locked or complete.
    var nextLevel: Int? {
        guard isUnlocked, !isCompleted else { return nil }
        return completedLevels + 1
    }

    /// Drives the next level needs; `nil` while the unit is locked or complete.
    var nextLevelRequirement: Int? {
        guard let level = nextLevel else { return nil }
        return HabitPathEngine.levelRequirements[level - 1]
    }

    /// What the progress bar of the unit fills (0…1).
    var progressFraction: Double {
        guard let requirement = nextLevelRequirement, requirement > 0 else {
            return isCompleted ? 1 : 0
        }
        return min(1, Double(qualifyingDrives) / Double(requirement))
    }

    /// Headline of the unit: where it stands, in one line.
    var statusText: String {
        if !isUnlocked {
            guard let previous = unit.previous else { return "Bloqueado" }
            return "Se abre al terminar «\(previous.title)»"
        }
        if isCompleted {
            return "Completado"
        }
        return "Nivel \(completedLevels + 1) de \(HabitPathEngine.levelRequirements.count)"
    }

    /// Drives counted towards the next level, e.g. "7 de 15 trayectos"; `nil` when
    /// there is nothing left to count.
    var progressText: String? {
        guard let requirement = nextLevelRequirement else { return nil }
        return "\(qualifyingDrives) de \(requirement) trayectos"
    }
}

extension HabitPathSnapshot {

    /// Levels already reached on the whole path.
    var completedLevels: Int {
        units.reduce(0) { $0 + $1.completedLevels }
    }

    /// Levels the path holds in total, all units counted.
    var totalLevels: Int {
        HabitUnit.allCases.count * HabitPathEngine.levelRequirements.count
    }

    /// S4: XP the reached levels pay, as the server's ledger counts it (50 per
    /// level). Only what the levels themselves pay: the rest of the XP comes from
    /// drives, lessons and quests and is read from `my_xp` elsewhere.
    var xpFromLevels: Int {
        completedLevels * HabitPathEngine.xpPerLevel
    }

    /// The unit the user is working on: the first open one that is not complete.
    var currentUnit: HabitUnitProgress? {
        units.first { $0.isUnlocked && !$0.isCompleted }
    }
}
