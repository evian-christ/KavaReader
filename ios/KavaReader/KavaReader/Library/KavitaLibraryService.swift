import Foundation
import CryptoKit
import OSLog

struct KavitaLibraryService: LibraryServicing {
    // MARK: Lifecycle

    init(baseURL: URL,
         apiKey: String,
         session: URLSession = .shared,
         sectionsPath: String = "/api/Library/libraries",
         seriesDetailPathTemplate: String = "/api/Library/series/%@",
         pagePathTemplate: String = "/api/Library/series/%@/chapter/%@/page/%d")
    {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.session = session
        self.sectionsPath = sectionsPath
        self.seriesDetailPathTemplate = seriesDetailPathTemplate
        self.pagePathTemplate = pagePathTemplate
    }

    // MARK: Internal

    let baseURL: URL
    let apiKey: String
    let session: URLSession
    let sectionsPath: String
    let seriesDetailPathTemplate: String
    let pagePathTemplate: String

    func fetchSections() async throws -> [LibrarySection] {
        // Based on browser network analysis, Kavita uses POST with empty JSON body
        let emptyJsonBody = "{}".data(using: .utf8)!

        // Try multiple series endpoints (from browser analysis)
        let seriesEndpoints = [
            "/api/series/recently-updated-series",
            "/api/series/recently-added",
            "/api/series/newly-added",
            "/api/series/all"
        ]

        var allSeries: [LibrarySeries] = []

        for endpoint in seriesEndpoints {
            do {
                let request = try await makeRequest(path: endpoint, method: "POST", body: emptyJsonBody)
                #if DEBUG
                    Self.logger.debug("POST \(request.url?.absoluteString ?? "<nil>") with empty JSON body")
                #endif

                let (data, response) = try await session.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    continue
                }

                guard 200 ..< 300 ~= httpResponse.statusCode else {
                    #if DEBUG
                        Self.logger.error("\(endpoint) failed with status \(httpResponse.statusCode)")
                    #endif
                    continue
                }

                // Check if we got JSON or HTML
                if let responseString = String(data: data, encoding: .utf8),
                   responseString.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<") {
                    #if DEBUG
                        Self.logger.error("\(endpoint) returned HTML instead of JSON - SPA routing issue")
                    #endif
                    continue
                }

                #if DEBUG
                if let jsonObj = try? JSONSerialization.jsonObject(with: data),
                   let pretty = try? JSONSerialization.data(withJSONObject: jsonObj, options: [.prettyPrinted]),
                   let string = String(data: pretty, encoding: .utf8) {
                    print("[\(endpoint)] JSON (pretty):\n\(string.prefix(500))")
                }
                #endif

                // Try to decode as series array
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase

                // Try different DTO structures based on endpoint
                if endpoint.contains("recently-updated") {
                    // Simple structure: {seriesId, seriesName, ...}
                    if let series = try? decoder.decode([KavitaRecentlyUpdatedSeriesDTO].self, from: data) {
                        let domainSeries = series.map { $0.toDomain() }
                        allSeries.append(contentsOf: domainSeries)
                        #if DEBUG
                            Self.logger.debug("Successfully got \(series.count) series from \(endpoint)")
                        #endif
                    }
                } else {
                    // Full structure: {id, name, primaryColor, ...}
                    if let series = try? decoder.decode([KavitaFullSeriesDTO].self, from: data) {
                        let domainSeries = series.map { $0.toDomain() }
                        allSeries.append(contentsOf: domainSeries)
                        #if DEBUG
                            Self.logger.debug("Successfully got \(series.count) series from \(endpoint)")
                        #endif
                    }
                }
            } catch {
                #if DEBUG
                    Self.logger.error("Failed to fetch \(endpoint): \(error.localizedDescription)")
                #endif
                continue
            }
        }

        // Group series into sections
        var sections: [LibrarySection] = []

        if !allSeries.isEmpty {
            // Remove duplicates while preserving the order from recently-added endpoint
            var uniqueSeries: [LibrarySeries] = []
            var seenTitles: Set<String> = []

            for series in allSeries {
                if !seenTitles.contains(series.title) {
                    seenTitles.insert(series.title)
                    uniqueSeries.append(series)
                }
            }

            // Recently Added section - use first 8 from recently-added endpoint (already sorted by date)
            let recentlyAdded = Array(uniqueSeries.prefix(8))

            if !recentlyAdded.isEmpty {
                let seriesInfo = recentlyAdded.map { series in
                    SeriesInfo(id: series.id, title: series.title, author: series.author,
                              coverColorHexes: series.coverColorHexes, coverURL: series.coverURL)
                }
                sections.append(LibrarySection(id: UUID(), title: "Recently Added", items: seriesInfo))
            }

            // All Series section - sort alphabetically by title
            let allSeriesSorted = uniqueSeries.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            let allSeriesPreview = Array(allSeriesSorted.prefix(8))

            if !allSeriesPreview.isEmpty {
                let seriesInfo = allSeriesPreview.map { series in
                    SeriesInfo(id: series.id, title: series.title, author: series.author,
                              coverColorHexes: series.coverColorHexes, coverURL: series.coverURL)
                }
                sections.append(LibrarySection(id: UUID(), title: "All Series", items: seriesInfo))
            }
        }

        return sections
    }

    func fetchFullSection(sectionTitle: String) async throws -> [LibrarySeries] {
        // Based on browser network analysis, Kavita uses POST with empty JSON body
        let emptyJsonBody = "{}".data(using: .utf8)!

        // Determine endpoint based on section title
        let endpoint: String
        switch sectionTitle {
        case "Recently Added":
            endpoint = "/api/series/recently-added"
        case "All Series":
            endpoint = "/api/series/all"
        default:
            endpoint = "/api/series/all"
        }

        do {
            let request = try await makeRequest(path: endpoint, method: "POST", body: emptyJsonBody)
            #if DEBUG
                Self.logger.debug("Fetching full section for: \(sectionTitle) from \(endpoint)")
            #endif

            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw LibraryServiceError.invalidResponse
            }

            guard 200 ..< 300 ~= httpResponse.statusCode else {
                #if DEBUG
                    Self.logger.error("\(endpoint) failed with status \(httpResponse.statusCode)")
                #endif
                throw LibraryServiceError.requestFailed(statusCode: httpResponse.statusCode)
            }

            // Check if we got JSON or HTML
            if let responseString = String(data: data, encoding: .utf8),
               responseString.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<") {
                #if DEBUG
                    Self.logger.error("\(endpoint) returned HTML instead of JSON - SPA routing issue")
                #endif
                throw LibraryServiceError.decodingFailed
            }

            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase

            if endpoint.contains("recently-updated") {
                if let series = try? decoder.decode([KavitaRecentlyUpdatedSeriesDTO].self, from: data) {
                    return series.map { $0.toDomain() }
                }
            } else {
                if let series = try? decoder.decode([KavitaFullSeriesDTO].self, from: data) {
                    let domainSeries = series.map { $0.toDomain() }

                    // Apply correct sorting based on section
                    switch sectionTitle {
                    case "Recently Added":
                        // Keep original order (already sorted by date from API)
                        return domainSeries
                    case "All Series":
                        // Sort alphabetically by title
                        return domainSeries.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
                    default:
                        return domainSeries
                    }
                }
            }

            throw LibraryServiceError.decodingFailed
        } catch {
            #if DEBUG
                Self.logger.error("Failed to fetch full section \(sectionTitle): \(error.localizedDescription)")
            #endif
            throw error
        }
    }

    func fetchSeriesDetail(seriesID: UUID) async throws -> SeriesDetail {
        let path = String(format: seriesDetailPathTemplate, seriesID.uuidString.lowercased())
        let request = try await makeRequest(path: path)
        #if DEBUG
            Self.logger.debug("Requesting series detail: \(request.url?.absoluteString ?? "<nil>")")
        #endif

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch {
            #if DEBUG
                Self.logger.error("Network error: \(error.localizedDescription)")
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
            // 로그: 응답 본문 확인
            #if DEBUG
            if let body = String(data: data, encoding: .utf8) {
                Self.logger.debug("Raw response body (series detail): \(body)")
                print("=== Raw Response (fetchSeriesDetail) ===")
                print(body)
                print("========================================")
            }
            #endif

            let payload = try decoder.decode(SeriesDetailResponse.self, from: data)
            return payload.series.toDomain()
        } catch {
            #if DEBUG
                Self.logger.error("Decoding failed: \(error.localizedDescription)")
            #endif
            throw LibraryServiceError.decodingFailed
        }
    }

    func pageImageURL(seriesID: UUID, chapterID: UUID, pageNumber: Int) throws -> URL {
        guard pageNumber > 0 else {
            throw LibraryServiceError.invalidResponse
        }

        let path = String(format: pagePathTemplate,
                          seriesID.uuidString.lowercased(),
                          chapterID.uuidString.lowercased(),
                          pageNumber)

        guard let url = buildURL(path: path, queryItems: nil) else {
            throw LibraryServiceError.invalidBaseURL
        }
        return url
    }

    func fetchPageImage(seriesID: UUID, chapterID: UUID, pageNumber: Int) async throws -> Data {
        guard pageNumber > 0 else {
            throw LibraryServiceError.invalidResponse
        }

        let path = String(format: pagePathTemplate,
                          seriesID.uuidString.lowercased(),
                          chapterID.uuidString.lowercased(),
                          pageNumber)
        var request = try await makeRequest(path: path, queryItems: nil, accept: "image/*")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch {
            #if DEBUG
                Self.logger.error("Image load failed: \(error.localizedDescription)")
            #endif
            throw error
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LibraryServiceError.invalidResponse
        }

        guard 200 ..< 300 ~= httpResponse.statusCode else {
            #if DEBUG
                Self.logger.error("Image request failed with status \(httpResponse.statusCode)")
            #endif
            throw LibraryServiceError.requestFailed(statusCode: httpResponse.statusCode)
        }

        return data
    }

    // MARK: Private

    private func makeRequest(path: String,
                             queryItems: [URLQueryItem]? = nil,
                             accept: String = "application/json",
                             method: String = "GET",
                             body: Data? = nil) async throws -> URLRequest
    {
        guard let url = buildURL(path: path, queryItems: queryItems) else {
            throw LibraryServiceError.invalidBaseURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 15

        // Authentication handling - use Kavya's approach (query parameter)
        #if DEBUG
        print("[KavitaLibraryService] apiKey.isEmpty: \(apiKey.isEmpty), apiKey length: \(apiKey.count)")
        #endif

        if !apiKey.isEmpty {
            #if DEBUG
            print("[KavitaLibraryService] Using API Key to get Bearer token (Kavya approach)")
            #endif
            // Get Bearer token using API Key like Kavya does
            if let bearerToken = await authenticateWithAPIKey() {
                request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
                #if DEBUG
                print("[KavitaLibraryService] Set Authorization header with Bearer token from API Key")
                #endif
            } else {
                #if DEBUG
                print("[KavitaLibraryService] Failed to get Bearer token from API Key")
                #endif
                throw LibraryServiceError.requestFailed(statusCode: 401)
            }
        } else {
            #if DEBUG
            print("[KavitaLibraryService] No API key, trying JWT from keychain")
            #endif
            // Fallback to Bearer JWT token from login
            if let data = KeychainHelper.shared.read(key: "kavita_api_token"),
               let token = String(data: data, encoding: .utf8),
               !token.isEmpty {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                #if DEBUG
                print("[KavitaLibraryService] Setting Authorization header with login JWT")
                #endif
            }
        }

        // Set request body for POST requests (Kavita requires empty JSON object)
        if let body = body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        // Use minimal headers like Paperback/Kavya to avoid SPA detection
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue("Paperback", forHTTPHeaderField: "User-Agent")

        // Remove headers that might trigger SPA routing
        // request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        // request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")

        // Minimal headers - sometimes too many headers trigger SPA routing
        // Remove Referer/Origin which might trigger SPA behavior

        #if DEBUG
        // Minimal request log (URL + auth headers only)
        if let headers = request.allHTTPHeaderFields {
            var authHeaders: [String: String] = [:]
            for k in ["Authorization", "ApiKey", "X-Api-Key"] {
                if let v = headers[k] { authHeaders[k] = v }
            }
            print("[request] \(url.absoluteString) headers=\(authHeaders)")
        }
        #endif
        return request
    }

    // Diagnostic probe: try a set of header permutations and record responses so we can see which
    // request shape the reverse proxy accepts as an API call (returns JSON) instead of the SPA HTML.
    // Returns an array of ProbeResult (one per permutation) with status code and a short body preview.
    #if DEBUG
    func probeSectionsVariants() async -> [ProbeResult] {
        // Simple probe - only test Bearer JWT since we know that's what works
        let request = try? await makeRequest(path: sectionsPath)

        guard let request = request else {
            return [ProbeResult(headers: "invalid URL", statusCode: nil, bodyPreview: "Could not create request")]
        }

        do {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode
            let preview = Self.previewBody(data: data, maxLength: 200)
            let authHeader = request.allHTTPHeaderFields?["Authorization"] ?? "none"

            let summary = "Probe result: [status: \(status?.description ?? "nil")] headers=Authorization: \(authHeader) body=\(preview)"
            Self.logger.debug("\(summary)")
            print(summary)

            return [ProbeResult(headers: "Authorization: \(authHeader)", statusCode: status, bodyPreview: preview)]
        } catch {
            return [ProbeResult(headers: "Bearer JWT", statusCode: nil, bodyPreview: "error: \(error.localizedDescription)")]
        }
    }
    #endif

    #if DEBUG
    struct ProbeResult {
        let headers: String
        let statusCode: Int?
        let bodyPreview: String
    }

    static func previewBody(data: Data, maxLength: Int = 512) -> String {
        if data.isEmpty { return "<empty>" }
        if let s = String(data: data, encoding: .utf8) {
            // detect if it's HTML (starts with <!doctype or <html)
            let lowered = s.lowercased()
            if lowered.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<!doctype") || lowered.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<html") {
                return String(s.prefix(maxLength)).replacingOccurrences(of: "\n", with: " ")
            }
            // not HTML, return JSON-ish preview
            return String(s.prefix(maxLength)).replacingOccurrences(of: "\n", with: " ")
        }
        return "<non-utf8, \(data.count) bytes>"
    }

    #endif

    private func buildURL(path: String, queryItems: [URLQueryItem]? = nil) -> URL? {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return nil
        }

        let normalizedBasePath = normalize(basePath: components.path)
        let normalizedPath = normalize(endpointPath: path)
        components.path = normalizedBasePath + normalizedPath
        components.queryItems = queryItems

        #if DEBUG
        if let queryItems = queryItems, !queryItems.isEmpty {
            print("[buildURL] path='\(path)', queryItems=\(queryItems.map { "\($0.name)=\($0.value ?? "")" }), final URL='\(components.url?.absoluteString ?? "nil")'")
        }
        #endif

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

