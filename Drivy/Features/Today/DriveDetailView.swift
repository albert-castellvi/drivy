import MapKit
import SwiftUI

/// Detail of one stored drive (T4, S6, S10).
///
/// The server keeps the summarized numbers of a drive, never its samples, so the
/// figures here come from `public.drives` and the route can only come from an
/// in-memory track this device still holds (`LocalRouteStore`). When there is no
/// track, the screen says so instead of drawing an invented line.
struct DriveDetailView: View {

    let drive: DriveHistoryRow

    private var track: DriveTrack? {
        LocalRouteStore.shared.track(forStartedAt: drive.startedAt)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                mapSection
                summarySection
                eventsSection
            }
            .padding()
        }
        .navigationTitle("Trayecto")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Map

    @ViewBuilder
    private var mapSection: some View {
        if let track, track.coordinates.count > 1 {
            Map(initialPosition: .region(track.region)) {
                MapPolyline(coordinates: track.coordinates)
                    .stroke(Color.accentColor, lineWidth: 4)
            }
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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

    // MARK: - Summary

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(DriveFormat.shortDay(drive.startedAt))
                    .font(.headline)
                Text(
                    "\(DriveFormat.time(drive.startedAt)) · "
                        + DriveFormat.duration(TimeInterval(drive.durationSeconds))
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            HStack(alignment: .top, spacing: 16) {
                DriveMetric(title: "Nota", value: DriveFormat.score(drive.score))
                DriveMetric(title: "Distancia", value: DriveFormat.distance(drive.distanceKm))
            }

            HStack(alignment: .top, spacing: 16) {
                DriveMetric(
                    title: "Media",
                    value: DriveFormat.speed(drive.averageSpeedKmh)
                )
                DriveMetric(
                    title: "Modo",
                    value: drive.connectedMode ? "Conectado" : "Sin conexión"
                )
            }
        }
        .drivyCard()
    }

    // MARK: - Events

    private var eventsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cómo fue la conducción")
                .font(.headline)

            eventRow("Frenadas bruscas", count: drive.harshBrakes, systemImage: "hand.raised.fill")
            eventRow("Aceleraciones bruscas", count: drive.harshAccelerations, systemImage: "arrow.up.right")
            eventRow("Excesos de velocidad", count: drive.speedingEvents, systemImage: "speedometer")
            eventRow("Uso del móvil", count: drive.phoneUseEvents, systemImage: "iphone")

            if drive.connectedMode {
                Text("Conducción conectada: el uso del móvil no penaliza (S13).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .drivyCard()
    }

    private func eventRow(_ title: String, count: Int, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.subheadline)

            Spacer(minLength: 0)

            Text("\(count)")
                .font(.subheadline.monospacedDigit().weight(.semibold))
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
