import Foundation

/// One finished drive waiting for its upload, tagged with the session user that
/// recorded it (D4). The tag is what keeps a drive from ever being uploaded into
/// another user's account after a sign-out and a new sign-in: the retry only
/// uploads entries whose user id matches the current session.
struct PendingDriveUpload: Codable, Equatable {

    let record: DriveRecord

    /// Id of the user signed in when the drive was recorded. `nil` only when the
    /// session could not be resolved at recording time (for example a session
    /// that had already been signed out): such an entry is kept but never
    /// uploaded, because its owner cannot be proven.
    let sessionUserID: String?
}

/// D4: a failed upload must never lose the finished drive.
///
/// `DriveRecorder` persists every finished drive here *before* uploading and
/// removes the entry only when the whole upload (the `drives` insert plus the
/// `daily_scores` recompute) succeeded. The store is one JSON file in
/// Application Support holding one entry per drive id, written atomically, so a
/// crash mid-write can never lose the entries that were already there.
final class PendingDriveStore {

    private let url: URL

    private let fileManager: FileManager

    /// - Parameters:
    ///   - directory: Directory of the store file. Defaults to the app's
    ///     Application Support directory; tests inject a temporary one.
    ///   - fileManager: File system used for every operation; injectable for
    ///     tests.
    init(directory: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager

        let base = directory ?? Self.defaultDirectory(fileManager: fileManager)
        self.url = base.appendingPathComponent("pending-drives.json", isDirectory: false)
    }

    /// Adds the entry, replacing any previous entry with the same drive id
    /// (one entry per drive id).
    func add(_ upload: PendingDriveUpload) throws {
        var entries = load().filter { $0.record.id != upload.record.id }
        entries.append(upload)
        try persist(entries)
    }

    /// Every pending entry, oldest drive first.
    func all() -> [PendingDriveUpload] {
        load().sorted { $0.record.startedAt < $1.record.startedAt }
    }

    /// Whether the drive with this id is still pending.
    func contains(id: UUID) -> Bool {
        load().contains { $0.record.id == id }
    }

    /// Removes the entry of one drive: its upload succeeded.
    func remove(id: UUID) throws {
        try persist(load().filter { $0.record.id != id })
    }

    private static func defaultDirectory(fileManager: FileManager) -> URL {
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        // iOS sandboxes the app already; the subdirectory keeps the file
        // identifiable without depending on the host bundle id (tests run in
        // the app host but never use this default).
        return applicationSupport.appendingPathComponent("Drivy", isDirectory: true)
    }

    private func load() -> [PendingDriveUpload] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        // A corrupt file must never crash the recorder: the entries are lost,
        // but new drives can still be stored and uploaded. The atomic writes
        // make this unreachable in practice.
        return (try? JSONDecoder().decode([PendingDriveUpload].self, from: data)) ?? []
    }

    private func persist(_ entries: [PendingDriveUpload]) throws {
        let data = try JSONEncoder().encode(entries)
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        // Atomic: `Data` writes to a temporary file and moves it into place, so
        // a crash mid-write leaves the previous content untouched.
        try data.write(to: url, options: .atomic)
    }
}
