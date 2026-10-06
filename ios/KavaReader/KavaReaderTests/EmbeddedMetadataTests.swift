import Foundation
import XCTest
@testable import KavaReader

@MainActor
final class EmbeddedMetadataTests: XCTestCase {
    private let comic = Data(base64Encoded: "UEsDBBQAAAAIACEdQl0zMwpxPwAAAEQAAAAFAAAAMS5wbmfrDPBz5+WS4mJgYOD19HAJAtKMIMzBAiS3yvAwASluTxfHkIpbySk/+BkYWRkZ1SUepwGFGTxd/VzWOSU0AQBQSwMEFAAAAAgAIR1CXcnbfzxcAAAAdQAAAA0AAABDb21pY0luZm8ueG1ss3HOz81M9sxLy7ezcU/NK0q1c0vMK0ksrtRRcEwpS80rKS1K1VFIg4jZ6EOU2IQkphfb+SamZyZbKwQnZ+Tn59jog8VsgktzcxOLKu0cFYpL8ouAOmACNvoImwBQSwECFAMUAAAACAAhHUJdMzMKcT8AAABEAAAABQAAAAAAAAAAAAAAgAEAAAAAMS5wbmdQSwECFAMUAAAACAAhHUJdydt/PFwAAAB1AAAADQAAAAAAAAAAAAAAgAFiAAAAQ29taWNJbmZvLnhtbFBLBQYAAAAAAgACAG4AAADpAAAAAAA=")!
    private let epub = Data(base64Encoded: "UEsDBBQAAAAIACEdQl1vYassFgAAABQAAAAIAAAAbWltZXR5cGVLLCjIyUxOLMnMz9NPLShN0q7KLAAAUEsDBBQAAAAIACEdQl3JF3Q9NwAAAE4AAAAWAAAATUVUQS1JTkYvY29udGFpbmVyLnhtbLNJzs8rSczMSy2ysynKzy9Jy8xJLUYwFdJKc3J0CxJLMmyVkvLzs/XyC9KU9O1s9JHU6iOMAABQSwMEFAAAAAgAIR1CXeoColz9AAAAtQEAAAgAAABib29rLm9wZmWRSW7DMAxFryJo2zZCtoYtIJvs2k1OQFOMzUYTJKZIbl8PiRugO+E/4nFQmwEvMJC6BR9r47DTo0hujMnX4nepDMahIU+BolSz3+2Ntm0gAQcCtnXYCIsne2RP6iv9kG/NFs4YC4GkYg9XGVNZ4DOacb3234RijxAF6n3hz+yVn5ApIqkjo3CK/+ocVSycZ2YPqk/pspS8xsvYKkKgTiN47gs1AkPVClOUab9Of8LA+K5OOKbktbGt+Vs1QOQz1akdCwXFrtN9cnetxkLn9b27jRK8VoEcw4fc89QJcvaMME9gFvw2nXpVb8KaOdLqnVyTejMuhQ9sHn9lfwFQSwMEFAAAAAgAIR1CXZAotFMZAAAAHgAAAAoAAABib2R5LnhodG1ss8koyc2xs0nKT6m0C0mtKLHRBzNt9MHiAFBLAQIUAxQAAAAIACEdQl1vYassFgAAABQAAAAIAAAAAAAAAAAAAACAAQAAAABtaW1ldHlwZVBLAQIUAxQAAAAIACEdQl3JF3Q9NwAAAE4AAAAWAAAAAAAAAAAAAACAATwAAABNRVRBLUlORi9jb250YWluZXIueG1sUEsBAhQDFAAAAAgAIR1CXeoColz9AAAAtQEAAAgAAAAAAAAAAAAAAIABpwAAAGJvb2sub3BmUEsBAhQDFAAAAAgAIR1CXZAotFMZAAAAHgAAAAoAAAAAAAAAAAAAAIABygEAAGJvZHkueGh0bWxQSwUGAAAAAAQABADoAAAACwIAAAAA")!

