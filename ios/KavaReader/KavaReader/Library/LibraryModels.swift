import Foundation

// SeriesInfo 구조체 추가
struct SeriesInfo: Identifiable, Hashable, Decodable {
    let id: UUID
    let title: String
    let author: String
    let coverColorHexes: [String]
    let coverURL: URL?
}

extension SeriesInfo {
    func toLibrarySeries() -> LibrarySeries {
        return LibrarySeries(
            id: self.id,
            title: self.title,
            author: self.author,
            coverColorHexes: self.coverColorHexes,
            coverURL: self.coverURL
        )
    }
}

struct LibrarySeries: Identifiable, Hashable {
    // MARK: Lifecycle

    init(id: UUID = UUID(), title: String, author: String, coverColorHexes: [String], coverURL: URL? = nil) {
        self.id = id
        self.title = title
        self.author = author
        self.coverColorHexes = coverColorHexes
        self.coverURL = coverURL
    }

    // MARK: Internal

    let id: UUID
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
         lastReadPage: Int? = nil)
    {
        self.id = id
        self.title = title
        self.number = number
        self.pageCount = pageCount
        self.lastReadPage = lastReadPage
    }

    // MARK: Internal

    let id: UUID
    let title: String
    let number: Double
    let pageCount: Int
    let lastReadPage: Int?
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
        LibrarySeries(id: id ?? UUID(), title: title, author: author, coverColorHexes: coverColorHexes, coverURL: coverURL)
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
