import SwiftUI

/// Tab "Camino" (S3, S4): the habit path of the user, unit by unit, plus the
/// one-minute theory lesson of the day.
///
/// It sits between Hoy and Ligas because it is the map of the loop: what to learn
/// next, and what each level pays. Nothing on this screen invites the user to
/// drive: every unit counts drives that already happened and the lesson needs no
/// car, which is the safety principle of the whole feature.
struct PathView: View {

    @EnvironmentObject private var auth: AuthViewModel

    @StateObject private var model = HabitPathViewModel()

    /// Sheet of the theory lesson (S2), opened from the entry card of the tab.
    @State private var isPresentingLesson = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if model.isLoading && model.snapshot.units.isEmpty {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    }

                    lessonCard
                    summaryCard
                    pathCard

                    if let errorMessage = model.errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding()
            }
            .navigationTitle("Camino")
            .refreshable { await reload() }
            .task(id: auth.signedInUser?.id) { await reload() }
            .sheet(
                isPresented: $isPresentingLesson,
                // The lesson makes the day count for the streak (S1), so the entry
                // card states it as soon as the sheet closes.
                onDismiss: { Task { await reload() } }
            ) {
                LessonQuizView(onFinished: { _, _ in isPresentingLesson = false })
            }
        }
    }

    // MARK: - Sections

    /// S2/S3: the theory lesson, which is also the way to keep the streak without
    /// a car.
    private var lessonCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Lección de hoy", systemImage: "text.book.closed.fill")
                .font(.headline)

            Text(lessonMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                isPresentingLesson = true
            } label: {
                Text(lessonButtonTitle)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .drivyCard()
    }

    /// S3/S4: how far the path is and what the levels have paid.
    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Tu camino", systemImage: "map.fill")
                .font(.headline)

            HStack(spacing: 12) {
                DriveMetric(
                    title: "Niveles",
                    value: "\(model.snapshot.completedLevels) de \(model.snapshot.totalLevels)"
                )
                DriveMetric(
                    title: "XP de niveles",
                    value: "\(model.snapshot.xpFromLevels) XP"
                )
            }

            if let current = model.snapshot.currentUnit {
                Text("Ahora: «\(current.unit.title)». \(current.unit.tip)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .drivyCard()
    }

    /// S3: the units as a vertical path, locked ones included, so the whole way is
    /// visible from the start.
    private var pathCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Unidades")
                .font(.headline)

            ForEach(model.snapshot.units) { progress in
                HabitPathRow(
                    progress: progress,
                    isLast: progress.id == model.snapshot.units.last?.id
                )
            }

            Text(
                "Cada nivel superado suma \(HabitPathEngine.xpPerLevel) XP. "
                    + "Solo cuentan los trayectos de 2 km o más: ninguna unidad premia conducir más."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .drivyCard()
    }

    // MARK: - Copy of the lesson card

    private var lessonMessage: String {
        model.snapshot.hasLessonToday
            ? "Ya has hecho la lección de hoy: cuenta para tu racha y suma XP."
            : "Un minuto de teoría. Hacerla ya hace que el día cuente para la racha, aunque no cojas el coche."
    }

    private var lessonButtonTitle: String {
        model.snapshot.hasLessonToday ? "Repasar la lección" : "Hacer la lección (1 minuto)"
    }

    // MARK: - Data

    private func reload() async {
        guard auth.signedInUser != nil else { return }
        await model.load()
    }
}

/// One unit of the vertical path: the node of the trail, the tip, the progress of
/// the next level and where the unit stands (S3).
private struct HabitPathRow: View {

    let progress: HabitUnitProgress

    /// Last row draws no connector under its node.
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            trail

            VStack(alignment: .leading, spacing: 4) {
                Text(progress.unit.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(progress.isUnlocked ? Color.primary : Color.secondary)

                Text(progress.unit.tip)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let progressText = progress.progressText {
                    ProgressView(value: progress.progressFraction)
                        .tint(.accentColor)

                    Text(progressText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Text(progress.statusText)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(progress.isUnlocked ? Color.accentColor : Color.secondary)
            }
            .padding(.bottom, isLast ? 0 : 12)

            Spacer(minLength: 0)
        }
        // One element per unit: the node only repeats the state the row states.
        .accessibilityElement(children: .combine)
    }

    // MARK: - Trail

    private var trail: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(progress.isUnlocked ? Color.accentColor : Color.secondary.opacity(0.25))
                    .frame(width: 30, height: 30)

                Image(systemName: nodeSymbol)
                    .font(.caption)
                    .foregroundStyle(progress.isUnlocked ? Color.white : Color.secondary)
            }

            if !isLast {
                Rectangle()
                    .fill(.quaternary)
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
            }
        }
        .frame(width: 30)
        .accessibilityHidden(true)
    }

    private var nodeSymbol: String {
        if !progress.isUnlocked {
            return "lock.fill"
        }
        if progress.isCompleted {
            return "checkmark"
        }
        return progress.unit.symbolName
    }
}

#Preview {
    PathView()
        .environmentObject(AuthViewModel())
}
