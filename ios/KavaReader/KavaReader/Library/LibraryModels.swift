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
