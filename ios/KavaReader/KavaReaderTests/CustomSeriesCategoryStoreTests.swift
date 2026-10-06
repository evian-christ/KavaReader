import Foundation
@testable import KavaReader
import Testing

@MainActor
struct CustomSeriesCategoryStoreTests {
    @Test func additionsPersistWithoutReplacingSourceCategories() throws {
        let suite = "development-categories-test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let key = CustomSeriesCategoryStore.key(identity: "account-a", seriesID: "1", isLocal: false)
        let source = LibraryPlusMetadata(summary: "Summary", genres: ["Drama"], tags: ["School"])
        try CustomSeriesCategoryStore.save(.init(summary: "", genres: [" drama ", "Fantasy"], tags: ["Magic"]),
                                                key: key, defaults: defaults)
        let reopenedDefaults = try #require(UserDefaults(suiteName: suite))
        let resolved = CustomSeriesCategoryStore.applying(to: source, key: key, defaults: reopenedDefaults)
        #expect(resolved.genres == ["Drama", "genre:fantasy"])
        #expect(resolved.tags == ["School", "tag:magic"])
        #expect(resolved.summary == "Summary")
        CustomSeriesCategoryStore.reset(key: key, defaults: defaults)
        #expect(CustomSeriesCategoryStore.applying(to: source, key: key, defaults: defaults) == source)
    }

    @Test func legacyKoreanAdditionsResolveToStableIDsAndMergeWithEnglishSources() throws {
        let suite = "legacy-categories-test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let key = CustomSeriesCategoryStore.key(identity: "account", seriesID: "1", isLocal: false)
        let legacy = Data(#"{"summary":"","genres":["판타지","Fantasy"],"tags":["마법","Magic","내 취향"]}"#.utf8)
        defaults.set(legacy, forKey: key)
        let additions = CustomSeriesCategoryStore.load(key: key, defaults: defaults)
        #expect(additions.genres == ["genre:fantasy"])
        #expect(additions.tags == ["tag:magic", "내 취향"])
        let source = LibraryPlusMetadata(summary: "Summary", genres: ["Fantasy"], tags: ["Magic"])
        let merged = CustomSeriesCategoryStore.applying(to: source, key: key, defaults: defaults)
        #expect(merged.genres == ["Fantasy"])
        #expect(merged.tags == ["Magic", "내 취향"])
        #expect(HomeGenre.fantasy.matches(additions.genres))
        #expect(MetadataLocalization.displayName(additions.genres[0], language: .english) == "Fantasy")
    }

    @Test func storageSeparatesAccountsAndSeriesWhileLocalFilesIgnoreServerChanges() {
        let first = CustomSeriesCategoryStore.key(identity: "account-a", seriesID: "1", isLocal: false)
        #expect(first != CustomSeriesCategoryStore.key(identity: "account-b", seriesID: "1", isLocal: false))
        #expect(first != CustomSeriesCategoryStore.key(identity: "account-a", seriesID: "2", isLocal: false))
        let local = CustomSeriesCategoryStore.key(identity: "account-a", seriesID: "1", isLocal: true)
        #expect(first != local)
        #expect(local == CustomSeriesCategoryStore.key(identity: "account-b", seriesID: "1", isLocal: true))
    }

    @Test func homeGenreFilteringUsesAdditionsWithoutChangingSourceMetadata() throws {
        let identity = "development-home-test-\(UUID().uuidString)"
        let key = CustomSeriesCategoryStore.key(identity: identity, seriesID: "1", isLocal: false)
        defer { CustomSeriesCategoryStore.reset(key: key) }
        let item = SeriesInfo(id: UUID(), kavitaSeriesId: 1, title: "Comic", author: "",
                              coverColorHexes: [], coverURL: nil)
        let catalog = LibraryCatalogSnapshot(sections: [.init(id: UUID(), title: "All Series", items: [item])],
                                             continueReading: [])
        let source = LibraryPlusMetadata(summary: "", genres: ["Drama"], tags: [])
        let snapshot = LibraryPlusDailySnapshot(day: 100, revision: "initial", catalog: catalog,
                                                metadata: [1: source], external: [:])
        try CustomSeriesCategoryStore.save(.init(summary: "", genres: ["판타지"], tags: ["마법"]), key: key)
        let fantasy = try #require(HomeGenre.allCases.first { $0.matches(["Fantasy"]) })
        let presentation = snapshot.presentation(baseURL: nil, apiKey: "", identity: identity)
        #expect(presentation.genreSeriesIDs[fantasy] == [1])
        #expect(presentation.metadata[1]?.tags == ["tag:magic"])
        #expect(snapshot.metadata[1] == source)
        CustomSeriesCategoryStore.reset(key: key)
        #expect(snapshot.presentation(baseURL: nil, apiKey: "", identity: identity).metadata[1] == source)
    }
}
