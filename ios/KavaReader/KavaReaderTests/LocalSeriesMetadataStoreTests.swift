import Foundation
import XCTest
@testable import KavaReader

@MainActor
final class LocalSeriesMetadataStoreTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func session(_ protocolClass: AnyClass) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [protocolClass]
        return URLSession(configuration: configuration)
    }

    func testCachedMatchAndMissSurviveRestartWithoutNetwork() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let network = session(LocalMetadataFixtureProtocol.self)
        defer { network.invalidateAndCancel() }
        let store = LocalSeriesMetadataStore(directory: folder, session: network)
        let matchedID = UUID(), missingID = UUID()
        let matched = try await store.lookup(id: matchedID, title: "File Novel", includeNovels: true)
        let missing = try await store.lookup(id: missingID, title: "Different book", includeNovels: true)
        XCTAssertEqual(matched?.genres, ["Fantasy"])
        XCTAssertNil(missing)
        let offline = session(LocalMetadataNoNetworkProtocol.self)
        defer { offline.invalidateAndCancel() }
        let reopened = LocalSeriesMetadataStore(directory: folder, session: offline)
        let cached = try await reopened.lookup(id: matchedID, title: "File Novel", includeNovels: true)
        let cachedMiss = try await reopened.lookup(id: missingID, title: "Different book", includeNovels: true)
        XCTAssertEqual(cached?.aniListID, 1)
        XCTAssertNil(cachedMiss)
        let renamed = await reopened.information(id: matchedID, title: "Renamed book")
        XCTAssertNil(renamed.external)
    }

    func testManualDisableAndLinkArePerUUIDAndPersisted() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let offline = session(LocalMetadataNoNetworkProtocol.self)
        defer { offline.invalidateAndCancel() }
        let store = LocalSeriesMetadataStore(directory: folder, session: offline)
        let disabledID = UUID(), linkedID = UUID()
        try await store.set(ManualSeriesMetadataRecord(metadata: nil, updatedAt: Date()), id: disabledID)
        let disabled = try await store.lookup(id: disabledID, title: "Same title", includeNovels: true)
        XCTAssertNil(disabled)
        let match = ExternalSeriesMetadata(aniListID: 1, sourceTitle: "Linked",
            sourceURL: URL(string: "https://anilist.co/manga/1")!, genres: ["Fantasy"], tags: [])
        try await store.set(ManualSeriesMetadataRecord(metadata: match, updatedAt: Date()), id: linkedID)
        let reopened = LocalSeriesMetadataStore(directory: folder, session: offline)
        let linked = try await reopened.lookup(id: linkedID, title: "Renamed", includeNovels: true)
        XCTAssertEqual(linked?.aniListID, 1)
        let disabledInfo = await reopened.information(id: disabledID, title: "Same title")
        XCTAssertNotNil(disabledInfo.manual)
        XCTAssertNil(disabledInfo.external)
        try await reopened.set(nil, id: disabledID)
        let restored = await reopened.information(id: disabledID, title: "Same title")
        XCTAssertNil(restored.manual)
    }

    func testRateLimitIsPersistedAndCorruptCacheIsNotOverwritten() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let limited = session(LocalMetadataLimitedProtocol.self)
        defer { limited.invalidateAndCancel() }
        let store = LocalSeriesMetadataStore(directory: folder, session: limited)
        do {
            _ = try await store.lookup(id: UUID(), title: "File Novel", includeNovels: true)
            XCTFail("429 must not be recorded as a title miss")
        } catch ExternalLookupError.rateLimited { }
        let offline = session(LocalMetadataNoNetworkProtocol.self)
        defer { offline.invalidateAndCancel() }
        let reopened = LocalSeriesMetadataStore(directory: folder, session: offline)
        do {
            _ = try await reopened.lookup(id: UUID(), title: "Another title", includeNovels: false)
            XCTFail("Saved rate limit must defer lookup")
        } catch ExternalLookupError.rateLimited { }
        let url = folder.appendingPathComponent("local-files-metadata.json")
        let corrupt = Data("broken cache".utf8)
        try corrupt.write(to: url)
        let broken = LocalSeriesMetadataStore(directory: folder, session: offline)
        do {
            try await broken.set(ManualSeriesMetadataRecord(metadata: nil, updatedAt: Date()), id: UUID())
            XCTFail("Malformed saved connections must not be overwritten")
        } catch { }
        XCTAssertEqual(try Data(contentsOf: url), corrupt)
    }
}

private final class LocalMetadataFixtureProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let data = Data(#"{"data":{"Page":{"media":[{"id":1,"title":{"romaji":"File Novel"},"format":"NOVEL","genres":["Fantasy"]}]}}}"#.utf8)
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}

private final class LocalMetadataNoNetworkProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        XCTFail("Local cached metadata must not query Kavita or AniList")
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }
    override func stopLoading() { }
}

private final class LocalMetadataLimitedProtocol: URLProtocol {
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
