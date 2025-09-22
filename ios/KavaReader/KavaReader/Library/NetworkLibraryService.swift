import Foundation
import OSLog

struct NetworkLibraryService: LibraryServicing {
    // MARK: Lifecycle

    init(baseURL: URL,
         apiKey: String,
         session: URLSession = .shared,
         libraryPath: String = "/api/library")
    {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.session = session
        self.libraryPath = libraryPath
    }

    // MARK: Internal

    let baseURL: URL
    let apiKey: String
    let session: URLSession
    let libraryPath: String

    func fetchSections() async throws -> [LibrarySection] {
        let request = try makeRequest(path: libraryPath)
        #if DEBUG
            Self.logger.debug("Requesting library: \(request.url?.absoluteString ?? "<nil>")")
        #endif

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch {
            #if DEBUG
                Self.logger.error("Network error: \(error.localizedDescription, privacy: .public)")
            #endif
            throw error
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LibraryServiceError.invalidResponse
        }

        guard 200 ..< 300 ~= httpResponse.statusCode else {
            #if DEBUG
                Self.logger.error("Request failed with status \(httpResponse.statusCode)")
            #endif
            throw LibraryServiceError.requestFailed(statusCode: httpResponse.statusCode)
        }

        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let payload = try decoder.decode(LibrarySectionsResponse.self, from: data)
            return payload.sections.map { $0.toDomain() }
        } catch {
            #if DEBUG
                Self.logger.error("Decoding failed: \(error.localizedDescription, privacy: .public)")
            #endif
            throw LibraryServiceError.decodingFailed
        }
    }

    // MARK: Private

    private func makeRequest(path: String, queryItems: [URLQueryItem]? = nil) throws -> URLRequest {
        guard let url = buildURL(path: path, queryItems: queryItems) else {
            throw LibraryServiceError.invalidBaseURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func buildURL(path: String, queryItems: [URLQueryItem]? = nil) -> URL? {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return nil
        }

        let normalizedBasePath = normalize(basePath: components.path)
        let normalizedPath = normalize(endpointPath: path)
        components.path = normalizedBasePath + normalizedPath
        components.queryItems = queryItems
        return components.url
    }

    private func normalize(basePath: String) -> String {
        switch basePath {
        case "", "/":
            return ""
        case let path where path.hasSuffix("/"):
            return String(path.dropLast())
        default:
            return basePath
        }
    }

    private func normalize(endpointPath: String) -> String {
        if endpointPath.hasPrefix("/") {
            return endpointPath
        }
        return "/" + endpointPath
    }
}

// MARK: - Logging

extension NetworkLibraryService {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "KavaReader",
                                       category: "NetworkLibraryService")
}
