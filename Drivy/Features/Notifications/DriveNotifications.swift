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

/// Local notifications of the Duolingo loop (S7): the streak reminder and the
/// Monday league results. No push server: everything is scheduled on device and
/// rescheduled whenever the app comes to the foreground, a drive ends or a
/// lesson is recorded.
@MainActor
enum DriveNotifications {

    static let reminderID = "drivy.streak.reminder"
    static let leagueResultsID = "drivy.league.results"

    private static var isDriving = false

    /// A drive started: the reminder must not fire on the road.
    static func driveDidStart() {
        isDriving = true
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [reminderID])
    }

    static func driveDidEnd() {
        isDriving = false
        Task { await refresh() }
    }

    /// Reschedules both notifications from the current progress. Silently does
    /// nothing without permission or without a session: a reminder is never worth
    /// an error on screen.
    static func refresh(now: Date = Date(), calendar: Calendar = .current) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            return
        }

        center.removePendingNotificationRequests(withIdentifiers: [reminderID])
        let counted = (try? await isTodayCounted(now: now, calendar: calendar)) ?? false
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
                identifier: reminderID,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            ))
        }

        center.removePendingNotificationRequests(withIdentifiers: [leagueResultsID])
        if (try? await isInPublicLeagues()) == true {
            let content = UNMutableNotificationContent()
            content.title = "Resultados de tu liga"
            content.body = "Mira si has subido de división esta semana."
            var monday = DateComponents()
            monday.weekday = 2
            monday.hour = 9
            try? await center.add(UNNotificationRequest(
                identifier: leagueResultsID,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: monday, repeats: true)
            ))
        }
    }

    /// Same rule as the streak (S1): a lesson today, or today's drives with a
    /// clean daily score.
    private static func isTodayCounted(now: Date, calendar: Calendar) async throws -> Bool {
        let progress = SupabaseProgressRepository()
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
