import Foundation

struct LibrarySeries: Identifiable, Hashable {
    // MARK: Lifecycle

    init(id: UUID = UUID(), title: String, author: String, coverColorHexes: [String]) {
        self.id = id
        self.title = title
        self.author = author
        self.coverColorHexes = coverColorHexes
    }

    // MARK: Internal

    let id: UUID
    let title: String
    let author: String
    let coverColorHexes: [String]
}

struct LibrarySection: Identifiable, Hashable {
    // MARK: Lifecycle

    init(id: UUID = UUID(), title: String, items: [LibrarySeries]) {
        self.id = id
        self.title = title
        self.items = items
    }

    // MARK: Internal

    let id: UUID
    let title: String
    let items: [LibrarySeries]
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
        LibrarySection(id: id ?? UUID(), title: title, items: items.map { $0.toDomain() })
    }
}

extension LibrarySeriesDTO {
    func toDomain() -> LibrarySeries {
        LibrarySeries(id: id ?? UUID(), title: title, author: author, coverColorHexes: coverColorHexes)
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
