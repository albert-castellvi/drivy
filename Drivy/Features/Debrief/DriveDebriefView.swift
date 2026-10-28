import MapKit
import SwiftUI

/// The ~30-second summary shown when a drive ends (S2).
///
/// It answers one question — what cost me points — with the route on a map as the
/// hero, one small road sign per located event, the score as a hitto, the four
/// event kinds as dashboard tell-tales and a single piece of advice chosen from
/// the component that cost the most. Nothing here invites the user to drive more,
/// further or more often: the loop rewards driving better (S2, S4), so the only
/// call to action of the sheet is closing it.
///
/// The layout is the road language of S5: map first, signs instead of tinted dots,
/// `WarningLamp`s instead of stat tiles, hairline rules instead of stacked cards.
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

    /// The stored route only when it has enough points to be drawn as a line; the
    /// same rule the screen has always used.
    private var drawableTrack: DriveTrack? {
        guard let track, track.coordinates.count > 1 else { return nil }
        return track
    }

    private var markerCoordinates: [CLLocationCoordinate2D] {
        summary.markers.map { marker in
            CLLocationCoordinate2D(
                latitude: marker.coordinate.latitude,
                longitude: marker.coordinate.longitude
            )
        }
    }

    /// Everything the camera has to contain: the line and the events, if any.
    private var mapCoordinates: [CLLocationCoordinate2D] {
        (drawableTrack?.coordinates ?? []) + markerCoordinates
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    mapSection
                    headlineSection
                    DriveEventLampRow(rows: summary.eventRows)
                    eventsSection
                    adviceSection
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollContentBackground(.hidden)
            .background(Color.drivyPaper)
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

    // MARK: - Map (the hero of the screen)

    @ViewBuilder
    private var mapSection: some View {
        if drawableTrack != nil || !markerCoordinates.isEmpty {
            Map(initialPosition: .region(MapFit.region(for: mapCoordinates))) {
                if let drawableTrack {
                    MapPolyline(coordinates: drawableTrack.coordinates)
                        .stroke(Color.drivyTint, lineWidth: 4)
                }

                ForEach(summary.markers) { marker in
                    // The title is the annotation's own VoiceOver text, exactly as
                    // it was when these events were `Marker`s: the sign replaces the
                    // tinted dot, not the words.
                    Annotation(marker.kind.debriefTitle,
                               coordinate: MapFit.coordinate(marker.coordinate)) {
                        RoadSign(kind: EventSign.sign(for: marker.kind), size: 26)
                    }
                }
            }
            .frame(height: 260)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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

    // MARK: - Score

    private var headlineSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .bottom, spacing: 12) {
                KmPost(
                    value: DriveFormat.score(summary.score),
                    capColor: Color.drivySignRed,
                    isToday: true,
                    size: KmPostSize.score
                )

                Text("Driver Score")
                    .font(.drivyTitle)
                    .foregroundStyle(Color.drivyInk)

                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)

            HStack(alignment: .top, spacing: 16) {
                DriveQuietFigure(title: "Distancia", value: DriveFormat.distance(summary.distanceKm))
                DriveQuietFigure(
                    title: "Duración",
                    value: DriveFormat.duration(TimeInterval(summary.durationSeconds))
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Events

    private var eventsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Qué ha contado el resumen")
                .font(.drivyHeadline)
                .foregroundStyle(Color.drivyInk)
                .padding(.bottom, 8)

            ForEach(Array(summary.eventRows.enumerated()), id: \.element.id) { index, row in
                if index > 0 {
                    DriveHairlineRule().padding(.vertical, 6)
                }

                DriveEventSignRow(row: row)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Advice

    private var adviceSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            DriveHairlineRule()

            HStack(alignment: .top, spacing: 12) {
                RoadSign(kind: summary.tip.infoSign, size: 28)

                VStack(alignment: .leading, spacing: 4) {
                    Text(summary.tip.title)
                        .font(.drivyBodyStrong)
                        .foregroundStyle(Color.drivyInk)

                    Text(summary.tip.message)
                        .font(.drivyFootnote)
                        .foregroundStyle(Color.drivyInkMuted)
                        .fixedSize(horizontal: false, vertical: true)

                    if let note = summary.connectedNote {
                        Text(note)
                            .font(.drivyFootnote)
                            .foregroundStyle(Color.drivyInkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

// MARK: - The drive vocabulary shared by debrief and detail

/// The dashboard row of a drive: one tell-tale per event kind, lit when that kind
/// happened, with its count underneath (S5).
///
/// The four lamps always come in `DriveEventKind.allCases` order — the order
/// `DebriefSummary` already publishes — so the row never reshuffles between drives
/// and lines up with the list underneath it.
struct DriveEventLampRow: View {

    let rows: [DebriefEventRow]

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(rows) { row in
                WarningLamp(
                    systemName: row.kind.debriefSystemImage,
                    isLit: row.count > 0,
                    caption: "\(row.count)",
                    accessibilityLabel: "\(row.kind.debriefTitle): \(row.count)"
                )
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// One event kind in the list of the drive: its road sign, its name, how many.
struct DriveEventSignRow: View {

    let row: DebriefEventRow

    var body: some View {
        HStack(spacing: 12) {
            RoadSign(kind: EventSign.sign(for: row.kind), size: 28)

            Text(row.kind.debriefTitle)
                .font(.drivyBody)
                .foregroundStyle(Color.drivyInk)

            Spacer(minLength: 0)

            Text("\(row.count)")
                .font(.drivyBodyStrong.monospacedDigit())
                .foregroundStyle(row.count > 0 ? Color.drivyInk : Color.drivyInkMuted)
        }
        .frame(minHeight: 44)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// A labelled figure with no card: the small name above the value (S3 prefers
/// proximity and rules over tiles).
struct DriveQuietFigure: View {

    let title: String

    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.drivyKicker)
                .foregroundStyle(Color.drivyInkMuted)

            Text(value)
                .font(.drivyBodyStrong)
                .monospacedDigit()
                .foregroundStyle(Color.drivyInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// The hairline that separates two rows of the same list (S3).
struct DriveHairlineRule: View {

    var body: some View {
        Rectangle()
            .fill(Color.drivyRule)
            .frame(height: 1)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
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

    /// The pictogram the dashboard lamp of this kind wears. The sign of the event
    /// on the map and in the list comes from `EventSign`; this is the second,
    /// mechanical half of the same message.
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
}

extension DebriefTip {

    /// The sign the advice block wears: always the blue information face, because
    /// an advice is not a road hazard painted on the route (S3, S5). The four
    /// advice of an event keep that event's own pictogram, the same one its
    /// dashboard lamp shows; a clean drive gets a bare checkmark, because
    /// `checkmark.seal.fill` would put a second shape inside the panel.
    var infoSign: RoadSign.Kind {
        switch self {
        case .harshBrake, .harshAcceleration, .speeding, .phoneUse:
            return .info(systemName: systemImage)
        case .clean:
            return .info(systemName: "checkmark")
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
