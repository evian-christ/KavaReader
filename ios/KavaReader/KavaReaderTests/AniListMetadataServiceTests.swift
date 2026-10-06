import Foundation
@testable import KavaReader
import Testing

struct AniListMetadataServiceTests {
    @MainActor
    @Test func humanSearchKeepsAmbiguousAndUnclassifiedCandidatesAndExcludesNovels() throws {
        let data = Data("""
        {"data":{"Page":{"pageInfo":{"hasNextPage":true},"media":[
          {"id":1,"title":{"romaji":"Same Name","native":"原題"},"format":"MANGA",
           "startDate":{"year":1991},"coverImage":{"large":"https://example.com/cover.jpg"},
           "staff":{"edges":[
             {"role":"Story & Art","node":{"name":{"full":"Author","native":"作者"}}},
             {"role":"Translator (English)","node":{"name":{"full":"Translator"}}}
           ]},"genres":[],"tags":[]},
          {"id":2,"title":{"romaji":"Same Name"},"format":"MANGA","genres":["Drama"],
           "tags":[{"name":"Hidden Identity","rank":95,"isMediaSpoiler":true},
                   {"name":"School","rank":90,"isMediaSpoiler":false}]},
          {"id":3,"title":{"romaji":"Same Name"},"format":"NOVEL"}
        ]}}}
        """.utf8)
        let page = try AniListMetadataService.searchPage(data: data)
        #expect(page.candidates.map(\.id) == [1, 2])
        #expect(page.hasNextPage)
        #expect(page.candidates[0].metadata.genres.isEmpty)
        #expect(page.candidates[0].creators == ["作者"])
        #expect(page.candidates[0].year == 1991)
        #expect(page.candidates[1].metadata.tags == ["School"])
        // Automatic matching remains conservative, independently of human selection.
        #expect(try AniListMetadataService.match(data: data, title: "Same Name") == nil)
    }

    @MainActor
    @Test func graphQLErrorIsNotTreatedAsAnEmptyHumanSearch() {
        let data = Data(#"{"data":null,"errors":[{"message":"Unavailable"}]}"#.utf8)
        #expect(throws: ExternalLookupError.self) {
            try AniListMetadataService.searchPage(data: data)
        }
    }

    @MainActor
    @Test func uniqueExactAliasUsesNonSpoilerTags() throws {
        let data = Data("""
        {"data":{"Page":{"media":[
          {"id":42,"title":{"romaji":"Magic School","english":null,"native":null},
           "synonyms":["마법 학교"],"genres":["Fantasy"],
           "tags":[
             {"name":"Magic","rank":90,"isGeneralSpoiler":false,"isMediaSpoiler":false},
             {"name":"Secret Villain","rank":95,"isGeneralSpoiler":false,"isMediaSpoiler":true},
             {"name":"Minor Theme","rank":20,"isGeneralSpoiler":false,"isMediaSpoiler":false}
           ]}
        ]}}}
        """.utf8)

        let result = try AniListMetadataService.match(data: data, title: "마법-학교")
        #expect(result?.aniListID == 42)
        #expect(result?.genres == ["Fantasy"])
        #expect(result?.tags == ["Magic"])
    }

    @MainActor
    @Test func ambiguousOrPartialTitlesAreNotMatched() throws {
        let ambiguous = Data("""
        {"data":{"Page":{"media":[
          {"id":1,"title":{"romaji":"Same Name"},"genres":["Action"]},
          {"id":2,"title":{"romaji":"Same Name"},"genres":["Drama"]}
        ]}}}
        """.utf8)
        #expect(try AniListMetadataService.match(data: ambiguous, title: "Same Name") == nil)

        let partial = Data("""
        {"data":{"Page":{"media":[
          {"id":3,"title":{"romaji":"Same Name Returns"},"genres":["Action"]}
        ]}}}
        """.utf8)
        #expect(try AniListMetadataService.match(data: partial, title: "Same Name") == nil)
    }

    @MainActor
    @Test func kavitaCategoriesTakePriority() throws {
        let external = try ExternalSeriesMetadata(aniListID: 42, sourceTitle: "Example",
                                                  sourceURL: #require(URL(string: "https://anilist.co/manga/42")),
                                                  genres: ["Fantasy"], tags: ["Magic"])
        let kavita = LibraryPlusMetadata(summary: "Kavita summary", genres: ["Drama"], tags: [])
        let resolved = LibraryPlusMetadata.resolved(kavita: kavita, external: external)
        #expect(resolved.genres == ["Drama"])
        #expect(resolved.tags.isEmpty)

        let empty = LibraryPlusMetadata(summary: "Kavita summary", genres: [], tags: [])
        let supplemented = LibraryPlusMetadata.resolved(kavita: empty, external: external)
        #expect(supplemented.summary == "Kavita summary")
        #expect(supplemented.genres == ["Fantasy"])
    }
}
