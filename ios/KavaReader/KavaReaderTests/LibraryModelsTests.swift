import Combine
import Foundation
@testable import KavaReader
import XCTest

@MainActor
final class LibraryModelsTests: XCTestCase {
    func testLibraryPreferencesRoundTripPreservesFiltersAndRandomOrderPerCollection() throws {
        let saved = [
            "Kavita": LibraryListPreferences(readFilter: "unread", sort: .random,
                                             randomOrder: ["kavita:3", "kavita:1", "kavita:2"]),
            "Files": LibraryListPreferences(readFilter: "reading", sort: .titleDescending)
        ]
        let data = try JSONEncoder().encode(saved)
        let restored = try JSONDecoder().decode([String: LibraryListPreferences].self, from: data)
        XCTAssertEqual(restored["Kavita"]?.readFilter, "unread")
        XCTAssertEqual(restored["Kavita"]?.sort, .random)
        XCTAssertEqual(restored["Kavita"]?.randomOrder, ["kavita:3", "kavita:1", "kavita:2"])
        XCTAssertEqual(restored["Files"]?.readFilter, "reading")
        XCTAssertEqual(restored["Files"]?.sort, .titleDescending)
    }

    func testRandomOrderKeepsExistingRanksAcrossCatalogReloadsAndAdditions() {
        var preferences = LibraryListPreferences(sort: .random, randomOrder: ["c", "a", "b"])
        preferences.appendMissingSeries([])
        preferences.appendMissingSeries(["b", "a"])
        XCTAssertEqual(preferences.randomOrder, ["c", "a", "b"])
        preferences.appendMissingSeries(["b", "a", "d", "e", "d"])
        XCTAssertEqual(Array(preferences.randomOrder.prefix(3)), ["c", "a", "b"])
        XCTAssertEqual(Set(preferences.randomOrder.suffix(2)), Set(["d", "e"]))
        let order = preferences.randomOrder
        preferences.appendMissingSeries(["e", "d", "c", "b", "a"])
        XCTAssertEqual(preferences.randomOrder, order)
        XCTAssertEqual(preferences.randomRanks["c"], 0)
        XCTAssertEqual(preferences.randomRanks["b"], 2)
    }

    func testContinueReadingSortsAcrossSourcesByActualReadTime() {
        func item(_ title: String, serverID: Int?, timestamp: String) -> ContinueReadingItem {
            ContinueReadingItem(
                series: LibrarySeries(kavitaSeriesId: serverID, title: title, author: "", coverColorHexes: [],
                                      isLocal: serverID == nil),
                lastReadChapter: SeriesChapter(id: UUID(), title: "1", number: 1, pageCount: 20),
                progress: ProgressDto(volumeId: 0, chapterId: 0, pageNum: 1,
                                      seriesId: serverID ?? 0, libraryId: 0, bookScrollId: nil,
                                      lastModifiedUtc: timestamp))
        }
        let items = [
            item("server older", serverID: 1, timestamp: "2026-10-02T09:00:00Z"),
            item("server latest", serverID: 2, timestamp: "2026-10-02T10:00:00.1234567"),
            item("missing", serverID: 3, timestamp: ""),
            item("file latest", serverID: nil, timestamp: "2026-10-02T10:00:00.500Z"),
            item("file older", serverID: nil, timestamp: "2026-10-02T10:30:00+02:00"),
            item("invalid", serverID: nil, timestamp: "invalid")
        ]
        XCTAssertEqual(ContinueReadingItem.sortedByLastRead(items).map(\.series.title),
                       ["file latest", "server latest", "server older", "file older", "missing", "invalid"])
    }

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

@MainActor
final class LibraryPlusCurationTests: XCTestCase {
    private func series(_ id: Int, read: Bool = false) -> LibrarySeries {
        LibrarySeries(kavitaSeriesId: id, title: "Series \(id)", author: "",
                      coverColorHexes: [], isRead: read)
    }

