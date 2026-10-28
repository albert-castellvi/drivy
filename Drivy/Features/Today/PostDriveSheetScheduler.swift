import Foundation

/// A sheet of the Hoy tab (S2, S9).
///
/// One enum for the whole tab: SwiftUI gives every view a single sheet slot, so two
/// `.sheet` modifiers would silently fight over it and drop one of them. With the
/// sheets named in one place, the order S2 asks for (the post-drive summary first,
/// the paywall of the first drive after it, L9) becomes a decision of a value type
/// instead of nested guards inside the view.
enum TodaySheet: Equatable, Identifiable {

    /// Share card (S9).
    case shareCard

    /// Paywall after the first drive and from the gating hook points (S9).
    case paywall

    /// Post-drive summary (S2): shown before the paywall, never instead of it.
    case debrief(DriveRecord)

    /// Theory lesson of the day (S2).
    case lesson

    /// Identity of the presentation. The debrief carries its drive, so a second
    /// drive is a different sheet and `.sheet(item:)` presents it again instead of
    /// dismissing it as the sheet already on screen.
    var id: String {
        switch self {
        case .shareCard:
            return "shareCard"
        case .paywall:
            return "paywall"
        case .debrief(let record):
            return "debrief-\(record.startedAt.timeIntervalSince1970)"
        case .lesson:
            return "lesson"
        }
    }
}

/// S2/S9: which sheet the Hoy tab shows next, and whether that step consumes the
/// "paywall already shown" flag.
///
/// Pure on purpose. The one S2 rule that lives entirely in presentation code is the
/// order of the sheets ("hoja que se abre al terminar un trayecto, **antes del
/// paywall del primer trayecto**"), so it is a value here and a test in
/// `PostDriveSheetSchedulerTests` instead of guards that a reordering can silently
/// invert.
///
/// The view keeps every side effect (route hand-off, freemium history window,
/// reloads) and only asks this type what to show next. Nothing here records, gates
/// or rewards a drive: it decides presentation only.
enum PostDriveSheetScheduler {

    /// What the tab knows about the S9 paywall at the moment of deciding.
    ///
    /// It carries the state of `FirstDrivePaywallGate` as values so this type never
    /// restates the S9 rule (`PaywallPresenter.shouldPresent`), which stays in the
    /// presenter and in the gate.
    struct PaywallState: Equatable {

        /// A drive finished in this session. A plan that arrives later (StoreKit is
        /// slow, or the user just purchased) must not turn a launch into an ad for
        /// drives recorded days ago.
        let hasCompletedDriveThisSession: Bool

        /// `FirstDrivePaywallGate.wasPresented`: the paywall is once ever.
        let wasPresented: Bool

        /// `FirstDrivePaywallGate.shouldPresent(...)`: there is a drive, the plan is
        /// known and it is Free.
        let isDue: Bool
    }

    /// One step of the schedule.
    struct Step: Equatable {

        /// Sheet to present, or `nil` when the tab shows nothing new.
        let nextSheet: TodaySheet?

        /// `true` when the caller must record the paywall as presented. Only the
        /// paywall consumes the gate: the debrief never does (S2).
        let consumesPaywallGate: Bool

        /// Nothing to change on screen.
        static let stay = Step(nextSheet: nil, consumesPaywallGate: false)
    }

    /// S2: a finished drive always opens its post-drive summary first, and the
    /// paywall of S9 can only follow it once that sheet is closed.
    static func driveDidComplete(_ drive: DriveRecord) -> Step {
        Step(nextSheet: .debrief(drive), consumesPaywallGate: false)
    }

    /// S9: the paywall after the first drive, once ever, and only when no other
    /// sheet owns the slot (the debrief of the same drive is closed first, L9).
    ///
    /// - Parameter shownSheet: sheet of the tab right now; the paywall waits for it
    ///   instead of replacing it.
    static func paywallIfDue(shownSheet: TodaySheet?, paywall: PaywallState) -> Step {
        guard paywall.hasCompletedDriveThisSession else { return .stay }
        guard shownSheet == nil else { return .stay }
        guard !paywall.wasPresented, paywall.isDue else { return .stay }

        return Step(nextSheet: .paywall, consumesPaywallGate: true)
    }
}
