import Foundation
@testable import KavaReader
import UIKit
import XCTest

@MainActor
final class PagePreviewCacheTests: XCTestCase {
    func testReusesSmallPreviewAfterRestartAndSeparatesAccountsAndPages() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try XCTUnwrap(URL(string: "https://example.invalid/image?chapterId=7&page=5&apiKey=account-a"))
        let otherAccount = try XCTUnwrap(URL(string: "https://example.invalid/image?chapterId=7&page=5&apiKey=account-b"))
        let otherPage = try XCTUnwrap(URL(string: "https://example.invalid/image?chapterId=7&page=6&apiKey=account-a"))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let source = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 1600), format: format).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1200, height: 1600))
        }
        let cache = PagePreviewCache(directory: directory)
        let preview = await cache.image(for: url, sourceImage: source)
        XCTAssertEqual(preview?.cgImage?.width, 270)
        XCTAssertEqual(preview?.cgImage?.height, 360)

        let restoredCache = PagePreviewCache(directory: directory)
        let restored = await restoredCache.cachedImage(for: url)
        let differentAccount = await restoredCache.cachedImage(for: otherAccount)
        let differentPage = await restoredCache.cachedImage(for: otherPage)
        XCTAssertEqual(restored?.cgImage?.height, 360)
        XCTAssertNil(differentAccount)
        XCTAssertNil(differentPage)
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        XCTAssertEqual(files.count, 1)
        XCTAssertFalse(try XCTUnwrap(files.first).lastPathComponent.contains("account-a"))
    }

    func testDoesNotCacheErrorResponsesOrInvalidImages() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PagePreviewFailureProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let cache = PagePreviewCache(directory: directory, session: session)
        let errorURL = try XCTUnwrap(URL(string: "https://example.invalid/failure"))
        let invalidURL = try XCTUnwrap(URL(string: "https://example.invalid/invalid"))
        let errorImage = await cache.image(for: errorURL, sourceImage: nil)
        let invalidImage = await cache.image(for: invalidURL, sourceImage: nil)
        XCTAssertNil(errorImage)
        XCTAssertNil(invalidImage)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }
}

private final class PagePreviewFailureProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url,
              let response = HTTPURLResponse(url: url,
                                             statusCode: url.path == "/failure" ? 500 : 200,
                                             httpVersion: nil, headerFields: nil) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("invalid image".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