    func testMinimumFourAndSingleFavouriteException() {
        let items = (1...3).map { series($0) }
        let empty = LibraryPlusCurator(series: items, metadata: [:], readingIDs: [],
                                      favouriteIDs: [], recent: [], day: 1)
        XCTAssertTrue(empty.rows(featured: [], continuing: []).isEmpty)
        let saved = LibraryPlusCurator(series: items, metadata: [:], readingIDs: [],
                                      favouriteIDs: [1], recent: [], day: 1)
        let rows = saved.rows(featured: [], continuing: [])
        XCTAssertEqual(rows.map(\.id), ["favourites"])
        XCTAssertEqual(rows.first?.items.compactMap(\.kavitaSeriesId), [1])
        let eligible = LibraryPlusCurator(series: items + [series(4)], metadata: [:],
                                         readingIDs: [], favouriteIDs: [], recent: [], day: 1)
        XCTAssertEqual(eligible.rows(featured: [], continuing: []).first?.items.count, 4)
    }

    func testReadAndInProgressAreExcludedFromDiscovery() {
        let items = [series(1, read: true)] + (2...7).map { series($0) }
        let curator = LibraryPlusCurator(series: items, metadata: [:], readingIDs: [2, 3],
                                        favouriteIDs: [], recent: items, day: 1)
        let ids = Set(curator.rows(featured: [], continuing: []).flatMap(\.items).compactMap(\.kavitaSeriesId))
        XCTAssertEqual(ids, Set(4...7))
    }

    func testRepeatBudgetIsAppliedBeforeMinimumCount() {
        let items = (1...4).map { series($0) }
        let curator = LibraryPlusCurator(series: items, metadata: [:], readingIDs: [],
                                        favouriteIDs: [], recent: [], day: 1)
        // The first series already appears twice, leaving only three candidates.
        XCTAssertTrue(curator.rows(featured: [items[0]], continuing: [items[0]]).isEmpty)
    }

    func testScoringRecognizesAliasesAndCountsEachCategoryOnce() {
        let seed = series(1)
        let metadata = [
            1: LibraryPlusMetadata(summary: "", genres: ["판타지", "Fantasy"], tags: ["요리"]),
            2: LibraryPlusMetadata(summary: "", genres: ["Fantasy"], tags: []),
            3: LibraryPlusMetadata(summary: "", genres: [], tags: ["Cooking"]),
            4: LibraryPlusMetadata(summary: "", genres: ["Fantasy"], tags: ["Cooking"])
        ]
        let curator = LibraryPlusCurator(series: [seed, series(2), series(3), series(4)],
                                        metadata: metadata, readingIDs: [1], favouriteIDs: [],
                                        recent: [], day: 1)
        XCTAssertEqual(curator.recommended.compactMap(\.kavitaSeriesId), [4, 2, 3])
    }

    func testRowLimitsOverlapAndDailyStability() {
        let items = (1...40).map { series($0) }
        let curator = LibraryPlusCurator(series: items, metadata: [:], readingIDs: [],
                                        favouriteIDs: [1], recent: items, day: 100)
        let first = curator.rows(featured: [], continuing: [])
        let again = curator.rows(featured: [], continuing: [])
        XCTAssertLessThanOrEqual(first.count, 2)
        XCTAssertEqual(first.first?.id, "favourites")
        XCTAssertTrue(first.allSatisfy { $0.items.count <= 12 })
        XCTAssertEqual(first.map(\.id), again.map(\.id))
        XCTAssertEqual(first.map { $0.items.compactMap(\.kavitaSeriesId) },
                       again.map { $0.items.compactMap(\.kavitaSeriesId) })
        for index in first.indices {
            let a = Set(first[index].items.compactMap(\.kavitaSeriesId))
            for other in first.indices where other > index {
                let b = Set(first[other].items.compactMap(\.kavitaSeriesId))
                XCTAssertLessThan(Double(a.intersection(b).count) / Double(min(a.count, b.count)), 0.7)
            }
        }
    }
}

@MainActor
final class LibraryPlusDailySnapshotTests: XCTestCase {
    func testRestoreAndTabReentryKeepTheSameCatalog() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LibraryPlusDailyStore(directory: directory)
        let identity = UUID().uuidString
        let original = catalog()
        let snapshot = LibraryPlusDailySnapshot(day: 100, revision: "initial", catalog: original,
                                                metadata: [:], external: [:])
        try await store.save(snapshot, identity: identity)
        let model = LibraryPlusViewModel(dailyStore: store)
        let empty = LibraryCatalogSnapshot(sections: [], continueReading: [])
        let service = makeService()
        await model.prepareDaily(catalog: empty, identity: identity, baseURL: service.baseURL,
                                 apiKey: "", day: 100, revision: "initial", service: service)?.value
        XCTAssertEqual(model.dailySnapshot?.catalog.sections.first?.series.first?.kavitaSeriesId, 42)
        XCTAssertFalse(model.isPreparingDaily)
        XCTAssertFalse(model.isLoading)
        XCTAssertFalse(model.isEnriching)
        XCTAssertFalse(model.needsDailyPreparation(identity: identity, day: 100, revision: "initial"))
        let presentationIDs = model.dailyPresentation?.featured.compactMap(\.kavitaSeriesId)
        var presentationUpdates = 0
        let presentationSubscription = model.$dailyPresentation.dropFirst().sink { _ in presentationUpdates += 1 }
        defer { presentationSubscription.cancel() }

