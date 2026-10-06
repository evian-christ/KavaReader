import CryptoKit
import Foundation

/// Chapter metadata only. URLs can contain API keys, so rebuild them when loading.
struct ChapterCatalogSnapshot: Codable {
    let title: String
    let author: String
    let summary: String
    let chapters: [ChapterRecord]
    let libraryId: Int?
    let schemaVersion: Int?

    init(detail: SeriesDetail) {
        title = detail.title
        author = detail.author
        summary = detail.summary
        chapters = detail.chapters.map(ChapterRecord.init)
        libraryId = detail.libraryId
        schemaVersion = 2
    }

    func detail(seriesId: Int, baseURL: URL?, apiKey: String) -> SeriesDetail {
        var coverQuery = [URLQueryItem(name: "seriesId", value: String(seriesId))]
        if !apiKey.isEmpty { coverQuery.append(URLQueryItem(name: "apiKey", value: apiKey)) }
        let coverURL = baseURL?.appendingPathComponent("api/image/series-cover")
            .appendingQueryItems(coverQuery)
        return SeriesDetail(id: UUID(), title: title, author: author, summary: summary,
                            coverImageURL: coverURL,
                            chapters: chapters.map { $0.toDomain(baseURL: baseURL, apiKey: apiKey) },
                            libraryId: libraryId)
    }
}

struct ChapterRecord: Codable {
    let id: UUID
    let title: String
    let number: Double
    let pageCount: Int
    let lastReadPage: Int?
    let kavitaVolumeId: Int?
    let kavitaChapterId: Int?
    let isSpecial: Bool?

    init(_ chapter: SeriesChapter) {
        id = chapter.id
        title = chapter.title
        number = chapter.number
        pageCount = chapter.pageCount
        lastReadPage = chapter.lastReadPage
        kavitaVolumeId = chapter.kavitaVolumeId
        kavitaChapterId = chapter.kavitaChapterId
        isSpecial = chapter.isSpecial
    }

    func toDomain(baseURL: URL?, apiKey: String) -> SeriesChapter {
        let coverURL = kavitaChapterId.flatMap { chapterId in
            var coverQuery = [URLQueryItem(name: "chapterId", value: String(chapterId))]
            if !apiKey.isEmpty { coverQuery.append(URLQueryItem(name: "apiKey", value: apiKey)) }
            return baseURL?.appendingPathComponent("api/image/chapter-cover")
                .appendingQueryItems(coverQuery)
        }
        return SeriesChapter(id: id, title: title, number: number, pageCount: pageCount,
                             lastReadPage: lastReadPage, kavitaVolumeId: kavitaVolumeId,
                             kavitaChapterId: kavitaChapterId, coverImageURL: coverURL,
                             isSpecial: isSpecial ?? false)
    }
}

actor ChapterCatalogStore {
    static let shared = ChapterCatalogStore()

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("KavaReader/ChapterCatalog", isDirectory: true)
    }

    func load(identity: String, seriesId: Int, baseURL: URL?, apiKey: String) -> SeriesDetail? {
        guard let data = try? Data(contentsOf: fileURL(identity: identity, seriesId: seriesId)),
              let snapshot = try? JSONDecoder().decode(ChapterCatalogSnapshot.self, from: data),
              snapshot.schemaVersion == 2
        else { return nil }
        return snapshot.detail(seriesId: seriesId, baseURL: baseURL, apiKey: apiKey)
    }

    func save(_ detail: SeriesDetail, identity: String, seriesId: Int, generation expectedGeneration: Int) throws {
        guard generation == expectedGeneration else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(ChapterCatalogSnapshot(detail: detail))
            .write(to: fileURL(identity: identity, seriesId: seriesId), options: .atomic)
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

    private let directory: URL
    private var generation = 0

    private func fileURL(identity: String, seriesId: Int) -> URL {
        let value = "\(identity)|\(seriesId)"
        let hash = SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(hash + ".json")
    }
}
