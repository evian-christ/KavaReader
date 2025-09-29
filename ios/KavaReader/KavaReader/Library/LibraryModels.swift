import Foundation

// SeriesInfo 구조체 추가
struct SeriesInfo: Identifiable, Hashable, Decodable {
    let id: UUID
    let kavitaSeriesId: Int?
    let title: String
    let author: String
    let coverColorHexes: [String]
    let coverURL: URL?
}

extension SeriesInfo {
    func toLibrarySeries() -> LibrarySeries {
        return LibrarySeries(
            id: self.id,
            kavitaSeriesId: self.kavitaSeriesId,
            title: self.title,
            author: self.author,
            coverColorHexes: self.coverColorHexes,
            coverURL: self.coverURL
        )
    }
}

struct LibrarySeries: Identifiable, Hashable {
    // MARK: Lifecycle

    init(id: UUID = UUID(), kavitaSeriesId: Int? = nil, title: String, author: String, coverColorHexes: [String], coverURL: URL? = nil) {
        self.id = id
        self.kavitaSeriesId = kavitaSeriesId
        self.title = title
        self.author = author
        self.coverColorHexes = coverColorHexes
        self.coverURL = coverURL
    }

    // MARK: Internal

    let id: UUID
    let kavitaSeriesId: Int? // Store the actual Kavita series ID
    let title: String
    let author: String
    let coverColorHexes: [String]
    let coverURL: URL?
}

struct LibrarySection: Identifiable, Hashable, Decodable {
    let id: UUID
    let title: String
    let items: [SeriesInfo]
    
    var series: [LibrarySeries] {
        return items.map { $0.toLibrarySeries() }
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case title
        case items
    }
    
    // Hashable 프로토콜 준수를 위한 구현
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(title)
        hasher.combine(items)
    }
    
    // Equatable 프로토콜 준수를 위한 구현
    static func == (lhs: LibrarySection, rhs: LibrarySection) -> Bool {
        lhs.id == rhs.id &&
        lhs.title == rhs.title &&
        lhs.items == rhs.items
    }
    
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
}

struct SeriesDetail: Identifiable, Hashable {
    // MARK: Lifecycle

    init(id: UUID,
         title: String,
         author: String,
         summary: String,
         coverImageURL: URL?,
         chapters: [SeriesChapter])
    {
        self.id = id
        self.title = title
        self.author = author
        self.summary = summary
        self.coverImageURL = coverImageURL
        self.chapters = chapters
    }

    // MARK: Internal

    let id: UUID
    let title: String
    let author: String
    let summary: String
    let coverImageURL: URL?
    let chapters: [SeriesChapter]
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
         coverImageURL: URL? = nil)
    {
        self.id = id
        self.title = title
        self.number = number
        self.pageCount = pageCount
        self.lastReadPage = lastReadPage
        self.kavitaVolumeId = kavitaVolumeId
        self.kavitaChapterId = kavitaChapterId
        self.coverImageURL = coverImageURL
    }

    // MARK: Internal

    let id: UUID
    let title: String
    let number: Double
    let pageCount: Int
    let lastReadPage: Int?
    let kavitaVolumeId: Int? // Store Kavita volume ID for API calls
    let kavitaChapterId: Int? // Store Kavita chapter ID for page images
    let coverImageURL: URL? // Volume cover image URL
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
            SeriesInfo(
                id: dto.id ?? UUID(),
                kavitaSeriesId: dto.kavitaSeriesId,
                title: dto.title,
                author: dto.author,
                coverColorHexes: dto.coverColorHexes,
                coverURL: dto.coverURL
            )
        }
        
        return LibrarySection(
            id: id ?? UUID(),
            title: title,
            items: seriesInfoItems
        )
    }
}

extension LibrarySeriesDTO {
    func toDomain() -> LibrarySeries {
        LibrarySeries(id: id ?? UUID(), kavitaSeriesId: kavitaSeriesId, title: title, author: author, coverColorHexes: coverColorHexes, coverURL: coverURL)
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
    let title: String
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
    let id = UUID()
    let series: LibrarySeries
    let lastReadChapter: SeriesChapter
    let progress: ProgressDto

    var progressPercentage: Double {
        guard lastReadChapter.pageCount > 0 else { return 0 }
        return Double(progress.pageNum) / Double(lastReadChapter.pageCount)
    }

    var progressText: String {
        return "\(progress.pageNum) / \(lastReadChapter.pageCount) 페이지"
    }

    // MARK: - Hashable Conformance

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(series)
        hasher.combine(lastReadChapter)
        hasher.combine(progress.seriesId)
        hasher.combine(progress.chapterId)
        hasher.combine(progress.pageNum)
    }

    static func == (lhs: ContinueReadingItem, rhs: ContinueReadingItem) -> Bool {
        lhs.id == rhs.id &&
        lhs.series == rhs.series &&
        lhs.lastReadChapter == rhs.lastReadChapter &&
        lhs.progress.seriesId == rhs.progress.seriesId &&
        lhs.progress.chapterId == rhs.progress.chapterId &&
        lhs.progress.pageNum == rhs.progress.pageNum
    }
}
