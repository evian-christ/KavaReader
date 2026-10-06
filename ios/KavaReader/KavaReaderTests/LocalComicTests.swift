import XCTest
@testable import KavaReader

@MainActor
final class LocalComicTests: XCTestCase {
    private let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")!
    private let deflated = Data(base64Encoded: "UEsDBBQAAAAIANEUQl0zMwpxPwAAAEQAAAAGAAAAMTAucG5n6wzwc+flkuJiYGDg9fRwCQLSjCDMwQIkt8rwMAEpbk8Xx5CKW8kpP/gZGFkZGdUlHqcBhRk8Xf1c1jklNAEAUEsDBBQAAAAIANEUQl0zMwpxPwAAAEQAAAAFAAAAMi5wbmfrDPBz5+WS4mJgYOD19HAJAtKMIMzBAiS3yvAwASluTxfHkIpbySk/+BkYWRkZ1SUepwGFGTxd/VzWOSU0AQBQSwMEFAAAAAgA0RRCXTMzCnE/AAAARAAAAAUAAAAxLnBuZ+sM8HPn5ZLiYmBg4PX0cAkC0owgzMECJLfK8DABKW5PF8eQilvJKT/4GRhZGRnVJR6nAYUZPF39XNY5JTQBAFBLAwQUAAAACADRFEJd4taIDQgAAAAGAAAAEAAAAF9fTUFDT1NYLy5fMS5wbmfLTM/LL0oFAFBLAQIUAxQAAAAIANEUQl0zMwpxPwAAAEQAAAAGAAAAAAAAAAAAAACAAQAAAAAxMC5wbmdQSwECFAMUAAAACADRFEJdMzMKcT8AAABEAAAABQAAAAAAAAAAAAAAgAFjAAAAMi5wbmdQSwECFAMUAAAACADRFEJdMzMKcT8AAABEAAAABQAAAAAAAAAAAAAAgAHFAAAAMS5wbmdQSwECFAMUAAAACADRFEJd4taIDQgAAAAGAAAAEAAAAAAAAAAAAAAAgAEnAQAAX19NQUNPU1gvLl8xLnBuZ1BLBQYAAAAABAAEANgAAABdAQAAAAA=")!
    private let stored = Data(base64Encoded: "UEsDBBQAAAAAANEUQl0zMwpxRAAAAEQAAAAGAAAAMTAucG5niVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYIJQSwMEFAAAAAAA0RRCXTMzCnFEAAAARAAAAAUAAAAyLnBuZ4lQTkcNChoKAAAADUlIRFIAAAABAAAAAQgEAAAAtRwMAgAAAAtJREFUeNpjZPgPAAEFAQEnGONmAAAAAElFTkSuQmCCUEsDBBQAAAAAANEUQl0zMwpxRAAAAEQAAAAFAAAAMS5wbmeJUE5HDQoaCgAAAA1JSERSAAAAAQAAAAEIBAAAALUcDAIAAAALSURBVHjaY2T4DwABBQEBJxjjZgAAAABJRU5ErkJgglBLAwQUAAAAAADRFEJd4taIDQYAAAAGAAAAEAAAAF9fTUFDT1NYLy5fMS5wbmdpZ25vcmVQSwECFAMUAAAAAADRFEJdMzMKcUQAAABEAAAABgAAAAAAAAAAAAAAgAEAAAAAMTAucG5nUEsBAhQDFAAAAAAA0RRCXTMzCnFEAAAARAAAAAUAAAAAAAAAAAAAAIABaAAAADIucG5nUEsBAhQDFAAAAAAA0RRCXTMzCnFEAAAARAAAAAUAAAAAAAAAAAAAAIABzwAAADEucG5nUEsBAhQDFAAAAAAA0RRCXeLWiA0GAAAABgAAABAAAAAAAAAAAAAAAIABNgEAAF9fTUFDT1NYLy5fMS5wbmdQSwUGAAAAAAQABADYAAAAagEAAAAA")!

    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testStoredAndDeflatedArchivesUseNaturalPageOrderAndIgnoreResourceForks() throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        for data in [stored, deflated] {
            let file = folder.appendingPathComponent("comic.cbz")
            try data.write(to: file)
            let archive = try ComicArchive(url: file)
            XCTAssertEqual(archive.entries.map(\.name), ["1.png", "2.png", "10.png"])
            XCTAssertEqual(try archive.imageData(at: 0), png)
            XCTAssertEqual(try archive.imageData(at: 2), png)
            XCTAssertThrowsError(try archive.imageData(at: 3))
        }
    }

    func testCorruptAndEncryptedArchivesFailWithoutReturningPageData() throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("bad.cbz")
        try Data([0, 1, 2]).write(to: file)
        XCTAssertThrowsError(try ComicArchive(url: file))
        var corrupt = stored
        corrupt[36] ^= 1 // First stored image payload, leaving the central checksum unchanged.
        try corrupt.write(to: file)
        let archive = try ComicArchive(url: file)
        XCTAssertThrowsError(try archive.imageData(at: 2)) // 10.png sorts last.
        var encrypted = stored
        let signature = Data([0x50, 0x4b, 0x01, 0x02])
        let central = try XCTUnwrap(encrypted.range(of: signature)).lowerBound
        encrypted[central + 8] |= 1
        try encrypted.write(to: file)
        XCTAssertThrowsError(try ComicArchive(url: file))
    }

    func testImportDuplicateProgressFavouriteAndPersistenceWithoutServer() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("01.cbz")
        try deflated.write(to: source)
        let libraryFolder = folder.appendingPathComponent("library")
        let store = LocalComicStore(root: libraryFolder)
        let imported = try await store.importFile(source, group: "작품")
        let duplicate = try await store.importFile(source, group: "다른 작품")
        XCTAssertTrue(imported)
        XCTAssertFalse(duplicate)
        let comics = try await store.all()
        XCTAssertEqual(comics.count, 1)
        let comic = try XCTUnwrap(comics.first)
        let chapter = try XCTUnwrap(comic.volumes.first)
        try await store.edit(comic.id, favourite: true)
        try await store.saveProgress(seriesID: comic.id, chapterID: chapter.id, page: 2)
        let reopened = LocalComicStore(root: libraryFolder)
        let restored = try await reopened.all()
        XCTAssertTrue(restored[0].favourite)
        XCTAssertEqual(restored[0].volumes[0].page, 2)
        let page = try await reopened.pageData(chapterID: chapter.id, page: 2)
        XCTAssertEqual(page, png)
        try await reopened.delete(comic.id)
        let remaining = try await reopened.all()
        XCTAssertTrue(remaining.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testFolderDiscoveryGroupsWorksAndIgnoresUnrelatedFiles() throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let work = folder.appendingPathComponent("작품")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        try stored.write(to: work.appendingPathComponent("02.zip"))
        try deflated.write(to: work.appendingPathComponent("01.cbz"))
        try png.write(to: work.appendingPathComponent("cover.png"))
        let epub = work.appendingPathComponent("book.EPUB")
        try stored.write(to: epub)
        XCTAssertTrue(try LocalComicImport.files(in: [epub]).isEmpty)
        XCTAssertTrue(LocalComicImport.supports(work.appendingPathComponent("comic.CBZ")))
        XCTAssertTrue(LocalComicImport.supports(work.appendingPathComponent("comic.ZIP")))
        let files = try LocalComicImport.files(in: [folder])
        XCTAssertEqual(files.map { $0.url.lastPathComponent }, ["01.cbz", "02.zip"])
        XCTAssertEqual(files.map(\.group), ["작품", "작품"])
    }

    func testUnreadableCatalogIsPreservedInsteadOfOverwrittenByImport() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = folder.appendingPathComponent("library")
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        let catalog = library.appendingPathComponent("catalog.json")
        let original = Data("invalid catalog".utf8)
        try original.write(to: catalog)
        let source = folder.appendingPathComponent("comic.cbz")
        try stored.write(to: source)
        let store = LocalComicStore(root: library)
        do {
            _ = try await store.importFile(source, group: nil)
            XCTFail("A damaged catalog must not be overwritten")
        } catch {}
        XCTAssertEqual(try Data(contentsOf: catalog), original)
    }

    func testMergeAndDeletePreserveOtherWorksArchives() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let a = folder.appendingPathComponent("01.cbz")
        let b = folder.appendingPathComponent("02.cbz")
        try stored.write(to: a)
        try deflated.write(to: b)
        let libraryFolder = folder.appendingPathComponent("library")
        let store = LocalComicStore(root: libraryFolder)
        _ = try await store.importFile(a, group: nil)
        _ = try await store.importFile(b, group: nil)
        let works = try await store.all()
        try await store.merge(works[0].id, into: works[1].id)
        let merged = try await store.all()
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].volumes.count, 2)
        let page = try await store.pageData(chapterID: works[0].volumes[0].id, page: 1)
        XCTAssertEqual(page, png)
        try await store.delete(works[1].id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: libraryFolder.appendingPathComponent(works[0].id.uuidString).path))
    }
}
