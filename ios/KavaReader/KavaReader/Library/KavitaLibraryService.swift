import Foundation
import CryptoKit
import OSLog

extension URL {
    func appendingQueryItems(_ queryItems: [URLQueryItem]) -> URL? {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.queryItems = (components.queryItems ?? []) + queryItems
        return components.url
    }
}

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

    private var optionalApiKey: String? {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func fetchSections() async throws -> [LibrarySection] {
        // Performance optimization: Only fetch the essential APIs in parallel
        let emptyJsonBody = "{}".data(using: .utf8)!


        // Fetch only the 2 most important endpoints in parallel
        async let recentlyAddedTask = fetchSeriesFromEndpoint("/api/series/recently-added", body: emptyJsonBody)
        async let allSeriesTask = fetchSeriesFromEndpoint("/api/series/all", body: emptyJsonBody)

        // Wait for both to complete
        let (recentlyAddedSeries, allSeries) = await (recentlyAddedTask, allSeriesTask)

        var sections: [LibrarySection] = []

        // Recently Added section (limit to 8 for performance)
        if !recentlyAddedSeries.isEmpty {
            let recentItems = Array(recentlyAddedSeries.prefix(8)).map { series in
                SeriesInfo(id: series.id, kavitaSeriesId: series.kavitaSeriesId, title: series.title,
                          author: series.author, coverColorHexes: series.coverColorHexes, coverURL: series.coverURL)
            }
            sections.append(LibrarySection(id: UUID(), title: "Recently Added", items: recentItems))
        }

        // All Series section (limit to 12 for performance, sort alphabetically)
        if !allSeries.isEmpty {
            let sortedSeries = allSeries.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            let allItems = Array(sortedSeries.prefix(12)).map { series in
                SeriesInfo(id: series.id, kavitaSeriesId: series.kavitaSeriesId, title: series.title,
                          author: series.author, coverColorHexes: series.coverColorHexes, coverURL: series.coverURL)
            }
            sections.append(LibrarySection(id: UUID(), title: "All Series", items: allItems))
        }


        return sections
    }

    // Helper method for cleaner parallel API calls
    private func fetchSeriesFromEndpoint(_ endpoint: String, body: Data) async -> [LibrarySeries] {
        do {
            let request = try await makeRequest(path: endpoint, method: "POST", body: body)
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  200..<300 ~= httpResponse.statusCode else {
                return []
            }

            // Check for HTML response
            if let responseString = String(data: data, encoding: .utf8),
               responseString.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<") {
                return []
            }

            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase

            if let series = try? decoder.decode([KavitaFullSeriesDTO].self, from: data) {
                return series.map { $0.toDomain(baseURL: baseURL, apiKey: optionalApiKey) }
            }

        } catch {
            // Network error
        }

        return []
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
                    return series.map { $0.toDomain(baseURL: baseURL, apiKey: optionalApiKey) }
                }
            } else {
                if let series = try? decoder.decode([KavitaFullSeriesDTO].self, from: data) {
                    let domainSeries = series.map { $0.toDomain(baseURL: baseURL, apiKey: optionalApiKey) }

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

    func fetchSeriesDetail(kavitaSeriesId: Int) async throws -> SeriesDetail {
        // First, get series metadata
        let seriesPath = "/api/series/\(kavitaSeriesId)"


        let seriesRequest = try await makeRequest(path: seriesPath, method: "GET")
        let (seriesData, seriesResponse) = try await session.data(for: seriesRequest)

        guard let httpResponse = seriesResponse as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            throw LibraryServiceError.requestFailed(statusCode: (seriesResponse as? HTTPURLResponse)?.statusCode ?? -1)
        }

        // Check if we got HTML instead of JSON
        if let responseString = String(data: seriesData, encoding: .utf8),
           responseString.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<") {
            throw LibraryServiceError.decodingFailed
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        guard let seriesDetail = try? decoder.decode(KavitaSeriesDetailDTO.self, from: seriesData) else {
            throw LibraryServiceError.decodingFailed
        }

        // Try to get chapters/volumes for this series
        let chapters = await fetchChaptersForSeries(kavitaSeriesId: kavitaSeriesId)

        // Convert to domain model with chapters
        return SeriesDetail(
            id: UUID(),
            title: seriesDetail.name,
            author: seriesDetail.libraryName ?? "",
            summary: "총 \(seriesDetail.pages ?? 0)페이지",
            coverImageURL: generateCoverURL(for: kavitaSeriesId),
            chapters: chapters
        )
    }

    private func generateCoverURL(for seriesId: Int) -> URL? {
        var items = [URLQueryItem(name: "seriesId", value: String(seriesId))]
        if let key = optionalApiKey {
            items.append(URLQueryItem(name: "apiKey", value: key))
        }
        return baseURL
            .appendingPathComponent("api/image/series-cover")
            .appendingQueryItems(items)
    }

    private func fetchChaptersForSeries(kavitaSeriesId: Int) async -> [SeriesChapter] {
        // Use the discovered working endpoint
        let endpoint = "/api/series/series-detail"
        let queryItems = [URLQueryItem(name: "seriesId", value: String(kavitaSeriesId))]


        do {
            let request = try await makeRequest(path: endpoint, queryItems: queryItems, method: "GET")
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  200..<300 ~= httpResponse.statusCode else {
                return []
            }

            // Check if we got HTML
            if let responseString = String(data: data, encoding: .utf8),
               responseString.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<") {
                return []
            }


            // Parse the series-detail response
            if let chapters = tryParseChaptersFromResponse(data, endpoint: endpoint) {
                return chapters
            }

        } catch {
        }

        return []
    }

    private func tryParseChaptersFromResponse(_ data: Data, endpoint: String) -> [SeriesChapter]? {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        // Try parsing as different possible structures

        // 1. Direct array of volumes
        if let volumes = try? decoder.decode([KavitaVolumeDTO].self, from: data) {
            return parseChaptersFromVolumes(volumes)
        }

        // 2. Direct array of chapters
        if let chapters = try? decoder.decode([KavitaChapterDTO].self, from: data) {
            return parseChaptersFromChapterList(chapters)
        }

        // 3. Object with volumes property
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let volumesData = json["volumes"],
           let volumesJsonData = try? JSONSerialization.data(withJSONObject: volumesData),
           let volumes = try? decoder.decode([KavitaVolumeDTO].self, from: volumesJsonData) {
            return parseChaptersFromVolumes(volumes)
        }

        // 4. Object with chapters property
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let chaptersData = json["chapters"],
           let chaptersJsonData = try? JSONSerialization.data(withJSONObject: chaptersData),
           let chapters = try? decoder.decode([KavitaChapterDTO].self, from: chaptersJsonData) {
            return parseChaptersFromChapterList(chapters)
        }

        return nil
    }

    private func parseChaptersFromVolumes(_ volumes: [KavitaVolumeDTO]) -> [SeriesChapter] {
        var allChapters: [SeriesChapter] = []

        for (_, volume) in volumes.enumerated() {
            if let chapters = volume.chapters {
                for (chapterIndex, chapter) in chapters.enumerated() {
                    // Handle the weird "-100000" numbers from Kavita
                    let chapterNumber: Double = {
                        if let num = Double(chapter.number), num > -10000 {
                            return num
                        }
                        // Use sortOrder if available and reasonable
                        if let sortOrder = chapter.sortOrder, sortOrder > -10000 {
                            return Double(sortOrder)
                        }
                        // Fall back to volume.number + chapter index
                        return Double(volume.number) + Double(chapterIndex) * 0.1
                    }()

                    // Better title handling
                    let chapterTitle: String = {
                        if !chapter.title.isEmpty && !chapter.title.contains("-100000") {
                            return chapter.title
                        }
                        if volume.name.contains("Volume") {
                            return "\(volume.name)"
                        }
                        return "Chapter \(Int(chapterNumber))"
                    }()

                    // Generate volume cover URL
                    let volumeCoverURL = generateVolumeCoverURL(for: volume.id)

                    let seriesChapter = SeriesChapter(
                        id: UUID(),
                        title: chapterTitle,
                        number: chapterNumber,
                        pageCount: chapter.pages ?? 0,
                        lastReadPage: chapter.pagesRead == 0 ? nil : chapter.pagesRead,
                        kavitaVolumeId: volume.id,
                        kavitaChapterId: chapter.id,
                        coverImageURL: volumeCoverURL
                    )
                    allChapters.append(seriesChapter)
                }
            }
        }

        // Sort by volume number first, then by chapter number
        allChapters.sort {
            if abs($0.number - $1.number) < 0.1 {
                return $0.title < $1.title
            }
            return $0.number < $1.number
        }


        return allChapters
    }

    private func generateVolumeCoverURL(for volumeId: Int) -> URL? {
        var items = [URLQueryItem(name: "volumeId", value: String(volumeId))]
        if let key = optionalApiKey {
            items.append(URLQueryItem(name: "apiKey", value: key))
        }
        return baseURL
            .appendingPathComponent("api/image/volume-cover")
            .appendingQueryItems(items)
    }

    private func parseChaptersFromChapterList(_ chapters: [KavitaChapterDTO]) -> [SeriesChapter] {
        var allChapters: [SeriesChapter] = []
        for chapter in chapters {
            let chapterNumber = Double(chapter.number) ?? Double(allChapters.count + 1)
            let seriesChapter = SeriesChapter(
                id: UUID(),
                title: chapter.title.isEmpty ? "Chapter \(Int(chapterNumber))" : chapter.title,
                number: chapterNumber,
                pageCount: chapter.pages ?? 0,
                lastReadPage: nil
            )
            allChapters.append(seriesChapter)
        }
        allChapters.sort { $0.number < $1.number }
        return allChapters
    }

    func pageImageURL(seriesID: UUID, chapterID: UUID, pageNumber: Int) throws -> URL {
        guard pageNumber > 0 else {
            throw LibraryServiceError.invalidResponse
        }

        // For Kavita, we need to use chapterID as the actual Kavita chapter ID
        // The URL pattern should be: /api/reader/image?chapterId=X&page=Y&apiKey=Z
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "chapterId", value: chapterID.uuidString),
            URLQueryItem(name: "page", value: String(pageNumber))
        ]
        if let key = optionalApiKey {
            queryItems.append(URLQueryItem(name: "apiKey", value: key))
        }

        guard let url = buildURL(path: "/api/reader/image", queryItems: queryItems) else {
            throw LibraryServiceError.invalidBaseURL
        }
        return url
    }

    func pageImageURL(kavitaChapterId: Int, pageNumber: Int) throws -> URL {
        guard pageNumber > 0 else {
            throw LibraryServiceError.invalidResponse
        }

        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "chapterId", value: String(kavitaChapterId)),
            URLQueryItem(name: "page", value: String(pageNumber))
        ]
        if let key = optionalApiKey {
            queryItems.append(URLQueryItem(name: "apiKey", value: key))
        }

        guard let url = buildURL(path: "/api/reader/image", queryItems: queryItems) else {
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

        if !apiKey.isEmpty {
            // Get Bearer token using API Key like Kavya does
            if let bearerToken = await authenticateWithAPIKey() {
                request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
            } else {
                throw LibraryServiceError.requestFailed(statusCode: 401)
            }
        } else {
            // Fallback to Bearer JWT token from login
            if let data = KeychainHelper.shared.read(key: "kavita_api_token"),
               let token = String(data: data, encoding: .utf8),
               !token.isEmpty {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
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
    func toDomain(baseURL: URL? = nil, apiKey: String? = nil) -> LibrarySeries {
        // Generate cover image URL using discovered API pattern if baseURL and apiKey are available
        var coverURL: URL? = nil
        if let baseURL = baseURL, let apiKey = apiKey {
            coverURL = baseURL
                .appendingPathComponent("api/image/series-cover")
                .appendingQueryItems([
                    URLQueryItem(name: "seriesId", value: String(seriesId)),
                    URLQueryItem(name: "apiKey", value: apiKey)
                ])
        }

        return LibrarySeries(
            id: UUID(), // Generate a UUID for SwiftUI
            kavitaSeriesId: seriesId, // Store the actual Kavita series ID
            title: seriesName,
            author: "", // Not available in this endpoint
            coverColorHexes: ["#6B73FF", "#9B59B6"], // Default colors
            coverURL: coverURL
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
    func toDomain(baseURL: URL? = nil, apiKey: String? = nil) -> LibrarySeries {
        // Extract colors from primaryColor and secondaryColor
        var colors = ["#6B73FF", "#9B59B6"] // Default colors
        if let primary = primaryColor, !primary.isEmpty {
            colors[0] = primary
        }
        if let secondary = secondaryColor, !secondary.isEmpty {
            colors.append(secondary)
        }

        // Generate cover image URL using discovered API pattern if baseURL and apiKey are available
        var coverURL: URL? = nil
        if let baseURL = baseURL, let apiKey = apiKey {
            coverURL = baseURL
                .appendingPathComponent("api/image/series-cover")
                .appendingQueryItems([
                    URLQueryItem(name: "seriesId", value: String(id)),
                    URLQueryItem(name: "apiKey", value: apiKey)
                ])
        }

        return LibrarySeries(
            id: UUID(), // Generate a UUID for SwiftUI
            kavitaSeriesId: id, // Store the actual Kavita series ID
            title: name,
            author: "", // Not available in this endpoint
            coverColorHexes: colors,
            coverURL: coverURL
        )
    }
}

// Kavita series detail DTO based on actual API response
private struct KavitaSeriesDetailDTO: Decodable {
    let id: Int
    let name: String
    let originalName: String?
    let localizedName: String?
    let sortName: String?
    let pages: Int?
    let pagesRead: Int?
    let latestReadDate: String?
    let lastChapterAdded: String?
    let userRating: Int?
    let hasUserRated: Bool?
    let format: Int?
    let created: String?
    let wordCount: Int?
    let libraryId: Int?
    let libraryName: String?
    let minHoursToRead: Int?
    let maxHoursToRead: Int?
    let avgHoursToRead: Double?
    let folderPath: String?
    let lowestFolderPath: String?
    let coverImage: String?
    let primaryColor: String?
    let secondaryColor: String?
    let coverImageLocked: Bool?
    let nameLocked: Bool?
    let sortNameLocked: Bool?
    let localizedNameLocked: Bool?
    let dontMatch: Bool?
    let isBlacklisted: Bool?
}

private struct KavitaVolumeDTO: Decodable {
    let id: Int
    let name: String
    let number: Int
    let pages: Int?
    let chapters: [KavitaChapterDTO]?
    let minNumber: Int?
    let maxNumber: Int?
    let pagesRead: Int?
    let seriesId: Int?
}

private struct KavitaChapterDTO: Decodable {
    let id: Int
    let title: String
    let number: String
    let pages: Int?
    let volumeId: Int
    let range: String?
    let minNumber: Int?
    let maxNumber: Int?
    let sortOrder: Int?
    let isSpecial: Bool?
    let pagesRead: Int?
}

extension KavitaSeriesDetailDTO {
    func toDomain() -> SeriesDetail {
        // For now, we'll create empty chapters array since chapters need to be fetched separately
        let allChapters: [SeriesChapter] = []

        return SeriesDetail(
            id: UUID(), // Generate UUID for SwiftUI
            title: name,
            author: "", // Not available in this DTO
            summary: "총 \(pages ?? 0)페이지", // Use basic info for now
            coverImageURL: nil, // Will be generated separately
            chapters: allChapters
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
                throw LibraryServiceError.requestFailed(statusCode: (response as? HTTPURLResponse)?.statusCode ?? -1)
            }

            // Check if we got HTML instead of JSON (SPA routing issue)
            if isHTMLResponse(data) {

                // Try the exact 3 sections from Kavita's home page
                let alternatives: [(path: String, queryItems: [URLQueryItem]?)] = [
                    ("/api/Series/recently-updated", [URLQueryItem(name: "pageSize", value: "20")]),
                    ("/api/Series/newly-added", [URLQueryItem(name: "pageSize", value: "20")]),
                    ("/api/Series/recently-added", [URLQueryItem(name: "pageSize", value: "20")]),
                    ("/api/account/dashboard", nil)
                ]

                for (altPath, altQuery) in alternatives {
                    do {
                        let altRequest = try await makeRequest(path: altPath, queryItems: altQuery)
                        let (altData, altResponse) = try await session.data(for: altRequest)

                        if let http = altResponse as? HTTPURLResponse,
                           (200..<300).contains(http.statusCode),
                           !isHTMLResponse(altData) {
                            return parseSeriesArray(from: altData) ?? []
                        }
                    } catch {
                        continue
                    }
                }

                // As final fallback, try minimal headers on original path
                do {

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
                        return parseSeriesArray(from: retryData) ?? []
                    }
                } catch {
                }

                // All alternatives failed
                return []
            }

            // Print series JSON for debugging

            if let items = parseSeriesArray(from: data) {
                return items
            } else {
                throw LibraryServiceError.decodingFailed
            }
        } catch {
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
            result.append(SeriesInfo(id: idValue, kavitaSeriesId: nil, title: title, author: author, coverColorHexes: colors, coverURL: coverURL))
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


        do {
            let (data, response) = try await session.data(for: request)


            if let http = response as? HTTPURLResponse,
               (200..<300).contains(http.statusCode),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let token = json["token"] as? String {


                // Cache the JWT
                if let tokenData = token.data(using: .utf8) {
                    _ = KeychainHelper.shared.save(key: cacheKey, data: tokenData)
                }

                return token
            }
        } catch {
        }

        return nil
    }

    // MARK: - Reading Progress Methods

    /// 읽기 진행률을 Kavita 서버에 저장
    public func saveProgress(seriesId: Int, volumeId: Int, chapterId: Int, pageNumber: Int) async throws {
        let path = "/api/reader/progress"

        let progressRequest = ProgressUpdateRequest(
            volumeId: volumeId,
            chapterId: chapterId,
            pageNum: pageNumber,
            seriesId: seriesId,
            libraryId: 1, // 기본값, 실제로는 라이브러리 ID를 가져와야 함
            bookScrollId: nil
        )

        let encoder = JSONEncoder()
        guard let requestBody = try? encoder.encode(progressRequest) else {
            throw LibraryServiceError.invalidResponse
        }

        let request = try await makeRequest(path: path, method: "POST", body: requestBody)


        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LibraryServiceError.invalidResponse
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            throw LibraryServiceError.requestFailed(statusCode: httpResponse.statusCode)
        }
    }

    /// 특정 챕터의 읽기 진행률을 조회
    public func getProgress(chapterId: Int) async throws -> ProgressDto? {
        let path = "/api/reader/get-progress"
        let queryItems = [URLQueryItem(name: "chapterId", value: String(chapterId))]

        let request = try await makeRequest(path: path, queryItems: queryItems, method: "GET")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LibraryServiceError.invalidResponse
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            if httpResponse.statusCode == 404 {
                return nil
            }
            throw LibraryServiceError.requestFailed(statusCode: httpResponse.statusCode)
        }

        let decoder = JSONDecoder()

        do {
            let progress = try decoder.decode(ProgressDto.self, from: data)
            return progress
        } catch {
            return nil
        }
    }

    /// 시리즈의 이어서 읽기 지점을 조회
    public func getContinuePoint(seriesId: Int) async throws -> ContinuePointDto? {
        let path = "/api/reader/continue-point"
        let queryItems = [URLQueryItem(name: "seriesId", value: String(seriesId))]

        let request = try await makeRequest(path: path, queryItems: queryItems, method: "GET")


        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LibraryServiceError.invalidResponse
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            if httpResponse.statusCode == 404 {
                return nil
            }
            throw LibraryServiceError.requestFailed(statusCode: httpResponse.statusCode)
        }

        let decoder = JSONDecoder()

        do {
            let continuePoint = try decoder.decode(ContinuePointDto.self, from: data)
            return continuePoint
        } catch {
            return nil
        }
    }

    /// 챕터의 진행률을 가져와서 SeriesChapter 모델을 업데이트
    public func getChapterWithProgress(kavitaChapterId: Int, existingChapter: SeriesChapter) async -> SeriesChapter {
        do {
            if let progress = try await getProgress(chapterId: kavitaChapterId) {
                return SeriesChapter(
                    id: existingChapter.id,
                    title: existingChapter.title,
                    number: existingChapter.number,
                    pageCount: existingChapter.pageCount,
                    lastReadPage: progress.pageNum > 0 ? progress.pageNum : nil,
                    kavitaVolumeId: existingChapter.kavitaVolumeId,
                    kavitaChapterId: existingChapter.kavitaChapterId,
                    coverImageURL: existingChapter.coverImageURL
                )
            }
        } catch {
            // Failed to get progress
        }

        return existingChapter
    }

    /// 이어서 읽기 항목들을 가져오기 (진행 중인 시리즈들)
    public func fetchContinueReadingItems() async -> [ContinueReadingItem] {
        // Kavita의 "on-deck" 엔드포인트 사용
        let path = "/api/series/on-deck"
        let queryItems = [
            URLQueryItem(name: "libraryId", value: "0"),
            URLQueryItem(name: "pageNumber", value: "1"),
            URLQueryItem(name: "pageSize", value: "10")
        ]

        do {
            // POST 요청이므로 빈 JSON body 전송
            let emptyBody = "{}".data(using: .utf8)!
            let request = try await makeRequest(path: path, queryItems: queryItems, method: "POST", body: emptyBody)

            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                return []
            }

            guard 200..<300 ~= httpResponse.statusCode else {
                return []
            }

            // HTML 응답 체크
            if isHTMLResponse(data) {
                return []
            }

            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase

            // on-deck 응답 파싱 시도
            if let onDeckItems = try? decoder.decode([KavitaOnDeckDTO].self, from: data) {
                var continueItems: [ContinueReadingItem] = []

                for item in onDeckItems {
                    // 각 on-deck 항목에 대해 시리즈 정보와 진행률 가져오기
                    if let continueItem = await createContinueReadingItem(from: item) {
                        continueItems.append(continueItem)
                    }
                }

                return continueItems
            }

        } catch {
        }

        return []
    }

    private func createContinueReadingItem(from onDeckItem: KavitaOnDeckDTO) async -> ContinueReadingItem? {
        // 시리즈 정보 생성
        let series = LibrarySeries(
            id: UUID(),
            kavitaSeriesId: onDeckItem.seriesId,
            title: onDeckItem.seriesName,
            author: "",
            coverColorHexes: ["#6B73FF", "#9B59B6"],
            coverURL: generateCoverURL(for: onDeckItem.seriesId)
        )

        // 챕터 정보 생성 (on-deck에서 제공하는 정보 사용)
        let chapter = SeriesChapter(
            id: UUID(),
            title: onDeckItem.chapterTitle ?? "Chapter \(onDeckItem.chapterNumber ?? 1)",
            number: Double(onDeckItem.chapterNumber ?? 1),
            pageCount: onDeckItem.pages ?? 0,
            lastReadPage: onDeckItem.pagesRead ?? 0,
            kavitaVolumeId: onDeckItem.volumeId,
            kavitaChapterId: onDeckItem.chapterId
        )

        // 진행률 정보 생성
        let progress = ProgressDto(
            volumeId: onDeckItem.volumeId ?? 0,
            chapterId: onDeckItem.chapterId ?? 0,
            pageNum: onDeckItem.pagesRead ?? 0,
            seriesId: onDeckItem.seriesId,
            libraryId: onDeckItem.libraryId ?? 1,
            bookScrollId: nil,
            lastModifiedUtc: ISO8601DateFormatter().string(from: Date())
        )

        return ContinueReadingItem(
            series: series,
            lastReadChapter: chapter,
            progress: progress
        )
    }
}

// MARK: - Kavita On-Deck DTO

private struct KavitaOnDeckDTO: Decodable {
    let seriesId: Int
    let seriesName: String
    let volumeId: Int?
    let chapterId: Int?
    let chapterNumber: Int?
    let chapterTitle: String?
    let pages: Int?
    let pagesRead: Int?
    let libraryId: Int?
    let created: String?
}