extension KavitaLibraryService {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "KavaReader",
                                       category: "KavitaLibraryService")
}

// MARK: - Kavita API DTOs

// Simple structure for recently-updated-series endpoint
private struct KavitaRecentlyUpdatedSeriesDTO: Decodable {
    let seriesId: Int
    let seriesName: String
    let created: String?
}

extension KavitaRecentlyUpdatedSeriesDTO {
    func toDomain() -> LibrarySeries {
        LibrarySeries(
            id: UUID(), // Generate a UUID since Kavita uses Int
            title: seriesName,
            author: "", // Not available in this endpoint
            coverColorHexes: ["#6B73FF", "#9B59B6"], // Default colors
            coverURL: nil // Not available in this endpoint
        )
    }
}

// Full structure for recently-added and all series endpoints
private struct KavitaFullSeriesDTO: Decodable {
    let id: Int
    let name: String
    let primaryColor: String?
    let secondaryColor: String?
    let pages: Int?
    let originalName: String?
}

extension KavitaFullSeriesDTO {
    func toDomain() -> LibrarySeries {
        // Extract colors from primaryColor and secondaryColor
        var colors = ["#6B73FF", "#9B59B6"] // Default colors
        if let primary = primaryColor, !primary.isEmpty {
            colors[0] = primary
        }
        if let secondary = secondaryColor, !secondary.isEmpty {
            colors.append(secondary)
        }

        return LibrarySeries(
            id: UUID(), // Generate a UUID since Kavita uses Int
            title: name,
            author: "", // Not available in this endpoint
            coverColorHexes: colors,
            coverURL: nil // Not available in this endpoint
        )
    }
}

