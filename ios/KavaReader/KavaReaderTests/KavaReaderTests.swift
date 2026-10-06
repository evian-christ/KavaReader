import Foundation
@testable import KavaReader
import Testing

struct KavitaLibraryServiceTests {
    @MainActor
    @Test func unsupportedSchemeThrowsError() async {
        let service = LibraryServiceFactory(baseURLString: "ftp://example.com", apiKey: nil).makeService()

        do {
            _ = try await service.fetchSections()
            Issue.record("FTP 스킴은 예외를 던져야 합니다.")
        } catch let error as LibraryServiceError {
            switch error {
            case let .unsupportedScheme(scheme):
                #expect(scheme == "ftp")
            default:
                Issue.record("예상과 다른 오류: \(error)")
            }
        } catch {
            Issue.record("예상과 다른 오류: \(error)")
        }
    }

    @MainActor
    @Test func invalidURLFallsBackToErrorService() async {
        let service = LibraryServiceFactory(baseURLString: "http://", apiKey: nil).makeService()

        do {
            _ = try await service.fetchSections()
            Issue.record("잘못된 URL은 예외를 던져야 합니다.")
        } catch let error as LibraryServiceError {
            #expect(error == .invalidBaseURL)
        } catch {
            Issue.record("예상과 다른 오류: \(error)")
        }
    }

    @MainActor
    @Test func kavitaServiceBuildsImageURL() async throws {
        guard let baseURL = URL(string: "https://kavita.example.com") else {
            Issue.record("잘못된 테스트 baseURL")
            return
        }
        let service = KavitaLibraryService(baseURL: baseURL, apiKey: "test-key")
        let dummySeries = LibrarySeries(title: "Dummy", author: "", coverColorHexes: [])
        let dummyChapter = SeriesChapter(id: UUID(), title: "Chapter 1", number: 1, pageCount: 20)

        let url = try service.pageImageURL(seriesID: dummySeries.id, chapterID: dummyChapter.id, pageNumber: 1)

        #expect(url.absoluteString.contains("chapterId"))
        #expect(url.absoluteString.contains(dummyChapter.id.uuidString))
        #expect(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
            .first(where: { $0.name == "page" })?.value == "0")
    }

    @Test func readerImagePagesIncludeCoverAndLastPage() throws {
        let baseURL = try #require(URL(string: "https://kavita.example.com"))
        let service = KavitaLibraryService(baseURL: baseURL, apiKey: "test-key")

        for (readerPage, imageIndex) in [(1, "0"), (2, "1"), (20, "19")] {
            let url = try service.pageImageURL(kavitaChapterId: 42, pageNumber: readerPage)
            let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
            #expect(query.first(where: { $0.name == "page" })?.value == imageIndex)
            #expect(query.first(where: { $0.name == "chapterId" })?.value == "42")
        }
    }

    @Test func readerImageRejectsInvalidPageNumbers() throws {
        let baseURL = try #require(URL(string: "https://kavita.example.com"))
        let service = KavitaLibraryService(baseURL: baseURL, apiKey: "test-key")

        for page in [0, -1] {
            #expect(throws: LibraryServiceError.invalidResponse) {
                _ = try service.pageImageURL(kavitaChapterId: 42, pageNumber: page)
            }
            #expect(throws: LibraryServiceError.invalidResponse) {
                _ = try service.pageImageURL(seriesID: UUID(), chapterID: UUID(), pageNumber: page)
            }
        }
    }
}

struct ContinueReadingServiceTests {
    @Test func failedRequestThrowsInsteadOfReturningAnEmptyList() async {
        do {
            _ = try await service(host: "offline.example.com").fetchContinueReadingItems()
            Issue.record("조회 실패를 빈 목록으로 반환하면 안 됩니다.")
        } catch {
            #expect((error as? URLError)?.code == .notConnectedToInternet)
        }
    }

    @Test func decodesSeriesAndResolvesActualResumeChapter() async throws {
        let items = try await service(host: "resume.example.com").fetchContinueReadingItems()
        let item = try #require(items.first)
        #expect(items.count == 1)
        #expect(item.series.kavitaSeriesId == 42)
        #expect(item.series.title == "Resume series")
        #expect(item.lastReadChapter.kavitaChapterId == 203)
        #expect(item.lastReadChapter.kavitaVolumeId == 10)
        #expect(item.lastReadChapter.number == 2.5)
        #expect(item.lastReadChapter.title == "Chapter 2.5")
        #expect(item.lastReadChapter.pageCount == 40)
        #expect(item.lastReadChapter.lastReadPage == 12)
        #expect(item.progress.pageNum == 12)
        #expect(item.progress.libraryId == 7)
        #expect(item.progressPercentage == 0.3)
    }

