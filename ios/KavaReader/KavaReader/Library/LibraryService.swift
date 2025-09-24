import Foundation

protocol LibraryServicing {
    func fetchSections() async throws -> [LibrarySection]
    func fetchSeriesDetail(seriesID: UUID) async throws -> SeriesDetail
    func pageImageURL(seriesID: UUID, chapterID: UUID, pageNumber: Int) throws -> URL
    func fetchPageImage(seriesID: UUID, chapterID: UUID, pageNumber: Int) async throws -> Data
}

enum LibraryServiceError: Error, LocalizedError, Equatable {
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

extension LibraryServiceError {
    static func == (lhs: LibraryServiceError, rhs: LibraryServiceError) -> Bool {
        switch (lhs, rhs) {
        case (.missingResource, .missingResource),
             (.decodingFailed, .decodingFailed),
             (.invalidBaseURL, .invalidBaseURL),
             (.invalidResponse, .invalidResponse):
            return true
        case let (.unsupportedScheme(lScheme), .unsupportedScheme(rScheme)):
            return lScheme == rScheme
        case let (.requestFailed(lCode), .requestFailed(rCode)):
            return lCode == rCode
        default:
            return false
        }
    }
}

@MainActor
final class MockLibraryService: LibraryServicing {
    // MARK: Lifecycle

    init(resourceName: String = "LibraryMockData", bundle: Bundle = .main) {
        self.resourceName = resourceName
        self.bundle = bundle
    }

    // MARK: Internal

    let resourceName: String
    let bundle: Bundle

    func fetchSections() async throws -> [LibrarySection] {
        if let cached = cachedSections {
            return cached
        }

        guard let url = bundle.url(forResource: resourceName, withExtension: "json") else {
            throw LibraryServiceError.missingResource
        }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let response = try decoder.decode(LibrarySectionsResponse.self, from: data)
            let sections = response.sections.map { $0.toDomain() }
            cachedSections = sections
            buildDetailStore(from: sections)
            return sections
        } catch is DecodingError {
            throw LibraryServiceError.decodingFailed
        } catch {
            throw error
        }
    }

    func fetchSeriesDetail(seriesID: UUID) async throws -> SeriesDetail {
        if detailStore[seriesID] == nil {
            let sections = try await fetchSections()
            buildDetailStore(from: sections)
        }

        guard let detail = detailStore[seriesID] else {
            throw LibraryServiceError.missingResource
        }

        return detail
    }

    func pageImageURL(seriesID: UUID, chapterID: UUID, pageNumber: Int) throws -> URL {
        guard pageNumber > 0 else {
            throw LibraryServiceError.invalidResponse
        }

        return URL(string: "https://example.com/mock/series/\(seriesID.uuidString)/chapter/\(chapterID.uuidString)/page/\(pageNumber)")!
    }

    func fetchPageImage(seriesID: UUID, chapterID: UUID, pageNumber: Int) async throws -> Data {
        guard pageNumber > 0 else {
            throw LibraryServiceError.invalidResponse
        }

        return Data()
    }

    // MARK: Private

    private var cachedSections: [LibrarySection]?
    private var detailStore: [UUID: SeriesDetail] = [:]

    private func buildDetailStore(from sections: [LibrarySection]) {
        for section in sections {
            for series in section.items {
                guard detailStore[series.id] == nil else { continue }

                let chapters: [SeriesChapter] = (1 ... 5).map { index in
                    let chapterID = UUID()
                    return SeriesChapter(id: chapterID,
                                          title: "챕터 \(index)",
                                          number: Double(index),
                                          pageCount: 18 + index,
                                          lastReadPage: nil)
                }

                let detail = SeriesDetail(id: series.id,
                                           title: series.title,
                                           author: series.author,
                                           summary: "\(series.title)에 대한 요약 텍스트입니다. Kavita 연동 시 실제 메타데이터로 대체됩니다.",
                                           coverImageURL: nil,
                                           chapters: chapters)
                detailStore[series.id] = detail
            }
        }
    }
}
