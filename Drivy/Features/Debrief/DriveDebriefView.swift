import MapKit
import SwiftUI

/// The ~30-second summary shown when a drive ends (S2).
///
/// It answers one question — what cost me points — with the driver score, the count
/// of every event kind, the route on a map with one marker per located event and a
/// single piece of advice chosen from the component that cost the most. Nothing
/// here invites the user to drive more, further or more often: the loop rewards
/// driving better (S2, S4), so the only call to action of the sheet is closing it.
///
/// The route is the in-memory track `LocalRouteStore` kept for this drive (L11): as
/// with the drive detail, a route this device does not remember cannot be invented.
struct DriveDebriefView: View {

    let record: DriveRecord

    let onClose: () -> Void

    /// The permission prompt of S7 is asked once: a double tap, or a swipe after
    /// tapping, must not ask twice.
    @State private var didClose = false

    init(record: DriveRecord, onClose: @escaping () -> Void) {
        self.record = record
        self.onClose = onClose
    }

    private var summary: DebriefSummary {
        DebriefSummary(record: record)
    }

    private var track: DriveTrack? {
        LocalRouteStore.shared.track(forStartedAt: record.startedAt)
    }

    private var markerCoordinates: [CLLocationCoordinate2D] {
        summary.markers.map { marker in
            CLLocationCoordinate2D(
                latitude: marker.coordinate.latitude,
                longitude: marker.coordinate.longitude
            )
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    scoreSection
                    mapSection
                    eventsSection
                    adviceSection
                }
                .padding()
            }
            .navigationTitle("Resumen del trayecto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Cerrar") { close() }
                }
            }
        }
        // A swipe-down also closes the sheet, and the S7 prompt must still be
        // asked once: `didClose` makes both paths idempotent.
        .onDisappear { close() }
    }

    // MARK: - Score

    private var scoreSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(DriveFormat.score(summary.score))
                    .font(.system(size: 46, weight: .bold, design: .rounded))
                    .monospacedDigit()

                Text("Driver Score")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .top, spacing: 16) {
                DriveMetric(title: "Distancia", value: DriveFormat.distance(summary.distanceKm))
                DriveMetric(
                    title: "Duración",
                    value: DriveFormat.duration(TimeInterval(summary.durationSeconds))
                )
            }
        }
        .drivyCard()
    }

    // MARK: - Map

    @ViewBuilder
    private var mapSection: some View {
        if let track, track.coordinates.count > 1 {
            Map(initialPosition: .region(MapFit.region(for: track.coordinates + markerCoordinates))) {
                MapPolyline(coordinates: track.coordinates)
                    .stroke(Color.accentColor, lineWidth: 4)
                ForEach(summary.markers) { marker in
                    Marker(
                        marker.kind.debriefTitle,
                        systemImage: marker.kind.debriefSystemImage,
                        coordinate: MapFit.coordinate(marker.coordinate)
                    )
                    .tint(marker.kind.debriefTint)
                }
            }
            .frame(height: 240)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        } else if !markerCoordinates.isEmpty {
            // No track, but the events still know where they happened: showing
            // only the markers is honest and better than an empty card.
            Map(initialPosition: .region(MapFit.region(for: markerCoordinates))) {
                ForEach(summary.markers) { marker in
                    Marker(
                        marker.kind.debriefTitle,
                        systemImage: marker.kind.debriefSystemImage,
                        coordinate: MapFit.coordinate(marker.coordinate)
                    )
                    .tint(marker.kind.debriefTint)
                }
            }
            .frame(height: 240)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        } else {
            PlaceholderCard(
                systemImage: "map",
                title: "Ruta no disponible en este móvil",
                message: "Las muestras de GPS no se suben al servidor, así que la ruta solo "
                    + "aparece si este móvil la conservó en memoria. El resto del resumen sí "
                    + "corresponde a este trayecto."
            )
        }
    }

    // MARK: - Events

    private var eventsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Qué ha contado el resumen")
                .font(.headline)

            ForEach(summary.eventRows) { row in
                HStack(spacing: 12) {
                    Label(row.kind.debriefTitle, systemImage: row.kind.debriefSystemImage)
                        .font(.subheadline)

                    Spacer(minLength: 0)

                    Text("\(row.count)")
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                }
            }
        }
        .drivyCard()
    }

    // MARK: - Advice

    private var adviceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(summary.tip.title, systemImage: summary.tip.systemImage)
                .font(.headline)

            Text(summary.tip.message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let note = summary.connectedNote {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .drivyCard()
    }

    // MARK: - Actions

    /// S7: the first summary is one of the two moments in which the notification
    /// permission is asked, when the user already knows what it is for. Never at
    /// launch.
    private func close() {
        guard !didClose else { return }
        didClose = true
        onClose()
        NotificationPermission.requestAfterFirstLesson()
    }
}

// MARK: - Presentation of the event kinds

extension DriveEventKind {

    /// Spanish, because it is user-facing copy (the app has no localization).
    var debriefTitle: String {
        switch self {
        case .harshBrake:
            return "Frenadas bruscas"
        case .harshAcceleration:
            return "Aceleraciones bruscas"
        case .speeding:
            return "Excesos de velocidad"
        case .phoneUse:
            return "Uso del móvil"
        }
    }

    var debriefSystemImage: String {
        switch self {
        case .harshBrake:
            return "hand.raised.fill"
        case .harshAcceleration:
            return "arrow.up.right"
        case .speeding:
            return "speedometer"
        case .phoneUse:
            return "iphone"
        }
    }

    /// Marker colour of the map: braking and speed in red, the rest in orange, so
    /// the two hardest components stand out on the route.
    var debriefTint: Color {
        switch self {
        case .harshBrake, .speeding:
            return .red
        case .harshAcceleration, .phoneUse:
            return .orange
        }
    }
}

// MARK: - Map fitting

/// Small geometry helper of the map: no rule, no clock, only arithmetic.
private enum MapFit {

    static func coordinate(_ coordinate: DriveCoordinate) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    /// Camera that contains every point with a bit of margin.
    static func region(for coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
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
    DriveDebriefView(
        record: DriveRecord(
            score: DriveScore(
                score: 88,
                distanceKm: 8.4,
                durationSeconds: 720,
                harshBrakes: 1,
                harshAccelerations: 0,
                phoneUseEvents: 0,
                speedingEvents: 0,
                connectedMode: true,
                events: [
                    DriveEvent(
                        kind: .harshBrake,
                        timestamp: 250,
                        coordinate: DriveCoordinate(latitude: 41.3874, longitude: 2.1686)
                    )
                ]
            ),
            startedAt: Date()
        ),
        onClose: {}
    )
}
