import Foundation
@testable import KavaReader
import XCTest

@MainActor
final class LibraryPlusAnchorPolicyTests: XCTestCase {
    func testUsesWholeSeriesThresholdAndRejectsUnknownProgress() {
        let items = [series(1, read: 3), series(2, read: 499), series(3, read: 500),
                     series(4, read: 900), series(5, read: nil), series(6, read: 50, total: 0)]
        let result = candidates(items)
        XCTAssertEqual(result.compactMap(\.kavitaSeriesId), [4, 3])
    }

    func testCompletedAnchorsComeBeforePartialAnchors() {
        let partial = series(1, read: 990)
        let complete = series(2, read: nil, completed: true)
        let history = [LibraryPlusAnchorRecord(day: 98, seriesId: 2)]
        XCTAssertEqual(candidates([partial, complete], history: history).first?.kavitaSeriesId, 2)
    }

    func testYesterdayIsExcludedEvenWhenItIsTheOnlyEligibleAnchor() {
        let completed = series(1, read: 1000)
        let history = [LibraryPlusAnchorRecord(day: 99, seriesId: 1)]
        XCTAssertTrue(candidates([completed], history: history).isEmpty)
        XCTAssertEqual(candidates([completed, series(2, read: 600)], history: history).first?.kavitaSeriesId, 2)
    }

    func testRecentAndRepeatedAnchorsLosePriorityAndPenaltyEventuallyExpires() {
        let items = [series(1, read: 1000), series(2, read: 1000)]
        XCTAssertEqual(candidates(items).first?.kavitaSeriesId, 1)
        let recent = [LibraryPlusAnchorRecord(day: 98, seriesId: 1)]
        XCTAssertEqual(candidates(items, history: recent).first?.kavitaSeriesId, 2)
        let older = recent + [LibraryPlusAnchorRecord(day: 90, seriesId: 2)]
        XCTAssertEqual(candidates(items, history: older).first?.kavitaSeriesId, 2)
        let equallyRecent = recent + [LibraryPlusAnchorRecord(day: 98, seriesId: 2),
                                     LibraryPlusAnchorRecord(day: 96, seriesId: 1)]
        XCTAssertEqual(candidates(items, history: equallyRecent).first?.kavitaSeriesId, 2)
        XCTAssertEqual(candidates(items, history: [.init(day: 69, seriesId: 1)]).first?.kavitaSeriesId, 1)
    }

    func testCuratorUsesCompletedAnchorInsteadOfBarelyReadFavourite() {
        let barelyRead = series(1, read: 3)
        let completed = series(2, read: 1000)
        let unread = (10 ... 15).map { series($0, read: 0) }
        let items = [barelyRead, completed] + unread
        let metadata = Dictionary(uniqueKeysWithValues: items.map {
            ($0.kavitaSeriesId!, LibraryPlusMetadata(summary: "", genres: ["Fantasy"], tags: []))
        })
        let curator = LibraryPlusCurator(series: items, metadata: metadata, readingIDs: [1],
                                        favouriteIDs: [1], recent: [], day: 100)
        let row = curator.rows(featured: [], continuing: []).first { $0.id == "similar" }
        XCTAssertEqual(row?.sourceSeriesId, 2)
        XCTAssertEqual(row?.subtitle, completed.title)
        XCTAssertEqual(Set(row?.items.compactMap(\.kavitaSeriesId) ?? []), Set(10 ... 15))
    }

    func testCatalogPreservesWholeSeriesProgressAcrossRestart() throws {
        let item = SeriesInfo(id: UUID(), kavitaSeriesId: 1, title: "Half read", author: "",
                              coverColorHexes: [], coverURL: nil, totalPages: 1000, pagesRead: 500)
        let snapshot = LibraryCatalogSnapshot(sections: [.init(id: UUID(), title: "All Series", items: [item])],
                                               continueReading: [])
        let restored = try JSONDecoder().decode(LibraryCatalogSnapshot.self, from: JSONEncoder().encode(snapshot))
        let series = try XCTUnwrap(restored.domainSections(baseURL: nil, apiKey: "").first?.series.first)
        XCTAssertEqual(LibraryPlusAnchorPolicy.progress(series), 0.5)
    }

    func testHistorySurvivesRestartAndSameDayRefreshAndSeparatesAccounts() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LibraryPlusDailyStore(directory: directory)
        try await store.save(snapshot(day: 100, anchor: 1), identity: "account-a")
        try await store.save(snapshot(day: 101, anchor: 2), identity: "account-a")
        try await store.save(snapshot(day: 101, anchor: 3), identity: "account-a")
        let restored = LibraryPlusDailyStore(directory: directory)
        let history = await restored.loadAnchorHistory(identity: "account-a")
        XCTAssertTrue(history.contains(.init(day: 100, seriesId: 1)))
        XCTAssertTrue(history.contains(.init(day: 101, seriesId: 2)))
        XCTAssertTrue(history.contains(.init(day: 101, seriesId: 3)))
        let otherAccount = await restored.loadAnchorHistory(identity: "account-b")
        XCTAssertTrue(otherAccount.isEmpty)
    }

    func testOldDailyAlgorithmDoesNotKeepAnIneligibleAnchor() throws {
        let snapshot = snapshot(day: 100, anchor: 1)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as? [String: Any])
        json.removeValue(forKey: "curationVersion")
        let old = try JSONDecoder().decode(LibraryPlusDailySnapshot.self,
                                           from: JSONSerialization.data(withJSONObject: json))
        XCTAssertFalse(old.matches(day: 100, revision: "initial"))
    }

    private func candidates(_ items: [LibrarySeries], history: [LibraryPlusAnchorRecord] = []) -> [LibrarySeries] {
        LibraryPlusAnchorPolicy.candidates(items, history: history, day: 100) { UInt64($0) }
    }

    private func series(_ id: Int, read: Int?, total: Int = 1000, completed: Bool = false) -> LibrarySeries {
        LibrarySeries(kavitaSeriesId: id, title: "Series \(id)", author: "", coverColorHexes: [],
                      isRead: completed || (total > 0 && (read ?? 0) >= total), totalPages: total, pagesRead: read)
    }

    private func snapshot(day: Int, anchor: Int) -> LibraryPlusDailySnapshot {
        LibraryPlusDailySnapshot(day: day, revision: "initial",
                                catalog: LibraryCatalogSnapshot(sections: [], continueReading: []),
                                metadata: [:], external: [:],
                                selection: LibraryPlusSelection(featuredIDs: [], rows: [], hasRecommendations: false,
                                                                anchorSeriesId: anchor))
    }
}
