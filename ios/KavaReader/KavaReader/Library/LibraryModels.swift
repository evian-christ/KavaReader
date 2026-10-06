import Foundation

// SeriesInfo 구조체 추가
struct SeriesInfo: Identifiable, Hashable, Decodable {
    init(id: UUID, kavitaSeriesId: Int?, title: String, author: String,
         coverColorHexes: [String], coverURL: URL?, isRead: Bool = false, totalPages: Int? = nil, pagesRead: Int? = nil, isLocal: Bool = false)
    {
        self.id = id
        self.kavitaSeriesId = kavitaSeriesId
        self.title = title
        self.author = author
        self.coverColorHexes = coverColorHexes
        self.coverURL = coverURL
        self.isRead = isRead
        self.totalPages = totalPages
        self.pagesRead = pagesRead
        self.isLocal = isLocal
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        kavitaSeriesId = try container.decodeIfPresent(Int.self, forKey: .kavitaSeriesId)
        title = try container.decode(String.self, forKey: .title)
        author = try container.decode(String.self, forKey: .author)
        coverColorHexes = try container.decode([String].self, forKey: .coverColorHexes)
        coverURL = try container.decodeIfPresent(URL.self, forKey: .coverURL)
        isRead = try container.decodeIfPresent(Bool.self, forKey: .isRead) ?? false
        totalPages = try container.decodeIfPresent(Int.self, forKey: .totalPages)
        pagesRead = try container.decodeIfPresent(Int.self, forKey: .pagesRead)
        isLocal = try container.decodeIfPresent(Bool.self, forKey: .isLocal) ?? false
    }

    private enum CodingKeys: String, CodingKey {
        case id, kavitaSeriesId, title, author, coverColorHexes, coverURL, isRead, totalPages, pagesRead, isLocal
    }

    let id: UUID
    let kavitaSeriesId: Int?
    let title: String
    let author: String
    let coverColorHexes: [String]
    let coverURL: URL?
    let isRead: Bool
    let totalPages: Int?
    let pagesRead: Int?
    let isLocal: Bool
}

extension SeriesInfo {
    func toLibrarySeries() -> LibrarySeries {
        return LibrarySeries(id: id,
                             kavitaSeriesId: kavitaSeriesId,
                             title: title,
                             author: author,
                             coverColorHexes: coverColorHexes,
                             coverURL: coverURL,
                             isRead: isRead, totalPages: totalPages, pagesRead: pagesRead, isLocal: isLocal)
    }
}

struct LibrarySeries: Identifiable, Hashable {
    // MARK: Lifecycle

    init(id: UUID = UUID(), kavitaSeriesId: Int? = nil, title: String, author: String, coverColorHexes: [String],
         coverURL: URL? = nil, isRead: Bool = false, totalPages: Int? = nil, pagesRead: Int? = nil, isLocal: Bool = false)
    {
        self.id = id
        self.kavitaSeriesId = kavitaSeriesId
        self.title = title
        self.author = author
        self.coverColorHexes = coverColorHexes
        self.coverURL = coverURL
        self.isRead = isRead
        self.totalPages = totalPages
        self.pagesRead = pagesRead
        self.isLocal = isLocal
    }

    // MARK: Internal

    let id: UUID
    let kavitaSeriesId: Int? // Store the actual Kavita series ID
    let title: String
    let author: String
    let coverColorHexes: [String]
    let coverURL: URL?
    let isRead: Bool
    let totalPages: Int?
    let pagesRead: Int?
    let isLocal: Bool
}

struct LibrarySection: Identifiable, Hashable, Decodable {
    // MARK: Lifecycle

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        items = try container.decode([SeriesInfo].self, forKey: .items)
    }

    // 기본 생성자 추가
    init(id: UUID, title: String, items: [SeriesInfo]) {
        self.id = id
        self.title = title
        self.items = items
    }

    // MARK: Internal

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case items
    }

    let id: UUID
    let title: String
    let items: [SeriesInfo]

    var series: [LibrarySeries] {
        return items.map { $0.toLibrarySeries() }
    }

    // Equatable 프로토콜 준수를 위한 구현
    static func == (lhs: LibrarySection, rhs: LibrarySection) -> Bool {
        lhs.id == rhs.id &&
            lhs.title == rhs.title &&
            lhs.items == rhs.items
    }

    // Hashable 프로토콜 준수를 위한 구현
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(title)
        hasher.combine(items)
    }
}