        // Even a different disk snapshot must not be reread when returning to the tab.
        try await store.save(LibraryPlusDailySnapshot(day: 100, revision: "initial", catalog: empty,
                                                     metadata: [:], external: [:]), identity: identity)
        await model.prepareDaily(catalog: empty, identity: identity, baseURL: service.baseURL,
                                 apiKey: "", day: 100, revision: "initial", service: service)?.value
        XCTAssertEqual(model.dailySnapshot?.catalog.sections.first?.series.first?.kavitaSeriesId, 42)
        XCTAssertEqual(model.dailyPresentation?.featured.compactMap(\.kavitaSeriesId), presentationIDs)
        XCTAssertEqual(presentationUpdates, 0)
    }

    func testDayAndSettingsRevisionInvalidateTheSnapshot() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LibraryPlusDailyStore(directory: directory)
        let service = makeService()
        let empty = LibraryCatalogSnapshot(sections: [], continueReading: [])
        for (day, revision) in [(101, "initial"), (100, "settings-update")] {
            let identity = UUID().uuidString
            try await store.save(LibraryPlusDailySnapshot(day: 100, revision: "initial", catalog: catalog(),
                                                         metadata: [:], external: [:]), identity: identity)
            let model = LibraryPlusViewModel(dailyStore: store)
            await model.prepareDaily(catalog: empty, identity: identity, baseURL: service.baseURL,
                                     apiKey: "", day: day, revision: revision, service: service)?.value
            XCTAssertEqual(model.dailySnapshot?.day, day)
            XCTAssertEqual(model.dailySnapshot?.revision, revision)
            XCTAssertEqual(model.dailySnapshot?.catalog.sections.count, 0)
            let restored = await store.load(identity: identity)
            XCTAssertTrue(restored?.matches(day: day, revision: revision) == true)
        }
    }

    func testSnapshotOmitsCredentialsAndServerSwitchClearsVisibleState() async throws {
        let snapshot = LibraryPlusDailySnapshot(day: 100, revision: "initial", catalog: catalog(),
                                                metadata: [:], external: [:])
        let data = try JSONEncoder().encode(snapshot)
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(json.contains("secret-test-key"))
        XCTAssertFalse(json.contains("apiKey"))
        XCTAssertFalse(json.contains("coverURL"))

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LibraryPlusDailyStore(directory: directory)
        try await store.save(snapshot, identity: "server-a")
        let model = LibraryPlusViewModel(dailyStore: store)
        let service = makeService()
        await model.prepareDaily(catalog: LibraryCatalogSnapshot(sections: [], continueReading: []), identity: "server-a", baseURL: service.baseURL,
                                 apiKey: "", day: 100, revision: "initial", service: service)?.value
        XCTAssertNotNil(model.dailySnapshot)
        model.selectIdentity("server-b")
        XCTAssertNil(model.dailySnapshot)
        XCTAssertTrue(model.metadataByID.isEmpty)
        XCTAssertFalse(model.isPreparingDaily)
    }

    func testCollectedMetadataDoesNotChangeTodayButAppearsTomorrow() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LibraryPlusDailyStore(directory: directory)
        let model = LibraryPlusViewModel(dailyStore: store)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DailySnapshotMetadataProtocol.self]
        let service = KavitaLibraryService(baseURL: URL(string: "https://example.invalid")!, apiKey: "",
                                          session: URLSession(configuration: configuration))
        let identity = UUID().uuidString
        var publications = 0
        let subscription = model.$dailySnapshot.dropFirst().sink { snapshot in
            if snapshot != nil { publications += 1 }
        }
        defer { subscription.cancel() }
        await model.prepareDaily(catalog: catalog(), identity: identity, baseURL: service.baseURL,
                                 apiKey: "", day: 100, revision: "initial", service: service)?.value
        XCTAssertEqual(model.metadataByID[42]?.genres, ["Fantasy"])
        XCTAssertNil(model.dailySnapshot?.metadata[42])
        XCTAssertEqual(publications, 1)
        let persistedToday = await store.load(identity: identity)
        XCTAssertNil(persistedToday?.metadata[42])

        var parentNotifications = 0
        let parentSubscription = model.objectWillChange.sink { parentNotifications += 1 }
        model.diagnostics.externalLookupCount += 1
        XCTAssertEqual(parentNotifications, 0)
        parentSubscription.cancel()

        await model.prepareDaily(catalog: catalog(), identity: identity, baseURL: service.baseURL,
                                 apiKey: "", day: 101, revision: "initial", service: service)?.value
        XCTAssertEqual(model.dailySnapshot?.metadata[42]?.genres, ["Fantasy"])
        XCTAssertEqual(publications, 2)
    }

    func testPersistedSelectionIsReusedWithoutCuration() throws {
        let selected = LibraryPlusSelection(featuredIDs: [42], rows: [
            LibraryPlusSelection.Row(id: "stored-row", title: "Stored title", seriesIDs: [42], subtitle: nil)
        ], hasRecommendations: true)
        var snapshot = LibraryPlusDailySnapshot(day: 100, revision: "initial", catalog: catalog(),
                                                metadata: [:], external: [:], selection: selected)
        snapshot.prepareSelection(baseURL: nil, apiKey: "")
        XCTAssertEqual(snapshot.selection, selected)
        let data = try JSONEncoder().encode(snapshot)
        var restored = try JSONDecoder().decode(LibraryPlusDailySnapshot.self, from: data)
        restored.prepareSelection(baseURL: URL(string: "https://example.invalid"), apiKey: "test-key")
        XCTAssertEqual(restored.selection, selected)
        let presentation = restored.presentation(baseURL: nil, apiKey: "")
        XCTAssertEqual(presentation.featured.compactMap(\.kavitaSeriesId), [42])
        XCTAssertEqual(presentation.rows.map(\.id), ["stored-row"])
        XCTAssertEqual(presentation.rows.first?.items.compactMap(\.kavitaSeriesId), [42])
        XCTAssertTrue(presentation.hasRecommendations)
    }

    func testLegacySnapshotSelectionIsMigratedOnce() throws {
        let snapshot = LibraryPlusDailySnapshot(day: 100, revision: "initial", catalog: catalog(),
                                                metadata: [:], external: [:])
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as? [String: Any])
        json.removeValue(forKey: "selection")
        var restored = try JSONDecoder().decode(LibraryPlusDailySnapshot.self,
                                               from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(restored.selection)
        restored.prepareSelection(baseURL: nil, apiKey: "")
        let selected = try XCTUnwrap(restored.selection)
        XCTAssertEqual(selected.featuredIDs, [42])
        restored.prepareSelection(baseURL: nil, apiKey: "")
        XCTAssertEqual(restored.selection, selected)
    }

    private func catalog() -> LibraryCatalogSnapshot {
        let item = SeriesInfo(id: UUID(), kavitaSeriesId: 42, title: "Daily series", author: "",
                              coverColorHexes: [],
                              coverURL: URL(string: "https://example.invalid/cover?apiKey=secret-test-key"))
        return LibraryCatalogSnapshot(sections: [LibrarySection(id: UUID(), title: "All Series", items: [item])],
                                      continueReading: [])
    }

    private func makeService() -> KavitaLibraryService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DailySnapshotNoNetworkProtocol.self]
        return KavitaLibraryService(baseURL: URL(string: "https://example.invalid")!, apiKey: "",
                                    session: URLSession(configuration: configuration))
    }
}

private final class DailySnapshotNoNetworkProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        XCTFail("Restoring a daily snapshot must not request Kavita")
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }
    override func stopLoading() {}
}

private final class DailySnapshotMetadataProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let data = Data(#"{"summary":"Cached tomorrow","genres":[{"title":"Fantasy"}],"tags":[]}"#.utf8)
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
