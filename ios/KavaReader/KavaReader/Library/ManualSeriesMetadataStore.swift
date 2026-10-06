import CryptoKit
import Foundation

/// A record with nil metadata explicitly disables automatic linking for this work.
/// User choices have no title-based expiry and are separate from lookup caches.
nonisolated struct ManualSeriesMetadataRecord: Codable, Sendable {
    let metadata: ExternalSeriesMetadata?
    let updatedAt: Date
}

extension Notification.Name {
    static let seriesMetadataConnectionDidChange = Notification.Name("seriesMetadataConnectionDidChange")
}

actor ManualSeriesMetadataStore {
    // MARK: Lifecycle

    init(directory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("KavaReader/LibraryPlus", isDirectory: true))
    {
        self.directory = directory
    }

    // MARK: Internal

    static let shared = ManualSeriesMetadataStore()

    func load(identity: String) -> [Int: ManualSeriesMetadataRecord] {
        if let cached = cachedRecords[identity] { return cached }
        guard let data = try? Data(contentsOf: fileURL(identity)) else { return [:] }
        guard let records = try? JSONDecoder().decode([Int: ManualSeriesMetadataRecord].self, from: data)
        else { return [:] }
        cachedRecords[identity] = records
        return records
    }

    /// Removing a record restores automatic lookup; a nil-metadata record keeps it disabled.
    func set(_ record: ManualSeriesMetadataRecord?, identity: String, seriesID: Int) throws {
        let url = fileURL(identity)
        var records: [Int: ManualSeriesMetadataRecord] = [:]
        if FileManager.default.fileExists(atPath: url.path) {
            // Do not overwrite other user choices if an existing file cannot be read.
            records = try JSONDecoder().decode([Int: ManualSeriesMetadataRecord].self,
                                               from: Data(contentsOf: url))
        }
        records[seriesID] = record
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(records).write(to: url, options: .atomic)
        cachedRecords[identity] = records
    }

    // MARK: Private

    private let directory: URL
    private var cachedRecords: [String: [Int: ManualSeriesMetadataRecord]] = [:]

    private func fileURL(_ identity: String) -> URL {
        let hash = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(hash + "-manual-anilist.json")
    }
}
