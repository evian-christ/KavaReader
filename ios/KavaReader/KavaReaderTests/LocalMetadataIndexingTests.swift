import Foundation
import XCTest
@testable import KavaReader

@MainActor
final class LocalMetadataIndexingTests: XCTestCase {
    func testLocalIndexingWorksWithoutKavitaAndOnlyCountsNecessarySearches() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let primary = LibraryPlusMetadata(summary: "File summary", genres: ["Drama"], tags: ["School"])
        let comics = [comic(title: "Embedded", metadata: primary),
                      comic(title: "File Manga", metadata: .init(summary: "", genres: [], tags: []))]
        try JSONEncoder().encode(comics).write(to: folder.appendingPathComponent("catalog.json"))
        let store = LocalComicStore(root: folder)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LocalIndexingFixtureProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let externalStore = LocalSeriesMetadataStore(directory: folder, session: session)
        let model = LibraryPlusViewModel(localStore: store, localExternalStore: externalStore)
        await model.prepareLocalMetadata().value
        XCTAssertEqual(model.localMetadata[comics[0].id], primary)
        XCTAssertEqual(model.localMetadata[comics[1].id]?.genres, ["Fantasy"])
        XCTAssertEqual(model.localDiagnostics.totalCount, 2)
        XCTAssertEqual(model.localDiagnostics.completedCount, 2)
        XCTAssertEqual(model.localDiagnostics.externalTotalCount, 1)
        XCTAssertEqual(model.localDiagnostics.externalCompletedCount, 1)
        XCTAssertEqual(model.localDiagnostics.externalDeferredCount, 0)
        XCTAssertFalse(model.localDiagnostics.isLoading)
        XCTAssertFalse(model.localDiagnostics.isEnriching)
        XCTAssertNil(model.dailySnapshot) // No Kavita catalog or home preparation is required.

        // Favourite/progress changes preserve the existing indexing task and its completed counts.
        try await store.edit(comics[0].id, favourite: true)
        await model.prepareLocalMetadata().value
        XCTAssertEqual(model.localDiagnostics.externalTotalCount, 1)

        // A fresh model reuses saved matches and has no pending network stage.
        let cachedConfiguration = URLSessionConfiguration.ephemeral
        cachedConfiguration.protocolClasses = [LocalIndexingNoNetworkProtocol.self]
        let cachedSession = URLSession(configuration: cachedConfiguration)
        defer { cachedSession.invalidateAndCancel() }
        let cachedModel = LibraryPlusViewModel(localStore: store,
            localExternalStore: LocalSeriesMetadataStore(directory: folder, session: cachedSession))
        await cachedModel.prepareLocalMetadata().value
        XCTAssertEqual(cachedModel.localMetadata[comics[1].id]?.genres, ["Fantasy"])
        XCTAssertEqual(cachedModel.localDiagnostics.externalTotalCount, 0)
        XCTAssertEqual(cachedModel.localDiagnostics.externalLookupCount, 0)
        XCTAssertFalse(cachedModel.localDiagnostics.isEnriching)
    }

    func testRateLimitedIndexingStopsLoadingAndRetainsPendingCount() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let comic = comic(title: "File Manga", metadata: .init(summary: "", genres: [], tags: []))
        try JSONEncoder().encode([comic]).write(to: folder.appendingPathComponent("catalog.json"))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LocalIndexingLimitedProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let model = LibraryPlusViewModel(localStore: LocalComicStore(root: folder),
            localExternalStore: LocalSeriesMetadataStore(directory: folder, session: session))
        await model.prepareLocalMetadata().value
        XCTAssertEqual(model.localDiagnostics.completedCount, 1)
        XCTAssertEqual(model.localDiagnostics.externalTotalCount, 1)
        XCTAssertEqual(model.localDiagnostics.externalCompletedCount, 0)
        XCTAssertEqual(model.localDiagnostics.externalDeferredCount, 1)
        XCTAssertTrue(model.localDiagnostics.externalRateLimited)
        XCTAssertFalse(model.localDiagnostics.isLoading)
        XCTAssertFalse(model.localDiagnostics.isEnriching)
    }

    private func comic(title: String, metadata: LibraryPlusMetadata) -> LocalComic {
        let id = UUID()
        let volume = LocalComicVolume(id: UUID(), title: title, archive: "unused.cbz", digest: id.uuidString,
            pageCount: 1, bytes: 1, embeddedMetadata: metadata, metadataVersion: 1)
        return LocalComic(id: id, title: title, volumes: [volume], addedAt: Date())
    }
}

private final class LocalIndexingFixtureProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let data = Data(#"{"data":{"Page":{"media":[{"id":1,"title":{"romaji":"File Manga"},"format":"MANGA","genres":["Fantasy"]}]}}}"#.utf8)
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}

private final class LocalIndexingNoNetworkProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        XCTFail("Cached file indexing must not request Kavita or AniList")
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }
    override func stopLoading() { }
}

private final class LocalIndexingLimitedProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil,
                                       headerFields: ["Retry-After": "3600"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}
