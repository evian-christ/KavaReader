import Foundation

protocol LibraryServicing {
    func fetchSections() async throws -> [LibrarySection]
}

enum LibraryServiceError: Error, LocalizedError {
    case missingResource
    case decodingFailed
    case invalidBaseURL
    case unsupportedScheme(String)
    case invalidResponse
    case requestFailed(statusCode: Int)

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .missingResource:
            return "라이브러리 데이터 리소스를 찾지 못했습니다."
        case .decodingFailed:
            return "라이브러리 데이터를 읽는 중 문제가 발생했습니다."
        case .invalidBaseURL:
            return "서버 주소가 올바르지 않습니다."
        case let .unsupportedScheme(scheme):
            return "지원하지 않는 URL 스킴입니다. (입력 값: \(scheme), http 또는 https 사용)"
        case .invalidResponse:
            return "서버 응답 형식이 올바르지 않습니다."
        case let .requestFailed(statusCode):
            return "서버 요청이 실패했습니다. (코드: \(statusCode))"
        }
    }
}

struct MockLibraryService: LibraryServicing {
    // MARK: Lifecycle

    init(resourceName: String = "LibraryMockData", bundle: Bundle = .main) {
        self.resourceName = resourceName
        self.bundle = bundle
    }

    // MARK: Internal

    let resourceName: String
    let bundle: Bundle

    func fetchSections() async throws -> [LibrarySection] {
        guard let url = bundle.url(forResource: resourceName, withExtension: "json") else {
            throw LibraryServiceError.missingResource
        }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let response = try decoder.decode(LibrarySectionsResponse.self, from: data)
            return response.sections.map { $0.toDomain() }
        } catch is DecodingError {
            throw LibraryServiceError.decodingFailed
        } catch {
            throw error
        }
    }
}
