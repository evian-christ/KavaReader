import Foundation
@testable import KavaReader
import XCTest

@MainActor
final class ContinueReadingCollectionTests: XCTestCase {
    private let kavita = ContinueReadingSource.server(kind: "kavita", identity: "test-server-account")
    private let komga = ContinueReadingSource.server(kind: "komga", identity: "test-server-account")

    private func item(_ title: String, id: Int = 1, timestamp: String = "2026-10-02T10:00:00Z",
                      local: Bool = false) -> ContinueReadingItem {
        ContinueReadingItem(series: LibrarySeries(kavitaSeriesId: local ? nil : id, title: title,
                                                  author: "", coverColorHexes: [], isLocal: local),
                            lastReadChapter: SeriesChapter(id: UUID(), title: "1", number: 1, pageCount: 20),
                            progress: ProgressDto(volumeId: 1, chapterId: 1, pageNum: 2, seriesId: id,
                                                  libraryId: 1, bookScrollId: nil, lastModifiedUtc: timestamp))
    }

    func testMergesSourcesChronologicallyWithoutIDCollision() {
        var collection = ContinueReadingCollection()
        collection.setCachedItems([item("Kavita")], source: kavita)
        let komgaItem = item("Komga", timestamp: "2026-10-02T12:00:00+01:00")
            .withSource(komga, remoteSeriesID: "1")
        collection.setCachedItems([komgaItem], source: komga)
        collection.setCachedItems([item("File", timestamp: "2026-10-02T10:30:00Z", local: true)], source: .files)

        XCTAssertEqual(collection.items.map(\.series.title), ["Komga", "File", "Kavita"])
        XCTAssertEqual(Set(collection.items.map(\.id)).count, 3)
        XCTAssertNotEqual(kavita, .server(kind: "kavita", identity: "another-account"))
    }

    func testPromotesExistingSeriesEvenWhenAdapterCreatesANewUUID() {
        var collection = ContinueReadingCollection()
        collection.setCachedItems([item("First", id: 1), item("Second", id: 2)], source: kavita)
        collection.record(item("Second", id: 2), source: kavita, readAt: Date(timeIntervalSince1970: 2_000_000_000))

        XCTAssertEqual(collection.items.count, 2)
        XCTAssertEqual(collection.items.first?.series.title, "Second")
    }

    func testLateResponsePreservesReadsStartedAfterTheRequest() {
        var collection = ContinueReadingCollection()
        let requestedAt = Date(timeIntervalSince1970: 2_000_000_000)
        collection.record(item("New read"), source: kavita, readAt: requestedAt.addingTimeInterval(1))
        collection.acceptServerItems([], source: kavita, requestedAt: requestedAt)
        XCTAssertEqual(collection.items.map(\.series.title), ["New read"])

        // A subsequent authoritative response can remove completed/removed items.
        collection.acceptServerItems([], source: kavita, requestedAt: requestedAt.addingTimeInterval(2))
        XCTAssertTrue(collection.items.isEmpty)
    }

    func testReplacingOneServerDoesNotRemoveOtherSources() {
        var collection = ContinueReadingCollection()
        collection.setCachedItems([item("Kavita")], source: kavita)
        collection.setCachedItems([item("Komga")], source: komga)
        collection.acceptServerItems([], source: komga, requestedAt: Date())
        XCTAssertEqual(collection.items.map(\.series.title), ["Kavita"])
    }

    func testTieOrderIsStableRegardlessOfResponseOrder() {
        var first = ContinueReadingCollection()
        var second = ContinueReadingCollection()
        first.setCachedItems([item("A", id: 1), item("B", id: 2)], source: kavita)
        second.setCachedItems([item("B", id: 2), item("A", id: 1)], source: kavita)
        XCTAssertEqual(first.items.map(\.id), second.items.map(\.id))
    }
}
