import XCTest
@testable import KavaReader

@MainActor
final class EpubTests: XCTestCase {
    private let epub3 = Data(base64Encoded: "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")!
    private let textOnly = Data(base64Encoded: "UEsDBBQAAAAAAHEaQl1vYassFAAAABQAAAAIAAAAbWltZXR5cGVhcHBsaWNhdGlvbi9lcHViK3ppcFBLAwQUAAAACABxGkJdGvS6VYEAAAC4AAAAFgAAAE1FVEEtSU5GL2NvbnRhaW5lci54bWxNjUEOwjAMBL9S5YpK7lHaL4DEC0zqQkRiW7Ejld+DECrc9jA7ExOTQSZsw1YL6eR6o8CgWQNBRQ2WAgvSwqlXJAsfLOw3N8fGbGsuqL85rL2UUcDukzudL14gPeCGR5bVDRWXDKM9BScHIiUnsMzkGa+i4xc9vDvOz9H/2f1enV9QSwMEFAAAAAgAcRpCXTwQeB47AQAAWgIAAA8AAABPUFMvcGFja2FnZS5vcGadkktOwzAQhq8SWcoKkUlBiLZKIvHoQYw9oVYd27KHPnZsuqnYcAFWHAB2nAm1dyCPpmrFBrGz//H//TMjZ46LGX/EaFlpE3I2JXJjgMVikSjpysT6R7hI02uwrmTRHH1Q1uTsMklZkVVIXHLinXksxcHvnrxuvVIAaqzQUIBBMoDaJcWYFGksduuX7eZ9t/mKtp/rDA5680J45GR9sX17/f54bou9lEGfW3fAjSoxUJEpwipSMmcBhTWSRVOPZc4IlwSdlCynVGkWVSgVP6eVw5xx57QSnOqhoC2f1aMwOMKVygc6ocWT+3h0FY/u4slNfDuMh+n/yIFWGntyewnwYO0sESGcstrYRj22Gz7vzfXx7y1EzluHnhSGDgLNRg97DE4Z7GJqdp3UJnRbgF/6ftkNYm+E/YcqfgBQSwMEFAAACAgAcRpCXcKvxFeIAAAApQAAABUAAABPUFMvdGV4dC/tlZzquIAueGh0bWwljUEOwiAQRa9COAAT4wozcBdrR2lKC4FJaC/jzpWudNM7tYfQyvK///M+Oh68mAY/ZiMdczwBlFJUOaqQbnDQWsO0b6RFR+fWInfsyW7vp9juD4Qa0XdjLxJ5IzPPnrIjYilcoquRSkGF0ITQq0vOEixC1TWhnS3Gv3D9LOtrQYi/tnLYr+0XUEsDBBQAAAAIAHEaQl121XY2ZQAAAHkAAAAVAAAAT1BTL3RleHQvc2Vjb25kLnhodG1ss8koyc1RqMjNySu2VcooKSmw0tcvLy/XKzfWyy9K1ze0tLTUrwCpUbKzyUhNTLGzKcksyUm1ez1xxpvlOxTezFtqow8RsdGHyCflp1Ta2RTAVLzevOP1mh02+gVABRApfZBxdgBQSwMEFAAAAAgAcRpCXQAAAAACAAAAAAAAABMAAABPUFMvc3R5bGVzL2Jvb2suY3NzAwBQSwMEFAAAAAgAcRpCXY9FgEKRAAAAwgAAAA0AAABPUFMvbmF2LnhodG1ss8koyc1RqMjNySu2VcooKSmw0tcvLy/XKzfWyy9K1ze0tLTUrwCpUbKzScpPqbSzyUsss7PJz7Gzycm0s0lUyChKTbNVKkmtKNFXdXVRtTRVtXRWdXVUdbJQtTDQg2p9s2m1wpt5S230E+1s9EH6MPQWpybn56XA1L+eOOPN8h2oWvRBduqDbdeHuEQfpNgOAFBLAQIUAxQAAAAAAHEaQl1vYassFAAAABQAAAAIAAAAAAAAAAAAAACAAQAAAABtaW1ldHlwZVBLAQIUAxQAAAAIAHEaQl0a9LpVgQAAALgAAAAWAAAAAAAAAAAAAACAAToAAABNRVRBLUlORi9jb250YWluZXIueG1sUEsBAhQDFAAAAAgAcRpCXTwQeB47AQAAWgIAAA8AAAAAAAAAAAAAAIAB7wAAAE9QUy9wYWNrYWdlLm9wZlBLAQIUAxQAAAgIAHEaQl3Cr8RXiAAAAKUAAAAVAAAAAAAAAAAAAACAAVcCAABPUFMvdGV4dC/tlZzquIAueGh0bWxQSwECFAMUAAAACABxGkJddtV2NmUAAAB5AAAAFQAAAAAAAAAAAAAAgAESAwAAT1BTL3RleHQvc2Vjb25kLnhodG1sUEsBAhQDFAAAAAgAcRpCXQAAAAACAAAAAAAAABMAAAAAAAAAAAAAAIABqgMAAE9QUy9zdHlsZXMvYm9vay5jc3NQSwECFAMUAAAACABxGkJdj0WAQpEAAADCAAAADQAAAAAAAAAAAAAAgAHdAwAAT1BTL25hdi54aHRtbFBLBQYAAAAABwAHALkBAACZBAAAAAA=")!
    private let epub2 = Data(base64Encoded: "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")!
    private let encrypted = Data(base64Encoded: "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")!
    private let broken = Data(base64Encoded: "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")!
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testSpineOrderMetadataCoverAndEncodedPaths() throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("book.epub")
        try epub3.write(to: url)
        let archive = try ComicArchive(url: url, includeAllEntries: true)
        let book = try EpubPublication(archive: archive)
        XCTAssertEqual(book.title, "테스트 책")
        XCTAssertEqual(book.author, "작가")
        XCTAssertEqual(book.sections.map(\.path), ["OPS/text/한글.xhtml", "OPS/text/second.xhtml"])
        XCTAssertEqual(book.sections.map(\.title), ["첫 장", "둘째 장"])
        XCTAssertEqual(book.coverPath, "OPS/images/cover.png")
        XCTAssertEqual(book.resources["OPS/styles/book.css"], "text/css")
        XCTAssertEqual(try archive.resource(named: "OPS/styles/book.css"), Data())
        XCTAssertEqual(try EpubPublication.path("../images/cover.png", relativeTo: "OPS/text"), "OPS/images/cover.png")
        XCTAssertThrowsError(try EpubPublication.path("../../outside", relativeTo: "OPS"))
        XCTAssertThrowsError(try EpubPublication.path("https://example.com/book", relativeTo: "OPS"))
    }

    func testEpub2CoverAndTextOnlyPublication() throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("book.epub")
        try epub2.write(to: url)
        let old = try EpubPublication(archive: ComicArchive(url: url, includeAllEntries: true))
        XCTAssertEqual(old.coverPath, "OPS/images/cover.png")
        try textOnly.write(to: url)
        let text = try EpubPublication(archive: ComicArchive(url: url, includeAllEntries: true))
        XCTAssertNil(text.coverPath)
        XCTAssertEqual(text.sections.count, 2)
    }

    func testEncryptedAndBrokenSpinesAreRejected() throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("book.epub")
        for fixture in [encrypted, broken] {
            try fixture.write(to: url)
            let archive = try ComicArchive(url: url, includeAllEntries: true)
            XCTAssertThrowsError(try EpubPublication(archive: archive))
        }
        let entities = Data("<!DOCTYPE x [<!ENTITY e 'test'>]><x>&e;</x>".utf8)
        XCTAssertThrowsError(try EpubXML.parse(entities))
    }

    func testExistingEpubResourcesProgressAndResetSurviveReopening() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("book.epub")
        try textOnly.write(to: url)
        let library = folder.appendingPathComponent("library")
        // Seed a previously imported catalog: new EPUB imports are disabled.
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        try textOnly.write(to: library.appendingPathComponent("book.epub"))
        let publication = try EpubPublication(archive: ComicArchive(url: url, includeAllEntries: true))
        let oldVolume = LocalComicVolume(id: UUID(), title: "book", archive: "book.epub", digest: "legacy",
                                        pageCount: publication.sections.count * 1000, bytes: Int64(textOnly.count), epub: publication)
        let oldComic = LocalComic(id: UUID(), title: publication.title, volumes: [oldVolume],
                                  author: publication.author, coverAvailable: false, addedAt: Date())
        try JSONEncoder().encode([oldComic]).write(to: library.appendingPathComponent("catalog.json"))
        let store = LocalComicStore(root: library)
        let comics = try await store.all()
        let comic = try XCTUnwrap(comics.first)
        let volume = try XCTUnwrap(comic.volumes.first)
        XCTAssertEqual(comic.title, "테스트 책")
        XCTAssertEqual(comic.author, "작가")
        let cover = await store.coverURL(comic.id)
        XCTAssertNil(cover)
        let detail = try await store.detail(comic.id)
        XCTAssertTrue(detail.chapters[0].isEpub)
        let location = EpubLocation(section: 1, fraction: 0.45)
        try await store.saveEpubLocation(seriesID: comic.id, volumeID: volume.id, location: location)
        let reopened = LocalComicStore(root: library)
        let restored = try await reopened.epubVolume(volume.id)
        XCTAssertEqual(restored.epubLocation, location)
        XCTAssertEqual(restored.page, 1450)
        let resource = try await reopened.epubResource(volumeID: volume.id, path: "OPS/text/한글.xhtml")
        XCTAssertEqual(resource.mime, "application/xhtml+xml")
        XCTAssertTrue(String(decoding: resource.data, as: UTF8.self).contains("첫 본문"))
        do {
            _ = try await reopened.epubResource(volumeID: volume.id, path: "META-INF/container.xml")
            XCTFail("The reader must only serve manifest resources")
        } catch {}
        try await reopened.edit(comic.id, read: false)
        let reset = try await reopened.epubVolume(volume.id)
        XCTAssertNil(reset.epubLocation)
        XCTAssertEqual(reset.page, 0)
        try await reopened.delete(comic.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testNewEpubImportIsRejectedWithoutCreatingLibrary() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("book.EPUB")
        try textOnly.write(to: source)
        let library = folder.appendingPathComponent("library")
        let store = LocalComicStore(root: library)
        do {
            _ = try await store.importFile(source, group: nil)
            XCTFail("New EPUB imports must be rejected")
        } catch LocalComicImport.Failure.unsupportedFormat {}
        let comics = try await store.all()
        XCTAssertTrue(comics.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: library.path))
        XCTAssertEqual(try Data(contentsOf: source), textOnly)
    }

    func testExistingComicCatalogDecodesWithoutEpubFields() throws {
        let oldVolume = LocalComicVolume(id: UUID(), title: "1권", archive: "old.cbz", digest: "digest", pageCount: 20, bytes: 100)
        let comic = LocalComic(id: UUID(), title: "기존 만화", volumes: [oldVolume], addedAt: Date())
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(comic)) as? [String: Any])
        object.removeValue(forKey: "author")
        object.removeValue(forKey: "coverAvailable")
        let decoded = try JSONDecoder().decode(LocalComic.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(decoded.title, comic.title)
        XCTAssertNil(decoded.author)
        XCTAssertNil(decoded.volumes[0].epub)
        XCTAssertNil(decoded.volumes[0].epubLocation)
    }
}