struct SeriesDetail: Identifiable, Hashable {
    // MARK: Lifecycle

    init(id: UUID,
         title: String,
         author: String,
         summary: String,
         coverImageURL: URL?,
         chapters: [SeriesChapter],
         libraryId: Int? = nil)
    {
        self.id = id
        self.title = title
        self.author = author
        self.summary = summary
        self.coverImageURL = coverImageURL
        self.chapters = chapters
        self.libraryId = libraryId
    }

    // MARK: Internal

    let id: UUID
    let title: String
    let author: String
    let summary: String
    let coverImageURL: URL?
    let chapters: [SeriesChapter]
    let libraryId: Int?
}

struct SeriesChapter: Identifiable, Hashable {
    // MARK: Lifecycle

    init(id: UUID,
         title: String,
         number: Double,
         pageCount: Int,
         lastReadPage: Int? = nil,
         kavitaVolumeId: Int? = nil,
         kavitaChapterId: Int? = nil,
         coverImageURL: URL? = nil,
         isSpecial: Bool = false, isEpub: Bool = false)
    {
        self.id = id
        self.title = title
        self.number = number
        self.pageCount = pageCount
        self.lastReadPage = lastReadPage
        self.kavitaVolumeId = kavitaVolumeId
        self.kavitaChapterId = kavitaChapterId
        self.coverImageURL = coverImageURL
        self.isSpecial = isSpecial
        self.isEpub = isEpub
    }

    // MARK: Internal

    let id: UUID
    let title: String
    let number: Double
    let pageCount: Int
    let lastReadPage: Int?
    let kavitaVolumeId: Int? // Store Kavita volume ID for API calls
    let kavitaChapterId: Int? // Store Kavita chapter ID for page images
    let coverImageURL: URL? // Chapter cover image URL
    let isSpecial: Bool
    let isEpub: Bool
}

struct LibrarySectionsResponse: Decodable {
    let sections: [LibrarySectionDTO]
}

struct LibrarySectionDTO: Decodable {
    let id: UUID?
    let title: String
    let items: [LibrarySeriesDTO]
}

struct LibrarySeriesDTO: Decodable {
    let id: UUID?
    let kavitaSeriesId: Int?
    let title: String
    let author: String
    let coverColorHexes: [String]
    let coverURL: URL?
}

struct SeriesDetailResponse: Decodable {
    let series: SeriesDetailDTO
}

struct SeriesDetailDTO: Decodable {
    let id: UUID
    let title: String
    let author: String
    let summary: String
    let coverImageUrl: URL?
    let chapters: [SeriesChapterDTO]
}

struct SeriesChapterDTO: Decodable {
    let id: UUID
    let title: String
    let number: Double
    let pageCount: Int
    let lastReadPage: Int?
}

extension LibrarySectionDTO {
    func toDomain() -> LibrarySection {
        // items를 SeriesInfo 배열로 변환
        let seriesInfoItems = items.map { dto -> SeriesInfo in
            SeriesInfo(id: dto.id ?? UUID(),
                       kavitaSeriesId: dto.kavitaSeriesId,
                       title: dto.title,
                       author: dto.author,
                       coverColorHexes: dto.coverColorHexes,
                       coverURL: dto.coverURL)
        }

        return LibrarySection(id: id ?? UUID(),
                              title: title,
                              items: seriesInfoItems)
    }
}

extension LibrarySeriesDTO {
    func toDomain() -> LibrarySeries {
        LibrarySeries(id: id ?? UUID(), kavitaSeriesId: kavitaSeriesId, title: title, author: author,
                      coverColorHexes: coverColorHexes, coverURL: coverURL)
    }
}

extension SeriesDetailDTO {
    func toDomain() -> SeriesDetail {
        SeriesDetail(id: id,
                     title: title,
                     author: author,
                     summary: summary,
                     coverImageURL: coverImageUrl,
                     chapters: chapters.map { $0.toDomain() })
    }
}

extension SeriesChapterDTO {
    func toDomain() -> SeriesChapter {
        SeriesChapter(id: id,
                      title: title,
                      number: number,
                      pageCount: pageCount,
                      lastReadPage: lastReadPage)
    }
}

// MARK: - Reading Progress Models

struct ProgressDto: Codable, Hashable {
    let volumeId: Int
    let chapterId: Int
    let pageNum: Int
    let seriesId: Int
    let libraryId: Int
    let bookScrollId: String?
    let lastModifiedUtc: String
}

