import Foundation
@testable import Drivy

/// Dates and entitlements shared by the monetization tests.
enum PremiumFixtures {

    /// Reference calendar: UTC, so day boundaries do not depend on the machine.
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        guard let utc = TimeZone(identifier: "UTC") else {
            preconditionFailure("UTC must always exist")
        }
        calendar.timeZone = utc
        return calendar
    }

    /// Day 1 of the free trial window: the profile creation (or first drive)
    /// date, 2026-03-01T09:00:00Z.
    static let anchorDate = Date(timeIntervalSince1970: 1_772_355_600)

    static func date(anchorOffsetDays days: Int, hour: Int = 12) -> Date {
        let day = calendar.date(byAdding: .day, value: days, to: anchorDate) ?? anchorDate
        return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
    }

    /// An entitlement for the premium product, valid for `days` from `now`.
    static func entitlement(
        productID: String = PremiumProduct.monthlyIdentifier,
        expiringIn days: Int = 30,
        from now: Date = PremiumFixtures.date(anchorOffsetDays: 0),
        jws: String? = nil
    ) -> PremiumEntitlement {
        PremiumEntitlement(
            productID: productID,
            expirationDate: now.addingTimeInterval(TimeInterval(days) * 86_400),
            jws: jws
        )
    }
}