// MARK: - Fallback DTOs and helpers

private struct KavitaLibraryDTO: Decodable {
    let id: Int
    let name: String
}

// MARK: - Series fetching (fallback when hitting Kavita directly)

private extension KavitaLibraryService {
    func fetchSeriesItems(libraryId: Int) async throws -> [SeriesInfo] {
        // Try the specific sections from Kavita's home page
        let path = "/api/Series/on-deck"
        let query = [URLQueryItem(name: "pageSize", value: "20")]

        do {
            var request = try await makeRequest(path: path, queryItems: query)
            request.timeoutInterval = 20

            // Additional headers to ensure we get API response, not SPA
            request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
            request.setValue("1", forHTTPHeaderField: "X-API-Request")
            request.setValue("same-origin", forHTTPHeaderField: "Sec-Fetch-Site")
            request.setValue("cors", forHTTPHeaderField: "Sec-Fetch-Mode")

            let (data, response) = try await session.data(for: request)

            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                #if DEBUG
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                let preview = KavitaLibraryService.previewBody(data: data)
                Self.logger.debug("Series list request failed for path=\(path) status=\(status) preview=\(preview)")
                #endif
                throw LibraryServiceError.requestFailed(statusCode: (response as? HTTPURLResponse)?.statusCode ?? -1)
            }

            // Check if we got HTML instead of JSON (SPA routing issue)
            if isHTMLResponse(data) {
                #if DEBUG
                let responsePreview = KavitaLibraryService.previewBody(data: data)
                print("[series list] Got HTML instead of JSON for primary endpoint. Response preview: \(responsePreview)")
                print("[series list] Trying alternative approaches...")
                #endif

                // Try the exact 3 sections from Kavita's home page
                let alternatives: [(path: String, queryItems: [URLQueryItem]?)] = [
                    ("/api/Series/recently-updated", [URLQueryItem(name: "pageSize", value: "20")]),
                    ("/api/Series/newly-added", [URLQueryItem(name: "pageSize", value: "20")]),
                    ("/api/Series/recently-added", [URLQueryItem(name: "pageSize", value: "20")]),
                    ("/api/account/dashboard", nil)
                ]

                for (altPath, altQuery) in alternatives {
                    do {
                        #if DEBUG
                        let displayPath = altQuery != nil ? "\(altPath)?\(altQuery!.map { "\($0.name)=\($0.value ?? "")" }.joined(separator: "&"))" : altPath
                        print("[series list] Trying alternative path: \(displayPath)")
                        #endif

                        let altRequest = try await makeRequest(path: altPath, queryItems: altQuery)
                        #if DEBUG
                        print("[series list] Actual URL being requested: \(altRequest.url?.absoluteString ?? "nil")")
                        #endif
                        let (altData, altResponse) = try await session.data(for: altRequest)

                        if let http = altResponse as? HTTPURLResponse,
                           (200..<300).contains(http.statusCode),
                           !isHTMLResponse(altData) {
                            #if DEBUG
                            print("[series list] Success with alternative path: \(altPath)")
                            #endif
                            return parseSeriesArray(from: altData) ?? []
                        } else {
                            #if DEBUG
                            let responsePreview = KavitaLibraryService.previewBody(data: altData)
                            let statusCode = (altResponse as? HTTPURLResponse)?.statusCode ?? -1
                            print("[series list] Alternative path \(altPath) failed (status: \(statusCode)) or returned HTML. Preview: \(responsePreview)")
                            #endif
                        }
                    } catch {
                        #if DEBUG
                        print("[series list] Alternative path \(altPath) error: \(error)")
                        #endif
                        continue
                    }
                }

                // As final fallback, try minimal headers on original path
                do {
                    #if DEBUG
                    print("[series list] Trying minimal headers on original path...")
                    #endif

                    var retryRequest = URLRequest(url: request.url!)
                    retryRequest.httpMethod = "GET"
                    retryRequest.setValue("application/json", forHTTPHeaderField: "Accept")
                    // Only include auth header
                    if let auth = request.allHTTPHeaderFields?["Authorization"] {
                        retryRequest.setValue(auth, forHTTPHeaderField: "Authorization")
                    }

                    let (retryData, retryResponse) = try await session.data(for: retryRequest)

                    if let http = retryResponse as? HTTPURLResponse,
                       (200..<300).contains(http.statusCode),
                       !isHTMLResponse(retryData) {
                        #if DEBUG
                        print("[series list] Minimal headers retry succeeded")
                        #endif
                        return parseSeriesArray(from: retryData) ?? []
                    } else {
                        #if DEBUG
                        print("[series list] Minimal headers retry failed or returned HTML")
                        #endif
                    }
                } catch {
                    #if DEBUG
                    print("[series list] Minimal headers retry error: \(error)")
                    #endif
                }

                // All alternatives failed
                #if DEBUG
                print("[series list] All alternatives failed, returning empty array")
                #endif
                return []
            }

            // Print series JSON for debugging
            #if DEBUG
            if let jsonObj = try? JSONSerialization.jsonObject(with: data),
               let pretty = try? JSONSerialization.data(withJSONObject: jsonObj, options: [.prettyPrinted]),
               let string = String(data: pretty, encoding: .utf8) {
                print("[series list] \(path) JSON (pretty):\n\(string)")
            } else if let s = String(data: data, encoding: .utf8) {
                print("[series list] \(path) non-JSON (first 512):\n\(s.prefix(512))")
            }
            #endif

            if let items = parseSeriesArray(from: data) {
                #if DEBUG
                Self.logger.debug("Series list parsed for path=\(path) count=\(items.count)")
                #endif
                return items
            } else {
                #if DEBUG
                let preview = KavitaLibraryService.previewBody(data: data)
                Self.logger.debug("Series list unrecognized JSON for path=\(path) preview=\(preview)")
                #endif
                throw LibraryServiceError.decodingFailed
            }
        } catch {
            #if DEBUG
            Self.logger.debug("Series list request error for path=\(path) error=\(error.localizedDescription)")
            #endif
            throw error
        }
    }

    func parseSeriesArray(from data: Data) -> [SeriesInfo]? {
        // Try flexible parsing via JSONSerialization to handle varying shapes
        // 1) Top-level array
        if let arr = try? JSONSerialization.jsonObject(with: data, options: []) as? [[String: Any]] {
            return mapSeriesArray(arr)
        }
        // 2) Object with data: [] or series: []
        if let obj = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
            if let arr = obj["data"] as? [[String: Any]] { return mapSeriesArray(arr) }
            if let arr = obj["series"] as? [[String: Any]] { return mapSeriesArray(arr) }
            // 3) Paged payload with items/results
            if let arr = obj["items"] as? [[String: Any]] { return mapSeriesArray(arr) }
            if let arr = obj["results"] as? [[String: Any]] { return mapSeriesArray(arr) }
        }
        let result: [SeriesInfo] = []
        return result.isEmpty ? nil : result
    }

    func mapSeriesArray(_ arr: [[String: Any]]) -> [SeriesInfo] {
        var result: [SeriesInfo] = []
        for obj in arr {
            // id may be Int or String(UUID)
            let idValue: UUID = {
                if let i = obj["id"] as? Int { return deterministicUUID(from: "kavita-series-\(i)") }
                if let s = obj["id"] as? String { return UUID(uuidString: s) ?? deterministicUUID(from: "kavita-series-\(s)") }
                return UUID()
            }()
            let title: String = (obj["name"] as? String) ?? (obj["title"] as? String) ?? "Untitled"
            let author: String = {
                if let a = obj["author"] as? String { return a }
                if let arr = obj["authors"] as? [String], !arr.isEmpty { return arr.joined(separator: ", ") }
                return "Unknown"
            }()
            // Try to find a cover URL field commonly used by servers
            var coverURL: URL? = nil
            let coverKeys = ["coverImageUrl", "cover_url", "coverUrl", "thumbnail", "image", "cover"]
            for key in coverKeys {
                if let s = obj[key] as? String, let url = URL(string: s) {
                    coverURL = attachApiKeyIfNeeded(absolutizeIfNeeded(url))
                    break
                }
            }
            let colors = deriveColors(from: title)
            result.append(SeriesInfo(id: idValue, title: title, author: author, coverColorHexes: colors, coverURL: coverURL))
        }
        return result
    }
}