struct ProgressUpdateRequest: Codable {
    let volumeId: Int
    let chapterId: Int
    let pageNum: Int
    let seriesId: Int
    let libraryId: Int
    let bookScrollId: String?
}

struct ContinuePointDto: Codable {
    let id: Int
    let volumeId: Int
    let pagesRead: Int
    let title: String?
    let pages: Int

    // 편의 속성들
    var chapterId: Int { return id }
    var pageNum: Int { return pagesRead }
}

struct ReadingProgressResponse: Codable {
    let progress: ProgressDto?
    let success: Bool
    let message: String?
}

// MARK: - Continue Reading Models

struct ContinueReadingItem: Identifiable, Hashable {
    let id: UUID
    let series: LibrarySeries
    let lastReadChapter: SeriesChapter
    let progress: ProgressDto
    let source: ContinueReadingSource?
    let remoteSeriesID: String?

    init(series: LibrarySeries, lastReadChapter: SeriesChapter, progress: ProgressDto,
         source: ContinueReadingSource? = nil, remoteSeriesID: String? = nil) {
        self.series = series
        self.lastReadChapter = lastReadChapter
        self.progress = progress
        self.source = source
        self.remoteSeriesID = remoteSeriesID
        let seriesID = remoteSeriesID ?? series.kavitaSeriesId.map { String($0) } ?? series.id.uuidString
        id = source.map { stableCatalogUUID("continue|\($0.id)|\(seriesID)") } ?? series.id
    }

    func withSource(_ source: ContinueReadingSource, remoteSeriesID: String? = nil) -> Self {
        Self(series: series, lastReadChapter: lastReadChapter, progress: progress,
             source: source, remoteSeriesID: remoteSeriesID ?? self.remoteSeriesID)
    }

    func withReadDate(_ date: Date) -> Self {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return Self(series: series, lastReadChapter: lastReadChapter,
                    progress: ProgressDto(volumeId: progress.volumeId, chapterId: progress.chapterId,
                                          pageNum: progress.pageNum, seriesId: progress.seriesId,
                                          libraryId: progress.libraryId, bookScrollId: progress.bookScrollId,
                                          lastModifiedUtc: formatter.string(from: date)), source: source,
                    remoteSeriesID: remoteSeriesID)
    }

    static func sortedByLastRead(_ items: [ContinueReadingItem]) -> [ContinueReadingItem] {
        let formatter = ISO8601DateFormatter()
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        // Kavita may omit the timezone suffix on UTC timestamps.
        let datedItems = items.enumerated().map { index, item in
            let value = item.progress.lastModifiedUtc.trimmingCharacters(in: .whitespacesAndNewlines)
            let time = value.split(separator: "T").last ?? ""
            let hasTimezone = time.hasSuffix("Z") || time.contains("+") || time.contains("-")
            let timestamp = hasTimezone ? value : value + "Z"
            let date = fractionalFormatter.date(from: timestamp) ?? formatter.date(from: timestamp) ?? .distantPast
            return (index: index, item: item, date: date)
        }
        return datedItems.sorted {
            if $0.date != $1.date { return $0.date > $1.date }
            return $0.index < $1.index
        }.map(\.item)
    }

    var progressPercentage: Double {
        guard lastReadChapter.pageCount > 0 else { return 0 }
        return Double(progress.pageNum) / Double(lastReadChapter.pageCount)
    }

    var progressText: String {
        if lastReadChapter.isEpub { return AppLocalization.format("%d%% 읽음", Int(progressPercentage * 100)) }
        return AppLocalization.format("%d / %d 페이지", progress.pageNum, lastReadChapter.pageCount)
    }

    static func == (lhs: ContinueReadingItem, rhs: ContinueReadingItem) -> Bool {
        lhs.id == rhs.id &&
            lhs.series == rhs.series &&
            lhs.lastReadChapter == rhs.lastReadChapter &&
            lhs.progress.seriesId == rhs.progress.seriesId &&
            lhs.progress.chapterId == rhs.progress.chapterId &&
            lhs.progress.pageNum == rhs.progress.pageNum &&
            lhs.progress.lastModifiedUtc == rhs.progress.lastModifiedUtc
    }

    // MARK: - Hashable Conformance

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(series)
        hasher.combine(lastReadChapter)
        hasher.combine(progress.seriesId)
        hasher.combine(progress.chapterId)
        hasher.combine(progress.pageNum)
        hasher.combine(progress.lastModifiedUtc)
    }
}
