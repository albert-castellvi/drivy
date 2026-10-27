import Foundation

/// How many events of one kind the drive recorded (S2: "conteo de eventos por
/// tipo").
struct DebriefEventRow: Identifiable, Equatable {

    let kind: DriveEventKind

    let count: Int

    var id: String {
        kind.rawValue
    }
}

/// One event the map can draw: only the ones whose position is known (S2).
struct DebriefMarker: Identifiable, Equatable {

    /// Position of the event inside `DriveRecord.events`, unique per drive.
    let id: Int

    let kind: DriveEventKind

    let coordinate: DriveCoordinate
}

/// Everything the post-drive summary shows, derived from the finished drive (S2).
///
/// Pure value type: no SwiftUI, no MapKit, no clock, so every rule of the sheet is
/// asserted in tests and the view only lays it out.
struct DebriefSummary: Equatable {

    let score: Int

    let distanceKm: Double

    let durationSeconds: Int

    /// One row per event kind, always in `DriveEventKind.allCases` order and zero
    /// counts included, so the sheet never reorders between drives.
    let eventRows: [DebriefEventRow]

    /// Events whose position is known, in time order: the map draws one marker
    /// each.
    let markers: [DebriefMarker]

    /// The single advice of the summary (S2).
    let tip: DebriefTip

    /// S2/S13 line about connected driving, present only when the drive was
    /// connected: with CarPlay or Bluetooth on, phone use is not penalized.
    let connectedNote: String?

    static let connectedModeNote = "Conducción conectada: el uso del móvil no ha penalizado."

    init(record: DriveRecord) {
        self.score = record.score
        self.distanceKm = record.distanceKm
        self.durationSeconds = record.durationSeconds
        self.eventRows = DriveEventKind.allCases.map { kind in
            DebriefEventRow(kind: kind, count: record.eventCount(of: kind))
        }
        self.markers = record.events.enumerated().compactMap { index, event in
            guard let coordinate = event.coordinate else { return nil }
            return DebriefMarker(id: index, kind: event.kind, coordinate: coordinate)
        }
        self.tip = DebriefTip.tip(for: record)
        self.connectedNote = record.connectedMode ? Self.connectedModeNote : nil
    }
}

extension DriveRecord {

    /// How many events of `kind` the score counted for this drive.
    ///
    /// The counts come from the record and not from `events`, because `events` is
    /// local and can be missing (a row read back from the server) while the counts
    /// are always there.
    func eventCount(of kind: DriveEventKind) -> Int {
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