    func testDeclaredSubjectsTagsAndSourcePriority() throws {
        let xml = try EpubXML.parse(Data("""
        <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
          <dc:subject>Science Fiction</dc:subject><dc:subject>science fiction</dc:subject>
          <dc:description>A &amp; B</dc:description>
          <meta name="calibre:tags" content="Magic, School;Magic"/>
          <meta property="unknown:category">Invented</meta>
        </metadata>
        """.utf8))
        let primary = EmbeddedMetadataReader.epub(xml)
        XCTAssertEqual(primary.genres, ["Science Fiction"])
        XCTAssertEqual(primary.tags, ["Magic", "School"])
        XCTAssertEqual(primary.summary, "A & B")
        let external = ExternalSeriesMetadata(aniListID: 1, sourceTitle: "Other",
            sourceURL: URL(string: "https://anilist.co/manga/1")!, genres: ["Romance"], tags: ["School"])
        XCTAssertEqual(LibraryPlusMetadata.resolved(primary: primary, external: external), primary)
        let tagsOnly = LibraryPlusMetadata(summary: "", genres: [], tags: ["Magic"])
        XCTAssertEqual(LibraryPlusMetadata.resolved(primary: tagsOnly, external: external), tagsOnly)
        XCTAssertEqual(LibraryPlusMetadata.resolved(primary: .init(summary: "File summary", genres: [], tags: []),
            external: external).genres, ["Romance"])
        XCTAssertThrowsError(try EmbeddedMetadataReader.comicXML(Data("<broken>".utf8)))
    }

    func testManualConnectionOverridesEmbeddedCategoriesAndDisconnectRestoresThem() {
        let embedded = LibraryPlusMetadata(summary: "File summary", genres: ["Drama"], tags: ["School"])
        let automatic = ExternalSeriesMetadata(aniListID: 1, sourceTitle: "Automatic",
            sourceURL: URL(string: "https://anilist.co/manga/1")!, genres: ["Action"], tags: [])
        let linked = ExternalSeriesMetadata(aniListID: 2, sourceTitle: "Selected",
            sourceURL: URL(string: "https://anilist.co/manga/2")!, genres: ["Fantasy"], tags: ["Magic"])
        let manual = ManualSeriesMetadataRecord(metadata: linked, updatedAt: Date())
        let resolved = LibraryPlusMetadata.resolved(primary: embedded, external: automatic, manual: manual)
        XCTAssertEqual(resolved.genres, ["Fantasy"])
        XCTAssertEqual(resolved.tags, ["Magic"])
        XCTAssertEqual(resolved.summary, "File summary")
        XCTAssertEqual(LibraryPlusMetadata.resolved(primary: embedded, external: automatic), embedded)
        let disabled = ManualSeriesMetadataRecord(metadata: nil, updatedAt: Date())
        XCTAssertEqual(LibraryPlusMetadata.resolved(primary: embedded, external: automatic, manual: disabled), embedded)
        let unclassified = ExternalSeriesMetadata(aniListID: 3, sourceTitle: "Unclassified",
            sourceURL: URL(string: "https://anilist.co/manga/3")!, genres: [], tags: [])
        let empty = LibraryPlusMetadata.resolved(primary: embedded, external: automatic,
            manual: .init(metadata: unclassified, updatedAt: Date()))
        XCTAssertFalse(empty.hasCategories)
        XCTAssertEqual(empty.summary, embedded.summary)
    }

