import Foundation
@testable import KavaReader
import XCTest

@MainActor
final class AlternateTitleSearchTests: XCTestCase {
    // MARK: Internal

    func testWikipediaUsesUniqueEnglishLinkAndRejectsAmbiguity() throws {
        let linked = Data(#"{"query":{"pages":[{"pageprops":{"disambiguation":""},"langlinks":[{"lang":"en","title":"Wrong"}]},{"missing":true},{"langlinks":[{"lang":"en","title":"Magic School (manga)"}]}]}}"#
            .utf8)
        XCTAssertNil(try WikipediaTitleService.englishTitle(data: linked))
        let unique = Data(#"{"query":{"pages":[{"missing":true},{"langlinks":[{"lang":"en","title":"Magic School (manga)"}]}]}}"#
            .utf8)
        XCTAssertEqual(try WikipediaTitleService.englishTitle(data: unique), "Magic School")
        let sameEnglishName = Data(#"{"query":{"pages":[{"langlinks":[{"lang":"en","title":"Same (manga)"}]},{"langlinks":[{"lang":"en","title":"Same (novel)"}]}]}}"#
            .utf8)
        XCTAssertNil(try WikipediaTitleService.englishTitle(data: sameEnglishName))
        let ambiguous = Data(#"{"query":{"pages":[{"langlinks":[{"lang":"en","title":"One"}]},{"langlinks":[{"lang":"en","title":"Two"}]}]}}"#
            .utf8)
        XCTAssertNil(try WikipediaTitleService.englishTitle(data: ambiguous))
        XCTAssertNil(try WikipediaTitleService
            .englishTitle(data: Data(#"{"query":{"pages":[{"missing":true}]}}"#.utf8)))
        XCTAssertThrowsError(try WikipediaTitleService.englishTitle(data: Data(#"{"error":{"code":"maxlag"}}"#.utf8)))
    }

    func testAmbiguousKoreanTitleDoesNotFallBackToEnglish() async throws {
        let session = session(DirectLookupOnlyProtocol.self)
        defer { session.invalidateAndCancel() }
        let match = try await AniListMetadataService(session: session)
            .lookup(title: "동명 작품", retryWithEnglishTitle: true)
        XCTAssertNil(match)
    }

    func testAmbiguousEnglishTitleIsNotAutomaticallyLinked() async throws {
        let session = session(AmbiguousEnglishFixtureProtocol.self)
        defer { session.invalidateAndCancel() }
        let match = try await AniListMetadataService(session: session)
            .lookup(title: "마법 학교", retryWithEnglishTitle: true)
        XCTAssertNil(match)
    }

    func testIncompleteSearchPageCannotProveUniqueMatch() throws {
        let data = Data(#"{"data":{"Page":{"pageInfo":{"hasNextPage":true},"media":[{"id":1,"title":{"english":"Same"},"genres":["Fantasy"]}]}}}"#
            .utf8)
        XCTAssertNil(try AniListMetadataService.match(data: data, title: "Same"))
        let editions = Data(#"{"data":{"Page":{"media":[{"id":1,"format":"MANGA","title":{"english":"Same"},"genres":["Fantasy"]},{"id":2,"format":"NOVEL","title":{"english":"Same"},"genres":[]}]}}}"#
            .utf8)
        XCTAssertNil(try AniListMetadataService.match(data: editions, title: "Same"))
    }

    func testDisabledSearchNeverContactsWikipedia() async throws {
        let session = session(DirectLookupOnlyProtocol.self)
        defer { session.invalidateAndCancel() }
        let service = AniListMetadataService(session: session)
        // Default parameter must never make a Wikipedia request, even for a Korean title.
        let match = try await service.lookup(title: "마법 학교")
        XCTAssertNil(match)
    }

    func testEnglishLinkIsUsedToFetchAniListMetadata() async throws {
        let session = session(AlternateTitleFixtureProtocol.self)
        defer { session.invalidateAndCancel() }
        let match = try await AniListMetadataService(session: session)
            .lookup(title: "마법 학교", retryWithEnglishTitle: true)
        XCTAssertEqual(match?.aniListID, 42)
        XCTAssertEqual(match?.genres, ["Fantasy"])
    }

    func testDirectMatchSkipsWikipediaEvenWhenEnabled() async throws {
        let session = session(DirectLookupOnlyProtocol.self)
        defer { session.invalidateAndCancel() }
        let match = try await AniListMetadataService(session: session)
            .lookup(title: "한글 일치", retryWithEnglishTitle: true)
        XCTAssertEqual(match?.aniListID, 7)
    }

    func testEnablingRetriesOldCachedMissAndDisablingKeepsMatches() async throws {
        let defaults = UserDefaults.standard
        let original = defaults.object(forKey: IndexingSettings.alternateTitleSearchKey)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let session = session(AlternateTitleFixtureProtocol.self)
        defer {
            if let original { defaults.set(original, forKey: IndexingSettings.alternateTitleSearchKey) }
            else { defaults.removeObject(forKey: IndexingSettings.alternateTitleSearchKey) }
            session.invalidateAndCancel()
            try? FileManager.default.removeItem(at: directory)
        }
        defaults.removeObject(forKey: IndexingSettings.alternateTitleSearchKey)
        XCTAssertFalse(IndexingSettings.alternateTitleSearchEnabled)
        let id = UUID()
        let store = LocalSeriesMetadataStore(directory: directory, session: session)
        let miss = try await store.lookup(id: id, title: "마법 학교", includeNovels: false)
        XCTAssertNil(miss)
        let offPending = await store.needsLookup(id: id, title: "마법 학교", includeNovels: false)
        XCTAssertFalse(offPending)
        // Simulate the older cache schema without the new optional flag.
        struct OldRecord: Encodable {
            let title = "마법 학교"
            let includeNovels = false
            let checkedAt = Date()
        }
        struct OldSnapshot: Encodable {
            let automatic: [UUID: OldRecord]
            let manual: [UUID: ManualSeriesMetadataRecord] = [:]
        }
        let cacheURL = directory.appendingPathComponent("local-files-metadata.json")
        try JSONEncoder().encode(OldSnapshot(automatic: [id: OldRecord()])).write(to: cacheURL)
        let reopened = LocalSeriesMetadataStore(directory: directory, session: session)
        defaults.set(true, forKey: IndexingSettings.alternateTitleSearchKey)
        let onPending = await reopened.needsLookup(id: id, title: "마법 학교", includeNovels: false)
        XCTAssertTrue(onPending)
        let match = try await reopened.lookup(id: id, title: "마법 학교", includeNovels: false)
        XCTAssertEqual(match?.aniListID, 42)
        defaults.set(false, forKey: IndexingSettings.alternateTitleSearchKey)
        let info = await reopened.information(id: id, title: "마법 학교")
        XCTAssertEqual(info.external?.aniListID, 42)
    }

    // MARK: Private

    private func session(_ type: AnyClass) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [type]
        return URLSession(configuration: configuration)
    }
}

private class DirectLookupOnlyProtocol: URLProtocol {
    override class func canInit(with _: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard request.url?.host == "graphql.anilist.co" else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        let variables = requestVariables()
        let search = variables["search"] as? String
        if search == "동명 작품" {
            complete(#"{"data":{"Page":{"media":[{"id":1,"title":{"native":"동명 작품"},"genres":["Fantasy"]},{"id":2,"title":{"native":"동명 작품"},"genres":[]}]}}}"#)
            return
        }
        let json = search == "한글 일치"
            ? #"{"data":{"Page":{"media":[{"id":7,"title":{"native":"한글 일치"},"genres":["Fantasy"]}]}}}"#
            : #"{"data":{"Page":{"media":[]}}}"#
        complete(json)
    }

    override func stopLoading() {}

    func requestVariables() -> [String: Any] {
        // URLSession may deliver request bodies as streams to URLProtocol.
        var body = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                body.append(contentsOf: buffer.prefix(count))
            }
        }
        let object = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
        return object?["variables"] as? [String: Any] ?? [:]
    }

    func complete(_ json: String) {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(json.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

private class AlternateTitleFixtureProtocol: DirectLookupOnlyProtocol {
    override func startLoading() {
        if request.url?.host == "ko.wikipedia.org" {
            let parameters = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
            guard parameters.contains(where: { $0.name == "titles" && $0.value?.contains("마법 학교") == true }) else {
                client?.urlProtocol(self, didFailWithError: URLError(.badURL))
                return
            }
            complete(#"{"query":{"pages":[{"langlinks":[{"lang":"en","title":"Magic School (manga)"}]}]}}"#)
        } else if requestVariables()["search"] as? String == "Magic School" {
            complete(#"{"data":{"Page":{"media":[{"id":42,"title":{"english":"Magic School"},"genres":["Fantasy"]}]}}}"#)
        } else {
            super.startLoading()
        }
    }
}

private final class AmbiguousEnglishFixtureProtocol: AlternateTitleFixtureProtocol {
    override func startLoading() {
        if request.url?.host == "graphql.anilist.co", requestVariables()["search"] as? String == "Magic School" {
            complete(#"{"data":{"Page":{"media":[{"id":42,"title":{"english":"Magic School"},"genres":["Fantasy"]},{"id":43,"title":{"english":"Magic School"},"genres":[]}]}}}"#)
        } else {
            super.startLoading()
        }
    }
}
