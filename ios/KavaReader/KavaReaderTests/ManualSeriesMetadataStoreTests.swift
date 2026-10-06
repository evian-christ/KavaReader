import Foundation
@testable import KavaReader
import Testing

@MainActor
struct ManualSeriesMetadataStoreTests {
    // MARK: Internal

    @Test func userChoicesSurviveRestartAndStayIsolatedByAccountAndSeries() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ManualSeriesMetadataStore(directory: directory)
        let metadata = try metadata(id: 42, genre: "Fantasy")
        let oldDate = Date(timeIntervalSince1970: 0)
        try await store.set(.init(metadata: metadata, updatedAt: oldDate), identity: "account-a", seriesID: 1)
        try await store.set(.init(metadata: nil, updatedAt: oldDate), identity: "account-a", seriesID: 2)
        let restored = ManualSeriesMetadataStore(directory: directory)
        let records = await restored.load(identity: "account-a")
        #expect(records[1]?.metadata?.aniListID == 42)
        #expect(records[1]?.updatedAt == oldDate)
        #expect(records[2] != nil)
        #expect(records[2]?.metadata == nil)
        let other = await restored.load(identity: "account-b")
        #expect(other.isEmpty)

        try await restored.set(nil, identity: "account-a", seriesID: 2)
        let updated = await restored.load(identity: "account-a")
        #expect(updated[2] == nil)
        #expect(updated[1]?.metadata?.aniListID == 42)
    }

    @Test func manualChoiceOverridesKavitaCategoriesAndPersistsForHomeGenres() throws {
        let item = SeriesInfo(id: UUID(), kavitaSeriesId: 1, title: "Renamed local title", author: "",
                              coverColorHexes: [], coverURL: nil)
        let catalog = LibraryCatalogSnapshot(sections: [.init(id: UUID(), title: "All Series", items: [item])],
                                             continueReading: [])
        let automatic = try metadata(id: 10, genre: "Drama")
        let manual = try metadata(id: 42, genre: "Fantasy")
        var snapshot = LibraryPlusDailySnapshot(day: 100, revision: "initial", catalog: catalog,
                                                metadata: [1: .init(summary: "Kavita summary", genres: ["Drama"], tags: ["School"])],
                                                external: [1: automatic])
        snapshot.applyManualConnections([1: .init(metadata: manual, updatedAt: Date(timeIntervalSince1970: 0))])
        #expect(snapshot.external[1]?.aniListID == 42)
        let fantasy = try #require(HomeGenre.allCases.first { $0.matches(["Fantasy"]) })
        #expect(snapshot.presentation(baseURL: nil, apiKey: "").genreSeriesIDs[fantasy] == [1])
        let restored = try JSONDecoder().decode(LibraryPlusDailySnapshot.self, from: JSONEncoder().encode(snapshot))
        let presentation = restored.presentation(baseURL: nil, apiKey: "")
        #expect(presentation.genreSeriesIDs[fantasy] == [1])
        #expect(presentation.metadata[1]?.genres == ["Fantasy"])
        #expect(presentation.metadata[1]?.tags.isEmpty == true)
        #expect(presentation.metadata[1]?.summary == "Kavita summary")

        snapshot.applyManualConnections([1: .init(metadata: nil, updatedAt: Date())])
        #expect(snapshot.external[1] == nil)
        #expect(snapshot.presentation(baseURL: nil, apiKey: "").genreSeriesIDs[fantasy]?.isEmpty == true)
        #expect(snapshot.presentation(baseURL: nil, apiKey: "").metadata[1]?.genres == ["Drama"])
        #expect(snapshot.presentation(baseURL: nil, apiKey: "").metadata[1]?.tags == ["School"])
    }

    @Test func storedConnectionIsVisibleAfterLocalTitleChanges() async throws {
        let identity = "manual-test-\(UUID().uuidString)"
        defer {
            Task { try? await ManualSeriesMetadataStore.shared.set(nil, identity: identity, seriesID: 7) }
        }
        let metadata = try metadata(id: 42, genre: "Fantasy")
        try await ManualSeriesMetadataStore.shared
            .set(.init(metadata: metadata, updatedAt: Date(timeIntervalSince1970: 0)),
                 identity: identity, seriesID: 7)
        let info = await SeriesInformationCache.load(identity: identity, seriesID: 7, title: "Different title")
        #expect(info.external?.aniListID == 42)
        #expect(info.manual != nil)
    }

    // MARK: Private

    private func metadata(id: Int, genre: String) throws -> ExternalSeriesMetadata {
        try ExternalSeriesMetadata(aniListID: id, sourceTitle: "Example",
                                   sourceURL: #require(URL(string: "https://anilist.co/manga/\(id)")),
                                   genres: [genre], tags: [])
    }
}
