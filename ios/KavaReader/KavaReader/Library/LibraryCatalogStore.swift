import CryptoKit
import Foundation

/// A durable catalog snapshot. Cover URLs are rebuilt at display time so API keys
/// embedded in image URLs are never written to the catalog file.
struct LibraryCatalogSnapshot: Codable {
    static let currentSchemaVersion = 6

    let sections: [CatalogSection]
    let continueReading: [CatalogContinueItem]
    let savedAt: Date
    let schemaVersion: Int?

    init(sections: [LibrarySection], continueReading: [ContinueReadingItem]) {
        self.sections = sections.map { section in
            CatalogSection(title: section.title, series: section.items.compactMap { CatalogSeries($0) })
        }
        self.continueReading = continueReading.compactMap(CatalogContinueItem.init)
        savedAt = Date()
        schemaVersion = Self.currentSchemaVersion
    }

    init(snapshot: Self, continueReading: [CatalogContinueItem]) {
        sections = snapshot.sections
        self.continueReading = continueReading
        savedAt = snapshot.savedAt
        schemaVersion = snapshot.schemaVersion
    }

    func replacingContinueReading(_ items: [ContinueReadingItem]) -> Self {
        Self(snapshot: self, continueReading: items.compactMap(CatalogContinueItem.init))
    }

    func domainSections(baseURL: URL?, apiKey: String) -> [LibrarySection] {
        sections.map { section in
            let items = section.series.map { $0.toSeriesInfo(baseURL: baseURL, apiKey: apiKey) }
            let title = section.title == "읽고 있는 만화" ? "읽는 중" : section.title
            return LibrarySection(id: stableCatalogUUID("section|\(title)"), title: title, items: items)
        }
    }

    func domainContinueReading(baseURL: URL?, apiKey: String) -> [ContinueReadingItem] {
        continueReading.map { $0.toDomain(baseURL: baseURL, apiKey: apiKey) }
    }
}

struct CatalogSection: Codable {
    let title: String
    let series: [CatalogSeries]
}

struct CatalogSeries: Codable {
    let kavitaSeriesId: Int
    let title: String
    let author: String
    let coverColorHexes: [String]
    let isRead: Bool?
    let totalPages: Int?
    let pagesRead: Int?

    init?(_ series: SeriesInfo) {
        guard let id = series.kavitaSeriesId else { return nil }
        kavitaSeriesId = id
        title = series.title
        author = series.author
        coverColorHexes = series.coverColorHexes
        isRead = series.isRead
        totalPages = series.totalPages
        pagesRead = series.pagesRead
    }

    init?(_ series: LibrarySeries) {
        guard let id = series.kavitaSeriesId else { return nil }
        kavitaSeriesId = id
        title = series.title
        author = series.author
        coverColorHexes = series.coverColorHexes
        isRead = series.isRead
        totalPages = series.totalPages
        pagesRead = series.pagesRead
    }

    func toSeriesInfo(baseURL: URL?, apiKey: String) -> SeriesInfo {
        SeriesInfo(id: stableCatalogUUID("series|\(kavitaSeriesId)"), kavitaSeriesId: kavitaSeriesId,
                   title: title, author: author, coverColorHexes: coverColorHexes,
                   coverURL: coverURL(baseURL: baseURL, apiKey: apiKey), isRead: isRead ?? false,
                   totalPages: totalPages, pagesRead: pagesRead)
    }

    func toLibrarySeries(baseURL: URL?, apiKey: String) -> LibrarySeries {
        toSeriesInfo(baseURL: baseURL, apiKey: apiKey).toLibrarySeries()
    }

    private func coverURL(baseURL: URL?, apiKey: String) -> URL? {
        guard let baseURL, !apiKey.isEmpty else { return nil }
        return baseURL.appendingPathComponent("api/image/series-cover")
            .appendingQueryItems([
                URLQueryItem(name: "seriesId", value: String(kavitaSeriesId)),
                URLQueryItem(name: "apiKey", value: apiKey),
            ])
    }
}

struct CatalogContinueItem: Codable {
    let series: CatalogSeries
    let chapterTitle: String
    let chapterNumber: Double
    let pageCount: Int
    let lastReadPage: Int?
    let kavitaVolumeId: Int?
    let kavitaChapterId: Int?
    let progress: ProgressDto

    init?(_ item: ContinueReadingItem) {
        guard let series = CatalogSeries(item.series) else { return nil }
        self.series = series
        chapterTitle = item.lastReadChapter.title
        chapterNumber = item.lastReadChapter.number
        pageCount = item.lastReadChapter.pageCount
        lastReadPage = item.lastReadChapter.lastReadPage
        kavitaVolumeId = item.lastReadChapter.kavitaVolumeId
        kavitaChapterId = item.lastReadChapter.kavitaChapterId
        progress = item.progress
    }

    func toDomain(baseURL: URL?, apiKey: String) -> ContinueReadingItem {
        let chapter = SeriesChapter(id: stableCatalogUUID("chapter|\(kavitaChapterId ?? 0)|\(series.kavitaSeriesId)"),
                                    title: chapterTitle, number: chapterNumber, pageCount: pageCount,
                                    lastReadPage: lastReadPage, kavitaVolumeId: kavitaVolumeId,
                                    kavitaChapterId: kavitaChapterId)
        return ContinueReadingItem(series: series.toLibrarySeries(baseURL: baseURL, apiKey: apiKey),
                                   lastReadChapter: chapter, progress: progress)
    }
}

nonisolated func stableCatalogUUID(_ value: String) -> UUID {
    let bytes = Array(SHA256.hash(data: Data(value.utf8)).prefix(16))
    return UUID(uuid: uuid_t(bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                             bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
}

actor LibraryCatalogStore {
    static let shared = LibraryCatalogStore()

    private let directory: URL

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("KavaReader/LibraryCatalog", isDirectory: true)
    }

    func load(identity: String) -> LibraryCatalogSnapshot? {
        guard let data = try? Data(contentsOf: fileURL(for: identity)) else { return nil }
        guard let snapshot = try? JSONDecoder().decode(LibraryCatalogSnapshot.self, from: data) else { return nil }
        if let data = try? Data(contentsOf: continueReadingURL(for: identity)),
           let items = try? JSONDecoder().decode([CatalogContinueItem].self, from: data) {
            return LibraryCatalogSnapshot(snapshot: snapshot, continueReading: items)
        }
        return snapshot
    }

    func save(_ snapshot: LibraryCatalogSnapshot, identity: String, generation expectedGeneration: Int) throws {
        guard generation == expectedGeneration else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(snapshot).write(to: fileURL(for: identity), options: .atomic)
        try saveContinueReading(snapshot.continueReading, identity: identity, generation: expectedGeneration)
    }

    /// Reading activity updates a small overlay, rather than rewriting the entire catalog per page.
    func saveContinueReading(_ items: [CatalogContinueItem], identity: String, generation expectedGeneration: Int) throws {
        guard generation == expectedGeneration else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(items).write(to: continueReadingURL(for: identity), options: .atomic)
    }

    func sizeInBytes() -> Int64 {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])
        else { return 0 }
        return files.reduce(0) { total, file in
            let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return total + Int64(size)
        }
    }

    func clear() throws {
        generation += 1
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }

    func currentGeneration() -> Int { generation }

    private var generation = 0

    private func fileURL(for identity: String) -> URL {
        let hash = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(hash + ".json")
    }

    private func continueReadingURL(for identity: String) -> URL {
        fileURL(for: identity).deletingPathExtension().appendingPathExtension("continue.json")
    }
}
