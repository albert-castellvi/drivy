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
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                switch row {
                case .day(let day):
                    dayRow(day)
                case .locked(let hiddenDays):
                    lockedRow(hiddenDays: hiddenDays)
                }
            }
        }
        .navigationTitle("Histórico")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isPaywallPresented) {
            PaywallPresenter(freemium: freemium)
                .makePaywallView(onClose: { isPaywallPresented = false })
        }
    }

    // MARK: - Rows

    private func dayRow(_ day: HistoryDay) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(DriveFormat.shortDay(day.date))
                    .font(.headline)

                Spacer(minLength: 0)

                Text(DriveFormat.score(day.score))
                    .font(.title3.monospacedDigit().weight(.semibold))
            }

            HStack(spacing: 8) {
                Text(DriveFormat.distance(day.distanceKm))
                Text("·")
                Text(DriveFormat.drivesCount(day.drivesCount))
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    /// One row for every day the free plan hides (S9), with the paywall one tap away.
    private func lockedRow(hiddenDays: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(HistoryGating.lockedMessage, systemImage: "lock.fill")
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)

            Text(hiddenDays == 1 ? "1 día bloqueado" : "\(hiddenDays) días bloqueados")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                isPaywallPresented = true
            } label: {
                Text(PaywallCopy.title)
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
