import Foundation

protocol LibraryServicing {
    func fetchSections() async throws -> [LibrarySection]
    func fetchFullSection(sectionTitle: String) async throws -> [LibrarySeries]
    func fetchSeriesDetail(kavitaSeriesId: Int) async throws -> SeriesDetail
    func pageImageURL(seriesID: UUID, chapterID: UUID, pageNumber: Int) throws -> URL
    func fetchPageImage(seriesID: UUID, chapterID: UUID, pageNumber: Int) async throws -> Data
    func fetchContinueReadingItems() async -> [ContinueReadingItem]
}

enum LibraryServiceError: Error, LocalizedError, Equatable {
    case decodingFailed
    case invalidBaseURL
    case unsupportedScheme(String)
    case invalidResponse
    case requestFailed(statusCode: Int)
    case noData
    case networkFailure(underlying: Error)
    case authenticationFailed
    case serverUnavailable
    case imageLoadFailed(url: URL)
    case timeout

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .decodingFailed:
            return "라이브러리 데이터를 읽는 중 문제가 발생했습니다."
        case .invalidBaseURL:
            return "서버 주소가 올바르지 않습니다."
        case let .unsupportedScheme(scheme):
            return "지원하지 않는 URL 스킴입니다. (입력 값: \(scheme), http 또는 https 사용)"
        case .invalidResponse:
            return "서버 응답 형식이 올바르지 않습니다."
        case let .requestFailed(statusCode):
            return statusCodeMessage(for: statusCode)
        case .noData:
            return "서버에서 데이터를 받지 못했습니다."
        case .networkFailure:
            return "네트워크 연결에 문제가 있습니다. 인터넷 연결을 확인해주세요."
        case .authenticationFailed:
            return "인증에 실패했습니다. API 키를 확인해주세요."
        case .serverUnavailable:
            return "서버에 연결할 수 없습니다. 서버 상태를 확인해주세요."
        case let .imageLoadFailed(url):
            return "이미지를 불러올 수 없습니다: \(url.lastPathComponent)"
        case .timeout:
            return "요청 시간이 초과되었습니다. 다시 시도해주세요."
        }
    }

    // MARK: Private

    private func statusCodeMessage(for statusCode: Int) -> String {
        switch statusCode {
        case 401:
            return "인증에 실패했습니다. API 키를 확인해주세요."
        case 403:
            return "접근 권한이 없습니다."
        case 404:
            return "요청한 리소스를 찾을 수 없습니다."
        case 500 ... 599:
            return "서버에 문제가 발생했습니다. 잠시 후 다시 시도해주세요."
        default:
            return "서버 요청이 실패했습니다. (코드: \(statusCode))"
        }
    }
}

extension LibraryServiceError {
    static func == (lhs: LibraryServiceError, rhs: LibraryServiceError) -> Bool {
        switch (lhs, rhs) {
        case (.decodingFailed, .decodingFailed),
             (.invalidBaseURL, .invalidBaseURL),
             (.invalidResponse, .invalidResponse),
             (.noData, .noData),
             (.authenticationFailed, .authenticationFailed),
             (.serverUnavailable, .serverUnavailable),
             (.timeout, .timeout):
            return true
        case let (.unsupportedScheme(lScheme), .unsupportedScheme(rScheme)):
            return lScheme == rScheme
        case let (.requestFailed(lCode), .requestFailed(rCode)):
            return lCode == rCode
        case let (.imageLoadFailed(lUrl), .imageLoadFailed(rUrl)):
            return lUrl == rUrl
        case (.networkFailure, .networkFailure):
            return true // 내부 Error는 비교하지 않음
        default:
            return false
        }
    }

    var isRetryable: Bool {
        switch self {
        case .networkFailure, .timeout, .serverUnavailable:
            return true
        case let .requestFailed(code):
            return code >= 500 || code == 408 || code == 429
        case .imageLoadFailed:
            return true
        default:
            return false
        }
    }
}
