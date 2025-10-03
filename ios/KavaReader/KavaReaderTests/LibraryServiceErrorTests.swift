@testable import KavaReader
import XCTest

final class LibraryServiceErrorTests: XCTestCase {
    func testErrorDescriptions() {
        // Given & When & Then
        XCTAssertEqual(LibraryServiceError.decodingFailed.localizedDescription,
                       "라이브러리 데이터를 읽는 중 문제가 발생했습니다.")

        XCTAssertEqual(LibraryServiceError.invalidBaseURL.localizedDescription,
                       "서버 주소가 올바르지 않습니다.")

        XCTAssertEqual(LibraryServiceError.unsupportedScheme("ftp").localizedDescription,
                       "지원하지 않는 URL 스킴입니다. (입력 값: ftp, http 또는 https 사용)")

        XCTAssertEqual(LibraryServiceError.invalidResponse.localizedDescription,
                       "서버 응답 형식이 올바르지 않습니다.")

        XCTAssertEqual(LibraryServiceError.noData.localizedDescription,
                       "서버에서 데이터를 받지 못했습니다.")

        XCTAssertEqual(LibraryServiceError.networkFailure(underlying: URLError(.notConnectedToInternet))
            .localizedDescription,
            "네트워크 연결에 문제가 있습니다. 인터넷 연결을 확인해주세요.")

        XCTAssertEqual(LibraryServiceError.authenticationFailed.localizedDescription,
                       "인증에 실패했습니다. API 키를 확인해주세요.")

        XCTAssertEqual(LibraryServiceError.serverUnavailable.localizedDescription,
                       "서버에 연결할 수 없습니다. 서버 상태를 확인해주세요.")

        XCTAssertEqual(LibraryServiceError.timeout.localizedDescription,
                       "요청 시간이 초과되었습니다. 다시 시도해주세요.")

        let testURL = URL(string: "https://example.com/image.jpg")!
        XCTAssertEqual(LibraryServiceError.imageLoadFailed(url: testURL).localizedDescription,
                       "이미지를 불러올 수 없습니다: image.jpg")
    }

    func testStatusCodeMessages() {
        // Given & When & Then
        XCTAssertEqual(LibraryServiceError.requestFailed(statusCode: 401).localizedDescription,
                       "인증에 실패했습니다. API 키를 확인해주세요.")

        XCTAssertEqual(LibraryServiceError.requestFailed(statusCode: 403).localizedDescription,
                       "접근 권한이 없습니다.")

        XCTAssertEqual(LibraryServiceError.requestFailed(statusCode: 404).localizedDescription,
                       "요청한 리소스를 찾을 수 없습니다.")

        XCTAssertEqual(LibraryServiceError.requestFailed(statusCode: 500).localizedDescription,
                       "서버에 문제가 발생했습니다. 잠시 후 다시 시도해주세요.")

        XCTAssertEqual(LibraryServiceError.requestFailed(statusCode: 999).localizedDescription,
                       "서버 요청이 실패했습니다. (코드: 999)")
    }

    func testErrorEquality() {
        // Given
        let error1 = LibraryServiceError.decodingFailed
        let error2 = LibraryServiceError.decodingFailed
        let error3 = LibraryServiceError.invalidBaseURL

        let url1 = URL(string: "https://example.com/image1.jpg")!
        let url2 = URL(string: "https://example.com/image2.jpg")!
        let imageError1 = LibraryServiceError.imageLoadFailed(url: url1)
        let imageError2 = LibraryServiceError.imageLoadFailed(url: url1)
        let imageError3 = LibraryServiceError.imageLoadFailed(url: url2)

        // When & Then
        XCTAssertEqual(error1, error2)
        XCTAssertNotEqual(error1, error3)
        XCTAssertEqual(imageError1, imageError2)
        XCTAssertNotEqual(imageError1, imageError3)

        XCTAssertEqual(LibraryServiceError.requestFailed(statusCode: 404),
                       LibraryServiceError.requestFailed(statusCode: 404))

        XCTAssertNotEqual(LibraryServiceError.requestFailed(statusCode: 404),
                          LibraryServiceError.requestFailed(statusCode: 500))
    }

    func testRetryableErrors() {
        // Given & When & Then
        XCTAssertTrue(LibraryServiceError.networkFailure(underlying: URLError(.notConnectedToInternet)).isRetryable)
        XCTAssertTrue(LibraryServiceError.timeout.isRetryable)
        XCTAssertTrue(LibraryServiceError.serverUnavailable.isRetryable)
        XCTAssertTrue(LibraryServiceError.requestFailed(statusCode: 500).isRetryable)
        XCTAssertTrue(LibraryServiceError.requestFailed(statusCode: 502).isRetryable)
        XCTAssertTrue(LibraryServiceError.requestFailed(statusCode: 408).isRetryable) // Request Timeout
        XCTAssertTrue(LibraryServiceError.requestFailed(statusCode: 429).isRetryable) // Too Many Requests

        let testURL = URL(string: "https://example.com/image.jpg")!
        XCTAssertTrue(LibraryServiceError.imageLoadFailed(url: testURL).isRetryable)

        XCTAssertFalse(LibraryServiceError.decodingFailed.isRetryable)
        XCTAssertFalse(LibraryServiceError.invalidBaseURL.isRetryable)
        XCTAssertFalse(LibraryServiceError.authenticationFailed.isRetryable)
        XCTAssertFalse(LibraryServiceError.requestFailed(statusCode: 401).isRetryable)
        XCTAssertFalse(LibraryServiceError.requestFailed(statusCode: 403).isRetryable)
        XCTAssertFalse(LibraryServiceError.requestFailed(statusCode: 404).isRetryable)
    }
}
