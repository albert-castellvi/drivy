import MapKit
import SwiftUI

/// Detail of one stored drive (T4, S6, S10).
///
/// The server keeps the summarized numbers of a drive, never its samples, so the
/// figures here come from `public.drives` and the route can only come from an
/// in-memory track this device still holds (`LocalRouteStore`). When there is no
/// track, the screen says so instead of drawing an invented line.
///
/// The screen speaks the same road language as the post-drive summary (S5): the
/// route as the hero, the score as a hitto, the event kinds as dashboard
/// tell-tales, and the events as a rule-divided list of road signs — no cards.
struct DriveDetailView: View {

    let drive: DriveHistoryRow

    private var track: DriveTrack? {
        LocalRouteStore.shared.track(forStartedAt: drive.startedAt)
    }

    /// The stored route only when it has enough points to be drawn as a line.
    private var drawableTrack: DriveTrack? {
        guard let track, track.coordinates.count > 1 else { return nil }
        return track
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                mapSection
                headlineSection
                DriveEventLampRow(rows: drive.eventRows)
                eventsSection
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
        .background(Color.drivyPaper)
        .navigationTitle("Trayecto")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Map

    @ViewBuilder
    private var mapSection: some View {
        if let drawableTrack {
            Map(initialPosition: .region(drawableTrack.region)) {
                MapPolyline(coordinates: drawableTrack.coordinates)
                    .stroke(Color.drivyTint, lineWidth: 4)
            }
            .frame(height: 260)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            PlaceholderCard(
                systemImage: "map",
                title: "Ruta no disponible en este móvil",
                message: "Las muestras de GPS no se suben al servidor, así que la ruta solo "
                    + "aparece si este móvil la conservó en memoria. Los datos del trayecto sí "
                    + "están guardados."
            )
        }
    }

    // MARK: - Score and figures

    private var headlineSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .bottom, spacing: 12) {
                KmPost(
                    value: DriveFormat.score(drive.score),
                    capColor: Color.drivySignRed,
                    size: KmPostSize.score
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text("Nota")
                        .font(.drivyTitle)
                        .foregroundStyle(Color.drivyInk)

                    Text(DriveFormat.shortDay(drive.startedAt))
                        .font(.drivyFootnote)
                        .foregroundStyle(Color.drivyInkMuted)

                    Text(
                        "\(DriveFormat.time(drive.startedAt)) · "
                            + DriveFormat.duration(TimeInterval(drive.durationSeconds))
                    )
                    .font(.drivyFootnote)
                    .foregroundStyle(Color.drivyInkMuted)
                }

                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)

            HStack(alignment: .top, spacing: 16) {
                DriveQuietFigure(title: "Distancia", value: DriveFormat.distance(drive.distanceKm))
                DriveQuietFigure(title: "Media", value: DriveFormat.speed(drive.averageSpeedKmh))
                DriveQuietFigure(title: "Modo", value: drive.connectedMode ? "Conectado" : "Sin conexión")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Events

    private var eventsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Cómo fue la conducción")
                .font(.drivyHeadline)
                .foregroundStyle(Color.drivyInk)
                .padding(.bottom, 8)

            ForEach(Array(drive.eventRows.enumerated()), id: \.element.id) { index, row in
                if index > 0 {
                    DriveHairlineRule().padding(.vertical, 6)
                }

                DriveEventSignRow(row: row)
            }

            if drive.connectedMode {
                DriveHairlineRule().padding(.vertical, 6)

                Text("Conducción conectada: el uso del móvil no penaliza (S13).")
                    .font(.drivyFootnote)
                    .foregroundStyle(Color.drivyInkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension DriveHistoryRow {

    /// The four event kinds with the count stored for this drive, always in
    /// `DriveEventKind.allCases` order and with zero counts included: the same
    /// order and the same words the post-drive summary uses, so the two screens of
    /// one drive can never disagree (S5).
    var eventRows: [DebriefEventRow] {
        DriveEventKind.allCases.map { kind in
            DebriefEventRow(kind: kind, count: eventCount(of: kind))
        }
    }

    /// The stored count of one kind. `DriveRecord` answers the same question for a
    /// drive still on the phone; this is its twin for a row read back from the
    /// server.
    private func eventCount(of kind: DriveEventKind) -> Int {
        switch kind {
        case .harshBrake:
            return harshBrakes
        case .harshAcceleration:
            return harshAccelerations
        case .speeding:
            return speedingEvents
        case .phoneUse:
            return phoneUseEvents
        }
    }
}

private extension DriveTrack {

    /// Camera that contains the whole route with a bit of margin.
    var region: MKCoordinateRegion {
        let latitudes = coordinates.map(\.latitude)
        let longitudes = coordinates.map(\.longitude)

        guard
            let minLatitude = latitudes.min(),
            let maxLatitude = latitudes.max(),
            let minLongitude = longitudes.min(),
            let maxLongitude = longitudes.max()
        else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                span: MKCoordinateSpan(latitudeDelta: 1, longitudeDelta: 1)
            )
        }

        let center = CLLocationCoordinate2D(
            latitude: (minLatitude + maxLatitude) / 2,
            longitude: (minLongitude + maxLongitude) / 2
        )
        // A tiny route would zoom in to street level and a two-point route would
        // have no spread at all, hence the floor.
        let span = MKCoordinateSpan(
            latitudeDelta: max(maxLatitude - minLatitude, 0.005) * 1.4,
            longitudeDelta: max(maxLongitude - minLongitude, 0.005) * 1.4
        )
        return MKCoordinateRegion(center: center, span: span)
    }
}

#Preview {
    NavigationStack {
        DriveDetailView(
            drive: DriveHistoryRow(
                id: "preview",
                startedAt: Date(),
                endedAt: Date().addingTimeInterval(900),
                distanceKm: 12.3,
                durationSeconds: 900,
                score: 87,
                harshBrakes: 2,
                harshAccelerations: 1,
                phoneUseEvents: 0,
                speedingEvents: 3,
                connectedMode: true
            )
        )
    }
}
