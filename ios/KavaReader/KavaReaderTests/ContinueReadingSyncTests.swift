import Foundation
@testable import KavaReader
import XCTest

@MainActor
final class ContinueReadingSyncTests: XCTestCase {
    func testFailedRefreshPreservesCacheAndSuccessfulEmptyResponseRemovesIt() async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LibraryCatalogStore(directory: directory)
        let service = ContinueReadingSyncService()
        service.items = [item("Cached", id: 1)]
        let model = LibraryViewModel(service: service, catalogStore: store)
        await model.restore(service: service, identity: "sync-test", baseURL: "https://example.com", apiKey: "")
        XCTAssertEqual(serverItems(model).map(\.series.title), ["Cached"])

        service.error = LibraryServiceError.serverUnavailable
        await model.refreshContinueReading()
        XCTAssertEqual(serverItems(model).map(\.series.title), ["Cached"])
        XCTAssertNotNil(model.errorMessage)
        XCTAssertEqual(service.sectionRequests, 1)

        service.error = nil
        service.items = []
        await model.refreshContinueReading()
        XCTAssertTrue(serverItems(model).isEmpty)
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(service.sectionRequests, 1)
    }

    func testReadingActivityIsImmediateAndSurvivesOfflineRelaunch() async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LibraryCatalogStore(directory: directory)
        let service = ContinueReadingSyncService()
        service.items = [item("Old", id: 1)]
        let model = LibraryViewModel(service: service, catalogStore: store)
        await model.restore(service: service, identity: "activity-test", baseURL: "https://example.com", apiKey: "")
        await model.recordReadingActivity(item("New", id: 2), identity: "activity-test", readAt: Date())
        XCTAssertEqual(serverItems(model).map(\.series.title), ["New", "Old"])

        // Events from a reader belonging to another account cannot contaminate the list.
        await model.recordReadingActivity(item("Wrong account", id: 3), identity: "other-account", readAt: Date())
        XCTAssertEqual(serverItems(model).count, 2)

        service.error = LibraryServiceError.serverUnavailable
        let relaunched = LibraryViewModel(service: service, catalogStore: store)
        await relaunched.restore(service: service, identity: "activity-test", baseURL: "https://example.com", apiKey: "")
        XCTAssertEqual(serverItems(relaunched).map(\.series.title), ["New", "Old"])
        XCTAssertEqual(service.sectionRequests, 1)
    }

    private func serverItems(_ model: LibraryViewModel) -> [ContinueReadingItem] {
        model.continueReadingItems.filter { $0.source != .files }
    }

    private func item(_ title: String, id: Int) -> ContinueReadingItem {
        ContinueReadingItem(series: LibrarySeries(kavitaSeriesId: id, title: title, author: "", coverColorHexes: []),
                            lastReadChapter: SeriesChapter(id: UUID(), title: "1", number: 1, pageCount: 20),
                            progress: ProgressDto(volumeId: 1, chapterId: 1, pageNum: 2, seriesId: id,
                                                  libraryId: 1, bookScrollId: nil, lastModifiedUtc: "2001-01-01T00:00:00Z"))
    }
}

private final class ContinueReadingSyncService: MockLibraryService {
    var items: [ContinueReadingItem] = []
    var error: LibraryServiceError?
    var sectionRequests = 0

    override func fetchSections() async throws -> [LibrarySection] {
        sectionRequests += 1
        return []
    }

    override func fetchContinueReadingItems() async throws -> [ContinueReadingItem] {
        if let error { throw error }
        return items
    }
}