    @Test func keepsNextUnreadChapterAfterFinishingPreviousChapter() async throws {
        let items = try await service(host: "next-chapter.example.com").fetchContinueReadingItems()
        let item = try #require(items.first)
        #expect(items.count == 1)
        #expect(item.lastReadChapter.kavitaChapterId == 203)
        #expect(item.lastReadChapter.lastReadPage == 0)
        #expect(item.progress.pageNum == 0)
        #expect(item.lastReadChapter.pageCount == 40)
    }

    private func service(host: String) -> KavitaLibraryService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ContinueReadingFixtureProtocol.self]
        return KavitaLibraryService(baseURL: URL(string: "https://\(host)")!, apiKey: "",
                                    session: URLSession(configuration: configuration))
    }
}

/// Sanitized SeriesDto and ChapterDto responses, with one unavailable resume point.
private final class ContinueReadingFixtureProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        if url.host == "offline.example.com" {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        var status = 200
        let body: String
        switch url.path.lowercased() {
        case "/api/series/on-deck":
            if request.httpMethod != "POST" {
                status = 405
                body = "{}"
            } else if query.first(where: { $0.name == "PageNumber" })?.value == "1" {
                body = #"[{"id":43,"name":"Unavailable series","pages":100,"pagesRead":5},{"id":42,"name":"Resume series","pages":120,"pagesRead":52,"libraryId":7}]"#
            } else {
                body = "[]"
            }
        case "/api/reader/continue-point":
            if query.first(where: { $0.name == "seriesId" })?.value == "43" {
                body = "null"
            } else {
                let page = url.host == "next-chapter.example.com" ? 0 : 12
                body = "{\"id\":203,\"volumeId\":10,\"pagesRead\":\(page),\"title\":null,\"pages\":40}"
            }
        case "/api/series/series-detail":
            body = #"{"volumes":[{"id":10,"chapters":[{"id":201,"number":"1","pages":40,"pagesRead":40,"volumeId":10},{"id":203,"title":"Chapter 2.5","number":"2.5","pages":40,"pagesRead":12,"volumeId":10}]}]}"#
        default:
            status = 404
            body = "{}"
        }
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil,
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}


struct KavitaCredentialScopeTests {
    @Test func normalizesEquivalentServers() throws {
        let expected = try #require(KavitaCredentials.key(server: "https://example.com/books", field: "token"))
        #expect(KavitaCredentials.key(server: " HTTPS://EXAMPLE.COM:443/books/ ", field: "token") == expected)
    }

    @Test func separatesSchemePortPathAndCredentialType() throws {
        let expected = try #require(KavitaCredentials.key(server: "https://example.com/books", field: "token"))
        for server in ["http://example.com/books", "https://other.example.com/books",
                       "https://example.com:8443/books", "https://example.com/other"] {
            #expect(KavitaCredentials.key(server: server, field: "token") != expected)
        }
        #expect(KavitaCredentials.key(server: "https://example.com/books", field: "apiKey") != expected)
    }

    @Test func rejectsURLsContainingCredentialsOrNonServerComponents() {
        for server in ["https://user:password@example.com", "https://example.com?apiKey=secret",
                       "https://example.com#fragment", "ftp://example.com", "https://"] {
            #expect(KavitaCredentials.key(server: server, field: "token") == nil)
        }
    }

    @Test func attachesCredentialsOnlyWithinServerBoundary() throws {
        let server = "https://example.com/books"
        #expect(KavitaCredentials.contains(try #require(URL(string: "https://EXAMPLE.com:443/books/api/image")), server: server))
        for target in ["https://other.example.com/books/api/image", "http://example.com/books/api/image",
                       "https://example.com:8443/books/api/image", "https://example.com/bookstore/api/image",
                       "https://example.com/other/api/image", "https://user@example.com/books/api/image"] {
            #expect(!KavitaCredentials.contains(try #require(URL(string: target)), server: server))
        }
    }
}


struct KavitaServerSessionTests {
    @Test func separatesCookieJarsForProxyPaths() throws {
        let first = KavitaServerSession.session(for: "https://cookie-scope.example.com/first")
        let second = KavitaServerSession.session(for: "https://cookie-scope.example.com/second")
        #expect(first !== second)
        #expect(first === KavitaServerSession.session(for: "https://COOKIE-SCOPE.example.com:443/first/"))
        let cookie = try #require(HTTPCookie(properties: [
            .domain: "cookie-scope.example.com", .path: "/", .name: "test-auth", .value: "dummy"
        ]))
        let firstStorage = try #require(first.configuration.httpCookieStorage)
        let secondStorage = try #require(second.configuration.httpCookieStorage)
        firstStorage.setCookie(cookie)
        defer { firstStorage.deleteCookie(cookie) }
        #expect(firstStorage.cookies?.contains(where: { $0.name == "test-auth" }) == true)
        #expect(secondStorage.cookies?.contains(where: { $0.name == "test-auth" }) != true)
    }
}
