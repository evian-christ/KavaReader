import Foundation

nonisolated struct LocalSeriesInformation: Sendable {
    let external: ExternalSeriesMetadata?
    let manual: ManualSeriesMetadataRecord?
}

private nonisolated struct LocalMetadataLookup: Codable, Sendable {
    let title: String
    let includeNovels: Bool
    let checkedAt: Date
    let match: ExternalSeriesMetadata?
    var alternateTitleSearchAttempted: Bool? = nil

    func isFresh(title: String, includeNovels: Bool? = nil, alternateSearchEnabled: Bool = false) -> Bool {
        if IndexingSettings.needsAlternateSearch(title: title, hasMatch: match != nil,
                                                 attempted: alternateTitleSearchAttempted,
                                                 enabled: alternateSearchEnabled) { return false }
        let lifetime: TimeInterval = match == nil ? 30 * 86400 : 365 * 86400
        return self.title == title && (includeNovels == nil || self.includeNovels == includeNovels) &&
            Date().timeIntervalSince(checkedAt) < lifetime
    }
}

private nonisolated struct LocalMetadataSnapshot: Codable, Sendable {
    var automatic: [UUID: LocalMetadataLookup] = [:]
    var manual: [UUID: ManualSeriesMetadataRecord] = [:]
    var blockedUntil: Date?
}

/// Stable local UUIDs have their own cache, independent of server accounts and integer Kavita IDs.
actor LocalSeriesMetadataStore {
    // MARK: Lifecycle

    init(directory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("KavaReader/LibraryPlus", isDirectory: true), session: URLSession = .shared)
    {
        url = directory.appendingPathComponent("local-files-metadata.json")
        self.session = session
        snapshot = LocalMetadataSnapshot()
        if FileManager.default.fileExists(atPath: url.path) {
            do { snapshot = try JSONDecoder().decode(LocalMetadataSnapshot.self, from: Data(contentsOf: url)) }
            catch { loadError = error }
        }
    }

    // MARK: Internal

    static let shared = LocalSeriesMetadataStore()
    nonisolated static let notificationIdentity = "local-files"

    func information(id: UUID, title: String) -> LocalSeriesInformation {
        let manual = snapshot.manual[id]
        let record = snapshot.automatic[id]
        return LocalSeriesInformation(external: manual != nil ? manual?.metadata :
            (record?.isFresh(title: title) == true ? record?.match : nil), manual: manual)
    }

    func set(_ record: ManualSeriesMetadataRecord?, id: UUID) throws {
        var updated = snapshot
        updated.manual[id] = record
        try save(updated)
        NotificationCenter.default.post(name: .seriesMetadataConnectionDidChange, object: Self.notificationIdentity)
    }

    /// Cached misses and manual choices are finished work, not pending network requests.
    func needsLookup(id: UUID, title: String, includeNovels: Bool) -> Bool {
        snapshot.manual[id] == nil && snapshot.automatic[id]?.isFresh(title: title, includeNovels: includeNovels,
                                                                      alternateSearchEnabled: IndexingSettings
                                                                          .alternateTitleSearchEnabled) != true
    }

    func lookup(id: UUID, title: String, includeNovels: Bool) async throws -> ExternalSeriesMetadata? {
        if let loadError { throw loadError }
        if let manual = snapshot.manual[id] { return manual.metadata }
        if let record = snapshot.automatic[id], record.isFresh(title: title, includeNovels: includeNovels,
                                                               alternateSearchEnabled: IndexingSettings
                                                                   .alternateTitleSearchEnabled)
        {
            return record.match
        }
        if let blocked = snapshot.blockedUntil, blocked > Date() {
            throw ExternalLookupError.rateLimited(blocked.timeIntervalSinceNow)
        }
        let wait = max(0, nextRequestAt.timeIntervalSinceNow)
        nextRequestAt = Date().addingTimeInterval(wait + 2.5)
        if wait > 0 { try await Task.sleep(for: .seconds(wait)) }
        try Task.checkCancellation()
        // Actor suspension may have allowed a manual connection or rate limit to change.
        if let manual = snapshot.manual[id] { return manual.metadata }
        if let blocked = snapshot.blockedUntil, blocked > Date() {
            throw ExternalLookupError.rateLimited(blocked.timeIntervalSinceNow)
        }
        do {
            let alternateSearch = IndexingSettings.alternateTitleSearchEnabled
            let match = try await AniListMetadataService(session: session, includeNovels: includeNovels)
                .lookup(title: title,
                        retryWithEnglishTitle: alternateSearch)
            nextRequestAt = max(nextRequestAt, Date().addingTimeInterval(2.5))
            try Task.checkCancellation()
            var updated = snapshot
            updated.automatic[id] = LocalMetadataLookup(title: title, includeNovels: includeNovels,
                                                        checkedAt: Date(), match: match,
                                                        alternateTitleSearchAttempted: alternateSearch)
            try save(updated)
            return snapshot.manual[id] != nil ? snapshot.manual[id]?.metadata : match
        } catch let ExternalLookupError.rateLimited(retryAfter) {
            var updated = snapshot
            updated.blockedUntil = Date().addingTimeInterval(retryAfter)
            try save(updated)
            throw ExternalLookupError.rateLimited(retryAfter)
        }
    }

    // MARK: Private

    private let url: URL
    private let session: URLSession
    private var snapshot: LocalMetadataSnapshot
    private var loadError: Error?
    private var nextRequestAt = Date.distantPast

    private func save(_ updated: LocalMetadataSnapshot) throws {
        if let loadError { throw loadError }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(updated).write(to: url, options: .atomic)
        snapshot = updated
    }
}
