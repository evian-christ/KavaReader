import Foundation
@testable import KavaReader
import Testing

@MainActor
struct MetadataCategoryRegistryTests {
    @Test func tagPreviewCapsEachRowAtFifteenAndShowsAtMostThreeRows() {
        let tags = (0 ..< 100).map { HomeReadTag(id: "tag:\($0)", name: "Tag \($0)", count: 1) }
        let rows = HomeReadTag.previewRows(tags: tags)
        #expect(rows.map(\.count) == [15, 15, 15])
        #expect(Set(rows.flatMap { $0 }.map(\.id)).count == 45)
        #expect(Set(rows.flatMap { $0 }.map(\.id)) == Set(tags.prefix(45).map(\.id)))
        #expect(HomeReadTag.previewRows(tags: Array(tags.prefix(15))).map(\.count) == [15])
        #expect(HomeReadTag.previewRows(tags: Array(tags.prefix(16))).map(\.count) == [8, 8])
        #expect(HomeReadTag.previewRows(tags: Array(tags.prefix(31))).map(\.count) == [11, 10, 10])
        #expect(HomeReadTag.previewRows(tags: []).isEmpty)
    }

    @Test func searchTagsIncludeUnreadWorksAndDeduplicateAcrossSources() {
        let unread = LibrarySeries(kavitaSeriesId: 1, title: "Unread", author: "", coverColorHexes: [])
        let local = LibrarySeries(title: "Local", author: "", coverColorHexes: [], isLocal: true)
        let serverMetadata = [1: LibraryPlusMetadata(summary: "", genres: ["Fantasy"], tags: ["School", "Magic"])]
        let localMetadata = [local.id: LibraryPlusMetadata(summary: "", genres: [], tags: ["학교"])]
        let tags = HomeReadTag.ranked(catalog: [unread, local], serverMetadata: serverMetadata,
                                     localMetadata: localMetadata, completedOnly: false)
        #expect(tags.map(\.id) == ["tag:school", "tag:magic"])
        #expect(tags.map(\.count) == [2, 1])
        #expect(HomeReadTag.ranked(catalog: [unread, local], serverMetadata: serverMetadata,
                                  localMetadata: localMetadata).isEmpty)
    }

    @Test func homeTagsCountCompletedWorksOnceAndMergeTranslatedLabels() {
        let first = LibrarySeries(id: UUID(), kavitaSeriesId: 1, title: "First", author: "",
                                  coverColorHexes: [], coverURL: nil, isRead: true)
        let local = LibrarySeries(id: UUID(), kavitaSeriesId: nil, title: "Local", author: "",
                                  coverColorHexes: [], coverURL: nil, isRead: true, isLocal: true)
        let unread = LibrarySeries(id: UUID(), kavitaSeriesId: 2, title: "Unread", author: "",
                                   coverColorHexes: [], coverURL: nil)
        let tags = HomeReadTag.ranked(
            catalog: [first, first, local, unread],
            serverMetadata: [1: LibraryPlusMetadata(summary: "", genres: ["Fantasy"], tags: ["School", "학교", "Magic"]),
                             2: LibraryPlusMetadata(summary: "", genres: [], tags: ["Magic"])],
            localMetadata: [local.id: LibraryPlusMetadata(summary: "", genres: [], tags: ["학교", "Custom"])]
        )
        #expect(tags.map(\.id) == ["tag:school", "tag:custom:custom", "tag:magic"])
        #expect(tags.map(\.count) == [2, 1, 1])
        #expect(tags.first?.name == "tag:school")
        #expect(HomeReadTag.ranked(catalog: [unread], serverMetadata: [:], localMetadata: [:]).isEmpty)
    }

    @Test func translatedInputUsesTheSameIdentityAndPreventsDuplicates() {
        #expect(MetadataCategoryRegistry.identity("Fantasy", kind: .genre) == "genre:fantasy")
        #expect(MetadataCategoryRegistry.identity(" 판타지 ", kind: .genre) == "genre:fantasy")
        #expect(MetadataCategoryRegistry.contains(["Fantasy"], value: "판타지", kind: .genre))
        #expect(MetadataCategoryRegistry.contains(["School"], value: "학교", kind: .tag))
        #expect(MetadataCategoryRegistry.identity("학교", kind: .genre) !=
            MetadataCategoryRegistry.identity("학교", kind: .tag))
    }

    @Test func storedIdentityDisplaysInTheSelectedLanguageAndMatchesHomeCards() {
        #expect(MetadataLocalization.displayName("genre:fantasy", language: .korean) == "판타지")
        #expect(MetadataLocalization.displayName("genre:fantasy", language: .english) == "Fantasy")
        #expect(MetadataLocalization.displayName("판타지", language: .english) == "Fantasy")
        #expect(HomeGenre.fantasy.matches(["판타지"]))
        #expect(HomeGenre.sciFi.matches(["SF"]))
        #expect(HomeGenre.sciFi.matches(["science fiction"]))
        #expect(!HomeGenre.fantasy.matches(["다크 판타지 모음"]))
        #expect(LibraryPlusCurator.labels(["판타지"]) == LibraryPlusCurator.labels(["Fantasy"]))
        #expect(LibraryPlusCurator.labels(["학교"], kind: .tag) ==
            LibraryPlusCurator.labels(["School"], kind: .tag))
    }

    @Test func decodingOldMetadataDeduplicatesEquivalentNamesWithoutChangingSourceSpelling() throws {
        let json = Data(#"{"summary":"Summary","genres":["Fantasy","판타지","FANTASY","SF","Sci-Fi"],"tags":["School","학교"]}"#.utf8)
        let metadata = try JSONDecoder().decode(LibraryPlusMetadata.self, from: json)
        #expect(metadata.genres == ["Fantasy", "SF"])
        #expect(metadata.tags == ["School"])
        #expect(try JSONDecoder().decode(LibraryPlusMetadata.self,
                                        from: JSONEncoder().encode(metadata)) == metadata)
    }

    @Test func unknownNamesRemainUserDefinedAndPunctuationKeepsItsMeaning() {
        #expect(MetadataCategoryRegistry.storageValue("  내 취향  ", kind: .tag) == "내 취향")
        #expect(MetadataLocalization.displayName("내 취향", language: .english) == "내 취향")
        #expect(MetadataCategoryRegistry.identity("A+B", kind: .tag) !=
            MetadataCategoryRegistry.identity("AB", kind: .tag))
        #expect(MetadataCategoryRegistry.cleaned(["MY   TAG", "my tag"], kind: .tag) == ["MY   TAG"])
    }

    @Test func additionalLanguagesAndAmbiguousTranslationsDoNotChangeIDs() {
        let catalog = MetadataCategoryRegistry.Catalog(entries: [
            .init(id: "fantasy", englishName: "Fantasy",
                  localizedNames: ["ko": "판타지", "ja": "ファンタジー"]),
            .init(id: "first", englishName: "First", localizedNames: ["ko": "공통 이름"]),
            .init(id: "second", englishName: "Second", localizedNames: ["ko": "공통 이름"]),
        ])
        #expect(catalog.candidates("ファンタジー", kind: .genre).map(\.id) == ["fantasy"])
        #expect(catalog.candidates("공통 이름", kind: .tag).map(\.id) == ["first", "second"])
        #expect(catalog.candidates("tag:first", kind: .tag).map(\.id) == ["first"])
        #expect(catalog.candidates("genre:first", kind: .tag).isEmpty)
    }
}
