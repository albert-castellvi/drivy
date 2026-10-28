import Foundation
import Supabase
import UserNotifications

/// When the daily streak reminder fires (S7).
///
/// The reminder only ever invites to the one-minute lesson, never to drive, and
/// it is never pending while a drive is being recorded.
enum ReminderSchedule {

    /// Local hour of the reminder.
    static let hour = 20

    /// Next fire date: today at 20:00 while today does not count yet for the
    /// streak and 20:00 is still ahead, otherwise tomorrow at 20:00. `nil` while
    /// driving, so nothing can buzz on the road.
    static func nextFireDate(
        now: Date,
        todayCounted: Bool,
        isDriving: Bool,
        calendar: Calendar = .current
    ) -> Date? {
        guard !isDriving else { return nil }

        guard let today = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: now) else {
            return nil
        }
        if !todayCounted && now < today {
            return today
        }
        return calendar.date(byAdding: .day, value: 1, to: today)
    }
}

/// Identifiers of the local notifications of the loop (S7).
enum NotificationIdentifier {

    static let reminder = "drivy.streak.reminder"
    static let leagueResults = "drivy.league.results"
}

/// Which notifications may be pending (S7).
///
/// Pure on purpose: "nunca durante un trayecto" is a decision over two booleans,
/// so it is tested without the notification centre or a network. Leaving the
/// repeating league notification out of the guard that the reminder already has
/// is exactly how a user driving at 09:00 on a Monday got "Resultados de tu liga"
/// mid-drive (B2 of the QA report).
enum NotificationPolicy {

    /// Everything a drive start withdraws: no notification may buzz on the road.
    static let suppressedWhileDriving = [
        NotificationIdentifier.reminder,
        NotificationIdentifier.leagueResults
    ]

    /// The league results notification repeats every Monday and outlives the
    /// drive, so it needs the same guard: the drive-end refresh, where `isDriving`
    /// is already false, schedules it again.
    static func schedulesLeagueResults(isDriving: Bool, isInPublicLeagues: Bool) -> Bool {
        isInPublicLeagues && !isDriving
    }
}

/// Local notifications of the Duolingo loop (S7): the streak reminder and the
/// Monday league results. No push server: everything is scheduled on device and
/// rescheduled whenever the app comes to the foreground, a drive ends or a
/// lesson is recorded.
@MainActor
enum DriveNotifications {

    private static var isDriving = false

    /// A drive started: every pending notification of the day is withdrawn, so
    /// nothing can buzz on the road (S7).
    static func driveDidStart() {
        isDriving = true
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: NotificationPolicy.suppressedWhileDriving)
    }

    static func driveDidEnd() {
        isDriving = false
        Task { await refresh() }
    }

    /// Reschedules both notifications from the current progress. Silently does
    /// nothing without permission or without a session: a reminder is never worth
    /// an error on screen.
    ///
    /// - Parameter calendar: formats the local fire time of the reminder, so it
    ///   stays the device calendar. It is not a server key: the day the reminder
    ///   reasons about is Madrid (`isTodayCounted`).
    static func refresh(now: Date = Date(), calendar: Calendar = .current) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            return
        }

        center.removePendingNotificationRequests(withIdentifiers: [NotificationIdentifier.reminder])
        let counted = (try? await isTodayCounted(now: now)) ?? false
        if let fireDate = ReminderSchedule.nextFireDate(
            now: now,
            todayCounted: counted,
            isDriving: isDriving,
            calendar: calendar
        ) {
            let content = UNMutableNotificationContent()
            content.title = "Te queda la lección de hoy"
            content.body = "Un minuto de teoría mantiene tu racha."
            content.sound = .default
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
            try? await center.add(UNNotificationRequest(
                identifier: NotificationIdentifier.reminder,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            ))
        }

        // S7: the league results are withdrawn here too, and the drive-end refresh
        // brings them back. While a drive is in progress this leaves them
        // unscheduled instead of re-adding the repeating Monday trigger (B2 of
        // the QA report).
        center.removePendingNotificationRequests(withIdentifiers: [NotificationIdentifier.leagueResults])
        var isOptedIn = false
        if !isDriving {
            isOptedIn = (try? await isInPublicLeagues()) == true
        }
        if NotificationPolicy.schedulesLeagueResults(isDriving: isDriving, isInPublicLeagues: isOptedIn) {
            let content = UNMutableNotificationContent()
            content.title = "Resultados de tu liga"
            content.body = "Mira si has subido de división esta semana."
            var monday = DateComponents()
            monday.weekday = 2
            monday.hour = 9
            try? await center.add(UNNotificationRequest(
                identifier: NotificationIdentifier.leagueResults,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: monday, repeats: true)
            ))
        }
    }

    /// Same rule as the streak (S1): a lesson today, or today's drives with a
    /// clean daily score.
    ///
    /// Madrid, not the device zone: both the day key and the day boundary are
    /// compared with rows whose day the server derives as `madrid_today()`
    /// (B1 of the QA report). The reminder's own fire time keeps the device
    /// calendar, which comes in as `refresh`'s parameter.
    private static func isTodayCounted(now: Date) async throws -> Bool {
        let progress = SupabaseProgressRepository()
        let calendar = Calendar.madrid
        let today = DriveDay.key(for: now, calendar: calendar)
        let lessonDays = try await progress.lessonDays(from: today, to: today)
        if !lessonDays.isEmpty {
            return true
        }
        let drives = try await progress.drives(since: calendar.startOfDay(for: now))
        guard let daily = DailyScoreCalculator.dailyScore(from: drives.map(\.aggregateInput)) else {
            return false
        }
        return daily.score >= StreakCalculator.cleanDayThreshold
    }

    private struct OptInRow: Decodable {
        let optedIn: Bool

        enum CodingKeys: String, CodingKey {
            case optedIn = "opted_in"
        }
    }

    private static func isInPublicLeagues() async throws -> Bool {
        let rows: [OptInRow] = try await SupabaseProvider.shared
            .from("public_league_entries")
            .select("opted_in")
            .execute()
            .value
        return rows.first?.optedIn ?? false
    }
}

/// Asks for notification permission at a moment the user understands why (S7):
/// after their first lesson or first drive summary, never at launch.
@MainActor
enum NotificationPermission {

    private static let askedKey = "drivy.notifications.asked"

    static func requestAfterFirstLesson(defaults: UserDefaults = .standard) {
        Task {
            if !defaults.bool(forKey: askedKey) {
                defaults.set(true, forKey: askedKey)
                _ = try? await UNUserNotificationCenter.current()
                    .requestAuthorization(options: [.alert, .sound, .badge])
            }
            await DriveNotifications.refresh()
        }
    }
}