private extension KavitaLibraryService {
    func fetchRecentSeries() async throws -> [SeriesInfo] {
        let path = "/api/series/recent"

        do {
            let request = try await makeRequest(path: path, queryItems: nil)
            let (data, response) = try await session.data(for: request)

            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw LibraryServiceError.requestFailed(statusCode: (response as? HTTPURLResponse)?.statusCode ?? -1)
            }

            #if DEBUG
            if let jsonObj = try? JSONSerialization.jsonObject(with: data),
               let pretty = try? JSONSerialization.data(withJSONObject: jsonObj, options: [.prettyPrinted]),
               let string = String(data: pretty, encoding: .utf8) {
                print("[recent series] \(path) JSON (pretty):\n\(string)")
            } else if let s = String(data: data, encoding: .utf8) {
                print("[recent series] \(path) non-JSON (first 512):\n\(s.prefix(512))")
            }
            #endif

            return parseSeriesArray(from: data) ?? []
        } catch {
            throw error
        }
    }
}

// MARK: - Utility functions

private func deterministicUUID(from string: String) -> UUID {
    let digest = SHA256.hash(data: Data(string.utf8))
    // Take first 16 bytes for UUID
    let bytes = Array(digest.prefix(16))
    let uuid = uuid_t(bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7], bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15])
    return UUID(uuid: uuid)
}

