import Foundation
@testable import KavaReader
import XCTest

@MainActor
final class ReadingPauseStoreTests: XCTestCase {
    func testPausePersistsPerAccountAndPreservesReadingPosition() {
        let suite = "ReadingPauseTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let identity = UUID().uuidString
        defer {
            defaults.removePersistentDomain(forName: suite)
            ReadingStatusStore.clear(identity: identity, seriesId: 42)
        }
        _ = ReadingStatusStore.saveLocalProgress(chapterId: 9, volumeId: 3, page: 27,
                                                  identity: identity, seriesId: 42)
        ReadingPauseStore.setPaused(true, identity: identity, seriesId: 42, defaults: defaults, notify: false)
        let reopenedDefaults = UserDefaults(suiteName: suite)!
        XCTAssertEqual(ReadingPauseStore.pausedSeriesIDs(identity: identity, defaults: reopenedDefaults), [42])
        XCTAssertTrue(ReadingPauseStore.pausedSeriesIDs(identity: "other-account", defaults: defaults).isEmpty)
        XCTAssertEqual(ReadingStatusStore.load(identity: identity, seriesId: 42)?.page, 27)
        XCTAssertEqual(ReadingStatusStore.load(identity: identity, seriesId: 42)?.chapterId, 9)
        ReadingPauseStore.setPaused(false, identity: identity, seriesId: 42, defaults: defaults, notify: false)
        XCTAssertTrue(ReadingPauseStore.pausedSeriesIDs(identity: identity, defaults: defaults).isEmpty)
        XCTAssertEqual(ReadingStatusStore.load(identity: identity, seriesId: 42)?.page, 27)
    }

    func testCatalogFilteringDoesNotErasePausedSeriesDuringFavouriteChange() async throws {
        let identity = UUID().uuidString
        let item = SeriesInfo(id: UUID(), kavitaSeriesId: 42, title: "Paused series", author: "",
                              coverColorHexes: [], coverURL: nil, totalPages: 100, pagesRead: 27)
        let snapshot = LibraryCatalogSnapshot(sections: [
            LibrarySection(id: UUID(), title: "읽는 중", items: [item]),
            LibrarySection(id: UUID(), title: "모든 만화", items: [item])
        ], continueReading: [])
        let generation = await LibraryCatalogStore.shared.currentGeneration()
        try await LibraryCatalogStore.shared.save(snapshot, identity: identity, generation: generation)
        defer { ReadingPauseStore.setPaused(false, identity: identity, seriesId: 42, notify: false) }
        let service = LibraryServiceFactory(baseURLString: "http://", apiKey: nil).makeService()
        let model = LibraryViewModel(service: service)
        await model.restore(service: service, identity: identity, baseURL: "", apiKey: "")
        ReadingPauseStore.setPaused(true, identity: identity, seriesId: 42, notify: false)
        model.applyReadingPauseChange()
        XCTAssertNil(model.sections.first { $0.title == "읽는 중" })
        XCTAssertEqual(model.sections.first { $0.title == "모든 만화" }?.items.first?.pagesRead, 27)
        await model.applyWantToReadChange(series: item.toLibrarySeries(), isWanted: true)
        let restored = LibraryViewModel(service: service)
        await restored.restore(service: service, identity: identity, baseURL: "", apiKey: "")
        XCTAssertNil(restored.sections.first { $0.title == "읽는 중" })
        ReadingPauseStore.setPaused(false, identity: identity, seriesId: 42, notify: false)
        restored.applyReadingPauseChange()
        XCTAssertEqual(restored.sections.first { $0.title == "읽는 중" }?.items.first?.pagesRead, 27)
    }
}