    func testImportsAndLegacyBackfillPreserveProgress() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let root = folder.appendingPathComponent("library")
        let store = LocalComicStore(root: root)
        let source = folder.appendingPathComponent("comic.cbz")
        try comic.write(to: source)
        let didImport = try await store.importFile(source, group: nil)
        XCTAssertTrue(didImport)
        // Retain metadata backfill coverage for an existing EPUB catalog.
        let epubSource = root.appendingPathComponent("legacy.epub")
        try epub.write(to: epubSource)
        let publication = try EpubPublication(archive: ComicArchive(url: epubSource, includeAllEntries: true))
        let volume = LocalComicVolume(id: UUID(), title: "book", archive: "legacy.epub", digest: "legacy",
                                      pageCount: publication.sections.count * 1000, bytes: Int64(epub.count),
                                      epub: publication, embeddedMetadata: publication.embeddedMetadata, metadataVersion: 1)
        var catalogComics = try await store.all()
        catalogComics.append(LocalComic(id: UUID(), title: publication.title, volumes: [volume], addedAt: Date()))
        try JSONEncoder().encode(catalogComics).write(to: root.appendingPathComponent("catalog.json"))
        let existingStore = LocalComicStore(root: root)
        let imported = try await existingStore.all()
        XCTAssertEqual(imported[0].volumes[0].pageCount, 1) // ComicInfo.xml is never a page.
        XCTAssertEqual(imported[0].embeddedMetadata.genres, ["Fantasy", "Adventure"])
        XCTAssertEqual(imported[1].embeddedMetadata.genres, ["Fantasy", "Science Fiction"])
        XCTAssertEqual(imported[1].embeddedMetadata.tags, ["Magic", "School"])
        try await existingStore.edit(imported[0].id, favourite: true)
        try await existingStore.saveProgress(seriesID: imported[0].id, chapterID: imported[0].volumes[0].id, page: 1)
        // Simulate a catalog from before embedded metadata was stored.
        let catalog = root.appendingPathComponent("catalog.json")
        var legacy = try JSONSerialization.jsonObject(with: Data(contentsOf: catalog)) as! [[String: Any]]
        for index in legacy.indices {
            var volumes = legacy[index]["volumes"] as! [[String: Any]]
            for v in volumes.indices {
                volumes[v].removeValue(forKey: "embeddedMetadata")
                volumes[v].removeValue(forKey: "metadataVersion")
                if var publication = volumes[v]["epub"] as? [String: Any] {
                    publication.removeValue(forKey: "embeddedMetadata")
                    volumes[v]["epub"] = publication
                }
            }
            legacy[index]["volumes"] = volumes
        }
        try JSONSerialization.data(withJSONObject: legacy).write(to: catalog)
        let migrated = try await LocalComicStore(root: root).metadataCatalog()
        XCTAssertTrue(migrated[0].favourite)
        XCTAssertEqual(migrated[0].volumes[0].page, 1)
        XCTAssertEqual(migrated[0].embeddedMetadata.genres, imported[0].embeddedMetadata.genres)
        XCTAssertEqual(migrated[1].embeddedMetadata, imported[1].embeddedMetadata)
        let reopened = try await LocalComicStore(root: root).all()
        XCTAssertEqual(reopened[1].volumes[0].metadataVersion, 1)
    }

    func testRecommendationsMatchAcrossSourcesWithoutFakeServerIDs() {
        let seed = LibrarySeries(title: "File favourite", author: "", coverColorHexes: [], isLocal: true)
        let local = LibrarySeries(title: "File candidate", author: "", coverColorHexes: [], isLocal: true)
        let server = LibrarySeries(kavitaSeriesId: 7, title: "Kavita candidate", author: "", coverColorHexes: [])
        let unknown = LibrarySeries(title: "Unknown", author: "", coverColorHexes: [], isLocal: true)
        let fantasy = LibraryPlusMetadata(summary: "", genres: ["Fantasy"], tags: [])
        let curator = LibraryPlusCurator(series: [seed, local, server, unknown], metadata: [7: fantasy],
            readingIDs: [], favouriteIDs: [], recent: [], day: 100,
            localMetadata: [seed.id: fantasy, local.id: fantasy], localFavouriteIDs: [seed.id])
        XCTAssertEqual(Set(curator.recommended.map(\.id)), [local.id, server.id])
        XCTAssertNotEqual(curator.rank(local.id.uuidString), curator.rank(unknown.id.uuidString))
        XCTAssertTrue(curator.rows(featured: [], continuing: []).flatMap(\.items).contains { $0.id == seed.id })
        XCTAssertNil(local.kavitaSeriesId)
    }

    func testNovelLookupIsOptInAndAmbiguousTitlesStayUnmatched() throws {
        let data = Data(#"{"data":{"Page":{"media":[{"id":1,"title":{"romaji":"File Novel"},"format":"NOVEL","genres":["Fantasy"]}]}}}"#.utf8)
        XCTAssertNil(try AniListMetadataService.match(data: data, title: "File Novel"))
        XCTAssertEqual(try AniListMetadataService.match(data: data, title: "File Novel", includeNovels: true)?.aniListID, 1)
        XCTAssertTrue(try AniListMetadataService.searchPage(data: data).candidates.isEmpty)
        XCTAssertEqual(try AniListMetadataService.searchPage(data: data, includeNovels: true).candidates.count, 1)
    }
}
