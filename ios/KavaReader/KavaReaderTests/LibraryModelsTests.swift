import Foundation
@testable import KavaReader
import XCTest

@MainActor
final class LibraryModelsTests: XCTestCase {
    func testSeriesInfoToLibrarySeries() {
        // Given
        let id = UUID()
        let seriesInfo = SeriesInfo(id: id,
                                    kavitaSeriesId: 123,
                                    title: "Test Series",
                                    author: "Test Author",
                                    coverColorHexes: ["#FF0000", "#00FF00"],
                                    coverURL: URL(string: "https://example.com/cover.jpg"))

        // When
        let librarySeries = seriesInfo.toLibrarySeries()

        // Then
        XCTAssertEqual(librarySeries.id, id)
        XCTAssertEqual(librarySeries.kavitaSeriesId, 123)
        XCTAssertEqual(librarySeries.title, "Test Series")
        XCTAssertEqual(librarySeries.author, "Test Author")
        XCTAssertEqual(librarySeries.coverColorHexes, ["#FF0000", "#00FF00"])
        XCTAssertEqual(librarySeries.coverURL, URL(string: "https://example.com/cover.jpg"))
    }

    func testLibrarySeriesInit() {
        // Given
        let kavitaSeriesId = 456
        let title = "Another Test Series"
        let author = "Another Author"
        let colors = ["#0000FF", "#FFFF00"]
        let coverURL = URL(string: "https://example.com/another-cover.jpg")

        // When
        let librarySeries = LibrarySeries(kavitaSeriesId: kavitaSeriesId,
                                          title: title,
                                          author: author,
                                          coverColorHexes: colors,
                                          coverURL: coverURL)

        // Then
        XCTAssertNotNil(librarySeries.id) // UUID should be generated
        XCTAssertEqual(librarySeries.kavitaSeriesId, kavitaSeriesId)
        XCTAssertEqual(librarySeries.title, title)
        XCTAssertEqual(librarySeries.author, author)
        XCTAssertEqual(librarySeries.coverColorHexes, colors)
        XCTAssertEqual(librarySeries.coverURL, coverURL)
    }

    func testLibrarySectionWithSeriesConversion() {
        // Given
        let seriesInfo1 = SeriesInfo(id: UUID(),
                                     kavitaSeriesId: 1,
                                     title: "Series 1",
                                     author: "Author 1",
                                     coverColorHexes: ["#FF0000"],
                                     coverURL: nil)

        let seriesInfo2 = SeriesInfo(id: UUID(),
                                     kavitaSeriesId: 2,
                                     title: "Series 2",
                                     author: "Author 2",
                                     coverColorHexes: ["#00FF00"],
                                     coverURL: nil)

        let section = LibrarySection(id: UUID(),
                                     title: "Test Section",
                                     items: [seriesInfo1, seriesInfo2])

        // When
        let series = section.series

        // Then
        XCTAssertEqual(series.count, 2)
        XCTAssertEqual(series[0].title, "Series 1")
        XCTAssertEqual(series[1].title, "Series 2")
        XCTAssertEqual(series[0].kavitaSeriesId, 1)
        XCTAssertEqual(series[1].kavitaSeriesId, 2)
    }

    func testSeriesChapterInit() {
        // Given
        let id = UUID()
        let title = "Chapter 1"
        let number = 1.5
        let pageCount = 20
        let lastReadPage = 10
        let kavitaVolumeId = 100
        let kavitaChapterId = 200
        let coverURL = URL(string: "https://example.com/chapter-cover.jpg")

        // When
        let chapter = SeriesChapter(id: id,
                                    title: title,
                                    number: number,
                                    pageCount: pageCount,
                                    lastReadPage: lastReadPage,
                                    kavitaVolumeId: kavitaVolumeId,
                                    kavitaChapterId: kavitaChapterId,
                                    coverImageURL: coverURL)

        // Then
        XCTAssertEqual(chapter.id, id)
        XCTAssertEqual(chapter.title, title)
        XCTAssertEqual(chapter.number, number)
        XCTAssertEqual(chapter.pageCount, pageCount)
        XCTAssertEqual(chapter.lastReadPage, lastReadPage)
        XCTAssertEqual(chapter.kavitaVolumeId, kavitaVolumeId)
        XCTAssertEqual(chapter.kavitaChapterId, kavitaChapterId)
        XCTAssertEqual(chapter.coverImageURL, coverURL)
    }

    func testSeriesDetailInit() {
        // Given
        let id = UUID()
        let title = "Test Series Detail"
        let author = "Detail Author"
        let summary = "This is a test summary"
        let coverURL = URL(string: "https://example.com/detail-cover.jpg")

        let chapter1 = SeriesChapter(id: UUID(),
                                     title: "Chapter 1",
                                     number: 1.0,
                                     pageCount: 20)

        let chapter2 = SeriesChapter(id: UUID(),
                                     title: "Chapter 2",
                                     number: 2.0,
                                     pageCount: 25)

        let chapters = [chapter1, chapter2]

        // When
        let seriesDetail = SeriesDetail(id: id,
                                        title: title,
                                        author: author,
                                        summary: summary,
                                        coverImageURL: coverURL,
                                        chapters: chapters)

        // Then
        XCTAssertEqual(seriesDetail.id, id)
        XCTAssertEqual(seriesDetail.title, title)
        XCTAssertEqual(seriesDetail.author, author)
        XCTAssertEqual(seriesDetail.summary, summary)
        XCTAssertEqual(seriesDetail.coverImageURL, coverURL)
        XCTAssertEqual(seriesDetail.chapters.count, 2)
        XCTAssertEqual(seriesDetail.chapters[0].title, "Chapter 1")
        XCTAssertEqual(seriesDetail.chapters[1].title, "Chapter 2")
    }

    func testLibrarySectionEquality() {
        // Given
        let id = UUID()
        let seriesInfo = SeriesInfo(id: UUID(),
                                    kavitaSeriesId: 1,
                                    title: "Test",
                                    author: "Author",
                                    coverColorHexes: ["#FF0000"],
                                    coverURL: nil)

        let section1 = LibrarySection(id: id, title: "Section", items: [seriesInfo])
        let section2 = LibrarySection(id: id, title: "Section", items: [seriesInfo])
        let section3 = LibrarySection(id: UUID(), title: "Section", items: [seriesInfo])

        // When & Then
        XCTAssertEqual(section1, section2)
        XCTAssertNotEqual(section1, section3)
    }

    func testLibrarySectionHashing() {
        // Given
        let id = UUID()
        let seriesInfo = SeriesInfo(id: UUID(),
                                    kavitaSeriesId: 1,
                                    title: "Test",
                                    author: "Author",
                                    coverColorHexes: ["#FF0000"],
                                    coverURL: nil)

        let section1 = LibrarySection(id: id, title: "Section", items: [seriesInfo])
        let section2 = LibrarySection(id: id, title: "Section", items: [seriesInfo])

        // When
        var hasher1 = Hasher()
        section1.hash(into: &hasher1)
        let hash1 = hasher1.finalize()

        var hasher2 = Hasher()
        section2.hash(into: &hasher2)
        let hash2 = hasher2.finalize()

        // Then
        XCTAssertEqual(hash1, hash2)
    }
}