private func deriveColors(from seed: String) -> [String] {
    let h = SHA256.hash(data: Data(seed.utf8))
    let bytes = Array(h)
    func clamp(_ b: UInt8) -> UInt8 { max(48, b) } // avoid too dark
    func toHex(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> String { String(format: "#%02X%02X%02X", r, g, b) }
    let c1 = toHex(clamp(bytes[0]), clamp(bytes[1]), clamp(bytes[2]))
    let c2 = toHex(clamp(bytes[16 % bytes.count]), clamp(bytes[17 % bytes.count]), clamp(bytes[18 % bytes.count]))
    return [c1, c2]
}

private extension KavitaLibraryService {
    // Ensure any URL is absolute against the service baseURL
    func absolutizeIfNeeded(_ url: URL) -> URL {
        if url.scheme != nil { return url }
        var comps = URLComponents()
        comps.scheme = baseURL.scheme
        comps.host = baseURL.host
        comps.port = baseURL.port
        comps.path = url.absoluteString.hasPrefix("/") ? url.absoluteString : "/" + url.absoluteString
        return comps.url ?? url
    }

    // If using apiKey mode, attach it as query for image URLs (many backends expect api_key on images)
    func attachApiKeyIfNeeded(_ url: URL) -> URL {
        var url = url
        if !apiKey.isEmpty {
            if var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                var items = comps.queryItems ?? []
                if !(items.contains { $0.name == "api_key" }) {
                    items.append(URLQueryItem(name: "api_key", value: apiKey))
                }
                comps.queryItems = items
                url = comps.url ?? url
            }
        }
        return url
    }

    // Detect if response body is HTML (SPA) instead of JSON
    func isHTMLResponse(_ data: Data) -> Bool {
        guard let s = String(data: data, encoding: .utf8) else { return false }
        let lowered = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return lowered.hasPrefix("<!doctype") || lowered.hasPrefix("<html")
    }

    // Get JWT token using API Key through /api/Plugin/authenticate
    func authenticateWithAPIKey() async -> String? {
        guard !apiKey.isEmpty else { return nil }

        let cacheKey = "kavita_jwt_\(apiKey.prefix(8))"

        // Check cache first
        if let data = KeychainHelper.shared.read(key: cacheKey),
           let cachedJWT = String(data: data, encoding: .utf8),
           !cachedJWT.isEmpty {
            return cachedJWT
        }

        // Authenticate with API key using correct endpoint
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else { return nil }
        components.path = (components.path == "/" ? "" : components.path) + "/api/Plugin/authenticate"
        components.queryItems = [
            URLQueryItem(name: "apiKey", value: apiKey),
            URLQueryItem(name: "pluginName", value: "KavaReader")
        ]

        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        #if DEBUG
        print("[KavitaLibraryService] Trying to authenticate at: \(url.absoluteString)")
        #endif

        do {
            let (data, response) = try await session.data(for: request)

            #if DEBUG
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            print("[KavitaLibraryService] Authentication response status: \(statusCode)")
            if let responseString = String(data: data, encoding: .utf8) {
                print("[KavitaLibraryService] Authentication response: \(responseString.prefix(500))")
            }
            #endif

            if let http = response as? HTTPURLResponse,
               (200..<300).contains(http.statusCode),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let token = json["token"] as? String {

                #if DEBUG
                print("[KavitaLibraryService] Successfully got Bearer token")
                #endif

                // Cache the JWT
                if let tokenData = token.data(using: .utf8) {
                    _ = KeychainHelper.shared.save(key: cacheKey, data: tokenData)
                }

                return token
            } else {
                #if DEBUG
                print("[KavitaLibraryService] Token extraction failed or bad status code")
                #endif
            }
        } catch {
            #if DEBUG
            print("[KavitaLibraryService] API Key authentication failed: \(error)")
            #endif
        }

        return nil
    }
}
