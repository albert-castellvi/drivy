import SwiftUI

/// Histórico (S9): the days the plan in force allows, newest first, plus the upsell
/// row when older days are locked.
///
/// It reads the days the Hoy tab already fetched (no extra round trip) and asks
/// `HistoryGating` what to show, so the screen only renders and the rule stays
/// testable on its own.
struct HistoryView: View {

    /// Days newest first, as `public.daily_scores` returns them.
    let days: [HistoryDay]

    @EnvironmentObject private var freemium: FreemiumService

    @State private var isPaywallPresented = false

    private var rows: [HistoryRow] {
        HistoryGating.rows(days: days, access: freemium.access)
    }

    var body: some View {
        List {
            if days.isEmpty {
                Text(
                    "Aún no hay días registrados. En cuanto completes un trayecto, aparecerá aquí."
                )
                    .font(.drivyBody)
                    .foregroundStyle(Color.drivyInkMuted)
            }

            ForEach(rows) { row in
                switch row {
                case .day(let day):
                    dayRow(day)
                        .listRowBackground(Color.drivyPaper)
                case .locked(let hiddenDays):
                    lockedRow(hiddenDays: hiddenDays)
                        .listRowBackground(Color.drivyPaper)
                }
            }
        }
        .background(Color.drivyPaper)
        .scrollContentBackground(.hidden)
        .navigationTitle("Histórico")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isPaywallPresented) {
            PaywallPresenter(freemium: freemium)
                .makePaywallView(onClose: { isPaywallPresented = false })
        }
    }

    // MARK: - Rows

    /// One day of the history as a mark on the road: the score on a mini `KmPost`,
    /// the date in the strong body role, and the counts in the footnote under it
    /// (S5). No card: the list separators are the rules.
    private func dayRow(_ day: HistoryDay) -> some View {
        HStack(spacing: 14) {
            // The number speaks for itself inside the combined row: post first,
            // then date and counts, exactly the visual order.
            KmPost(
                value: DriveFormat.score(day.score),
                size: KmPostSize.marker
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(DriveFormat.shortDay(day.date))
                    .font(.drivyBodyStrong)
                    .foregroundStyle(Color.drivyInk)

                HStack(spacing: 8) {
                    Text(DriveFormat.distance(day.distanceKm))
                    Text("·")
                    Text(DriveFormat.drivesCount(day.drivesCount))
                }
                .font(.drivyFootnote)
                .foregroundStyle(Color.drivyInkMuted)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        // One element per row: post, date and counts are read in the order shown.
        .accessibilityElement(children: .combine)
        .contentShape(Rectangle())
    }

    /// One row for every day the free plan hides (S9), with the paywall one tap away.
    private func lockedRow(hiddenDays: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(HistoryGating.lockedMessage, systemImage: "lock.fill")
                .font(.drivyBody)
                .foregroundStyle(Color.drivyInk)
                .fixedSize(horizontal: false, vertical: true)

            Text(hiddenDays == 1 ? "1 día bloqueado" : "\(hiddenDays) días bloqueados")
                .font(.drivyFootnote)
                .foregroundStyle(Color.drivyInkMuted)

            Button {
                isPaywallPresented = true
            } label: {
                Text(PaywallCopy.title)
                    .font(.drivyBodyStrong)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        HistoryView(days: [])
            .environmentObject(FreemiumService(anchorDate: Date()))
    }
}
