import CryptoKit
import Foundation
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
         session: URLSession? = nil,
         sectionsPath: String = "/api/Library/libraries",
         seriesDetailPathTemplate: String = "/api/Library/series/%@",
         pagePathTemplate: String = "/api/Library/series/%@/chapter/%@/page/%d")
    {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.session = session ?? KavitaServerSession.session(for: baseURL.absoluteString)
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
        let emptyJsonBody = "{}".data(using: .utf8)!

        // Fetch catalog and Want to Read in parallel.
        async let recentlyAddedTask = fetchSeriesFromEndpoint("/api/Series/recently-added-v2", body: emptyJsonBody)
        async let allSeriesTask = fetchSeriesFromEndpoint("/api/Series/all-v2", body: emptyJsonBody)
        async let wantToReadTask = fetchSeriesFromEndpoint("/api/want-to-read/v2", body: emptyJsonBody)

        let (recentlyAddedDTOs, allSeriesDTOs, wantToReadDTOs) = try await (recentlyAddedTask, allSeriesTask, wantToReadTask)
        let readStatusByID = Dictionary(uniqueKeysWithValues: allSeriesDTOs.map { ($0.id, $0.isRead) })
        let recentlyAddedSeries = recentlyAddedDTOs.map { $0.toDomain(baseURL: baseURL, apiKey: optionalApiKey) }
        let allSeries = allSeriesDTOs.map { $0.toDomain(baseURL: baseURL, apiKey: optionalApiKey) }

        var sections: [LibrarySection] = []

        // Keep the complete results in the local catalog; the home view limits display.
        if !recentlyAddedSeries.isEmpty {
            let recentItems = recentlyAddedSeries.map { series in
                SeriesInfo(id: series.id, kavitaSeriesId: series.kavitaSeriesId, title: series.title,
                           author: series.author, coverColorHexes: series.coverColorHexes,
                           coverURL: series.coverURL,
                           isRead: series.kavitaSeriesId.flatMap { readStatusByID[$0] } ?? series.isRead,
                           totalPages: series.totalPages, pagesRead: series.pagesRead)
            }
            sections.append(LibrarySection(id: deterministicUUID(from: "section|recently-added"),
                                           title: "Recently Added", items: recentItems))
        }

        let readingSeries = allSeriesDTOs
            .filter(\.isReading)
            .sorted { lhs, rhs in
                let lhsDate = lhs.latestReadDate ?? ""
                let rhsDate = rhs.latestReadDate ?? ""
                return lhsDate == rhsDate
                    ? lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                    : lhsDate > rhsDate
            }
            .map { $0.toDomain(baseURL: baseURL, apiKey: optionalApiKey) }
        if !readingSeries.isEmpty {
            let readingItems = readingSeries.map { series in
                SeriesInfo(id: series.id, kavitaSeriesId: series.kavitaSeriesId, title: series.title,
                           author: series.author, coverColorHexes: series.coverColorHexes,
                           coverURL: series.coverURL, isRead: series.isRead,
                           totalPages: series.totalPages, pagesRead: series.pagesRead)
            }
            sections.insert(LibrarySection(id: deterministicUUID(from: "section|reading"),
                                           title: "읽는 중", items: readingItems), at: 0)
        }

        // All Series section (sort alphabetically)
        if !allSeries.isEmpty {
            let sortedSeries = allSeries
                .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            let allItems = sortedSeries.map { series in
                SeriesInfo(id: series.id, kavitaSeriesId: series.kavitaSeriesId, title: series.title,
                           author: series.author, coverColorHexes: series.coverColorHexes,
                           coverURL: series.coverURL, isRead: series.isRead,
                           totalPages: series.totalPages, pagesRead: series.pagesRead)
            }
            sections.append(LibrarySection(id: deterministicUUID(from: "section|all-series"),
                                           title: "All Series", items: allItems))
        }

        let favouriteItems = wantToReadDTOs.map { dto -> SeriesInfo in
            let series = dto.toDomain(baseURL: baseURL, apiKey: optionalApiKey)
            return SeriesInfo(id: series.id, kavitaSeriesId: series.kavitaSeriesId, title: series.title,
                              author: series.author, coverColorHexes: series.coverColorHexes,
                              coverURL: series.coverURL, isRead: readStatusByID[dto.id] ?? series.isRead,
                              totalPages: series.totalPages, pagesRead: series.pagesRead)
        }
        sections.insert(LibrarySection(id: deterministicUUID(from: "section|favourite"),
                                       title: "Favourite", items: favouriteItems), at: 0)

        return sections
    }

    func isSeriesInWantToRead(seriesId: Int) async throws -> Bool {
        let request = try await makeRequest(path: "/api/want-to-read",
                                            queryItems: [URLQueryItem(name: "seriesId", value: String(seriesId))])
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw LibraryServiceError.invalidResponse }
        guard 200 ..< 300 ~= http.statusCode else {
            throw LibraryServiceError.requestFailed(statusCode: http.statusCode)
        }
        guard let value = try? JSONDecoder().decode(Bool.self, from: data) else {
            throw LibraryServiceError.decodingFailed
        }
        return value
    }

    func setWantToRead(seriesId: Int, isWanted: Bool) async throws {
        let path = isWanted ? "/api/want-to-read/add-series" : "/api/want-to-read/remove-series"
        let body = try JSONEncoder().encode(UpdateWantToReadRequest(seriesIds: [seriesId]))
        let request = try await makeRequest(path: path, method: "POST", body: body)
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw LibraryServiceError.invalidResponse }
        guard 200 ..< 300 ~= http.statusCode else {
            throw LibraryServiceError.requestFailed(statusCode: http.statusCode)
        }
    }

    func fetchFullSection(sectionTitle: String) async throws -> [LibrarySeries] {
        // Based on browser network analysis, Kavita uses POST with empty JSON body
        let emptyJsonBody = "{}".data(using: .utf8)!

        if sectionTitle == "읽는 중" {
            let series = try await fetchSeriesFromEndpoint("/api/Series/all-v2", body: emptyJsonBody)
            return series
                .filter(\.isReading)
                .sorted { ($0.latestReadDate ?? "") > ($1.latestReadDate ?? "") }
                .map { $0.toDomain(baseURL: baseURL, apiKey: optionalApiKey) }
        }

        if sectionTitle == "Favourite" {
            return try await fetchSeriesFromEndpoint("/api/want-to-read/v2", body: emptyJsonBody)
                .map { $0.toDomain(baseURL: baseURL, apiKey: optionalApiKey) }
        }

        // Determine endpoint based on section title
        let endpoint: String
        switch sectionTitle {
        case "Recently Added":
            endpoint = "/api/Series/recently-added-v2"
        case "All Series":
            endpoint = "/api/Series/all-v2"
        default:
            endpoint = "/api/Series/all-v2"
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
               responseString.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<")
            {
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
                        return domainSeries
                            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
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
              200 ..< 300 ~= httpResponse.statusCode
        else {
            throw LibraryServiceError.requestFailed(statusCode: (seriesResponse as? HTTPURLResponse)?.statusCode ?? -1)
        }

        // Check if we got HTML instead of JSON
        if let responseString = String(data: seriesData, encoding: .utf8),
           responseString.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<")
        {
            throw LibraryServiceError.decodingFailed
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        guard let seriesDetail = try? decoder.decode(KavitaSeriesDetailDTO.self, from: seriesData) else {
            throw LibraryServiceError.decodingFailed
        }

        // Try to get chapters/volumes for this series
        let chapters = try await fetchChaptersForSeries(kavitaSeriesId: kavitaSeriesId)

        // Convert to domain model with chapters
        return SeriesDetail(id: UUID(),
                            title: seriesDetail.name,
                            author: seriesDetail.libraryName ?? "",
                            summary: "총 \(seriesDetail.pages ?? 0)페이지",
                            coverImageURL: generateCoverURL(for: kavitaSeriesId),
                            chapters: chapters,
                            libraryId: seriesDetail.libraryId)
    }

    /// Read Kavita's existing metadata without changing the series or its files.
    func fetchSeriesMetadata(kavitaSeriesId: Int) async throws -> LibraryPlusMetadata {
        let request = try await makeRequest(path: "/api/Series/metadata",
                                            queryItems: [URLQueryItem(name: "seriesId", value: String(kavitaSeriesId))])
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw LibraryServiceError.invalidResponse }
        guard 200 ..< 300 ~= http.statusCode else {
            throw LibraryServiceError.requestFailed(statusCode: http.statusCode)
        }
        guard let dto = try? JSONDecoder().decode(KavitaSeriesMetadataDTO.self, from: data) else {
            throw LibraryServiceError.decodingFailed
        }
        return LibraryPlusMetadata(summary: dto.summary ?? "",
                                   genres: dto.genres?.compactMap(\.title) ?? [],
                                   tags: dto.tags?.compactMap(\.title) ?? [])
    }

    func pageImageURL(seriesID _: UUID, chapterID: UUID, pageNumber: Int) throws -> URL {
        guard pageNumber > 0 else {
            throw LibraryServiceError.invalidResponse
        }

        // For Kavita, we need to use chapterID as the actual Kavita chapter ID
        // The URL pattern should be: /api/reader/image?chapterId=X&page=Y&apiKey=Z
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "chapterId", value: chapterID.uuidString),
            // Reader pages start at 1; Kavita image indexes start at 0 (the cover).
            URLQueryItem(name: "page", value: String(pageNumber - 1)),
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
            // Keep the cover at reader page 1 and the last image within bounds.
            URLQueryItem(name: "page", value: String(pageNumber - 1)),
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

    private var optionalApiKey: String? {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // Helper method for cleaner parallel API calls
    private func fetchSeriesFromEndpoint(_ endpoint: String, body: Data) async throws -> [KavitaFullSeriesDTO] {
        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let pageSize = 100
            var pageNumber = 1
            var series: [KavitaFullSeriesDTO] = []
            var seenIDs = Set<Int>()

            while true {
                let request = try await makeRequest(path: endpoint,
                                                    queryItems: [URLQueryItem(name: "PageNumber", value: String(pageNumber)),
                                                                 URLQueryItem(name: "PageSize", value: String(pageSize))],
                                                    method: "POST", body: body)
                let (data, response) = try await session.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw LibraryServiceError.invalidResponse
                }
                guard 200 ..< 300 ~= httpResponse.statusCode else {
                    throw LibraryServiceError.requestFailed(statusCode: httpResponse.statusCode)
                }
                if let responseString = String(data: data, encoding: .utf8),
                   responseString.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<")
                {
                    throw LibraryServiceError.decodingFailed
                }

                let page = try decoder.decode([KavitaFullSeriesDTO].self, from: data)
                let newItems = page.filter { seenIDs.insert($0.id).inserted }
                series.append(contentsOf: newItems)
                // A repeated page also terminates safely if an older server ignores pagination.
                if page.isEmpty || newItems.isEmpty { break }
                pageNumber += 1
            }
            return series
        } catch {
            #if DEBUG
                Self.logger.error("Failed to fetch series from \(endpoint): \(error.localizedDescription)")
            #endif
            throw error
        }
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

    private func fetchChaptersForSeries(kavitaSeriesId: Int) async throws -> [SeriesChapter] {
        // Use the discovered working endpoint
        let endpoint = "/api/series/series-detail"
        let queryItems = [URLQueryItem(name: "seriesId", value: String(kavitaSeriesId))]

        let request = try await makeRequest(path: endpoint, queryItems: queryItems, method: "GET")
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              200 ..< 300 ~= httpResponse.statusCode
        else {
            throw LibraryServiceError.requestFailed(statusCode: (response as? HTTPURLResponse)?.statusCode ?? -1)
        }

        if let responseString = String(data: data, encoding: .utf8),
           responseString.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<")
        {
            throw LibraryServiceError.decodingFailed
        }

        guard let chapters = tryParseChaptersFromResponse(data, endpoint: endpoint) else {
            throw LibraryServiceError.decodingFailed
        }
        return chapters
    }

    private func tryParseChaptersFromResponse(_ data: Data, endpoint _: String) -> [SeriesChapter]? {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        // Kavita returns specials separately from volumes and loose chapters.
        if let detail = try? decoder.decode(KavitaSeriesContentsDTO.self, from: data) {
            let specialIDs = Set(detail.specials?.map(\.id) ?? [])
            let chapters = parseChaptersFromVolumes(detail.volumes ?? [], specialIDs: specialIDs)
                + parseChaptersFromChapterList(detail.chapters ?? [], specialIDs: specialIDs)
                + parseChaptersFromChapterList(detail.storylineChapters ?? [], specialIDs: specialIDs)
                + parseChaptersFromChapterList(detail.specials ?? [], forceSpecial: true)
            return orderedChapters(chapters)
        }

        // Older responses may be direct arrays.
        if let volumes = try? decoder.decode([KavitaVolumeDTO].self, from: data) {
            return orderedChapters(parseChaptersFromVolumes(volumes))
        }
        if let chapters = try? decoder.decode([KavitaChapterDTO].self, from: data) {
            return orderedChapters(parseChaptersFromChapterList(chapters))
        }

        return nil
    }

    private func parseChaptersFromVolumes(_ volumes: [KavitaVolumeDTO], specialIDs: Set<Int> = []) -> [SeriesChapter] {
        var allChapters: [SeriesChapter] = []

        for volume in volumes {
            if let chapters = volume.chapters {
                for (chapterIndex, chapter) in chapters.enumerated() {
                    let isSpecial = chapter.isSpecial == true || specialIDs.contains(chapter.id)
                    let chapterNumber = resolvedChapterNumber(chapter,
                                                              fallback: Double(volume.number ?? 0) + Double(chapterIndex) * 0.1)
                    let volumeID = chapter.volumeId ?? volume.id
                    allChapters.append(SeriesChapter(id: UUID(),
                                                     title: resolvedChapterTitle(chapter, number: chapterNumber,
                                                                                 volumeName: volume.name, index: chapterIndex,
                                                                                 isSpecial: isSpecial),
                                                     number: chapterNumber,
                                                     pageCount: chapter.pages ?? 0,
                                                     lastReadPage: (chapter.pagesRead ?? 0) > 0 ? chapter.pagesRead : nil,
                                                     kavitaVolumeId: volumeID,
                                                     kavitaChapterId: chapter.id,
                                                     coverImageURL: generateChapterCoverURL(for: chapter.id),
                                                     isSpecial: isSpecial))
                }
            }
        }
        return allChapters
    }

    private func generateChapterCoverURL(for chapterId: Int) -> URL? {
        var items = [URLQueryItem(name: "chapterId", value: String(chapterId))]
        if let key = optionalApiKey {
            items.append(URLQueryItem(name: "apiKey", value: key))
        }
        return baseURL
            .appendingPathComponent("api/image/chapter-cover")
            .appendingQueryItems(items)
    }

    private func parseChaptersFromChapterList(_ chapters: [KavitaChapterDTO],
                                              specialIDs: Set<Int> = [], forceSpecial: Bool = false) -> [SeriesChapter]
    {
        chapters.enumerated().map { index, chapter in
            let isSpecial = forceSpecial || chapter.isSpecial == true || specialIDs.contains(chapter.id)
            let chapterNumber = resolvedChapterNumber(chapter, fallback: Double(index + 1))
            let volumeID = chapter.volumeId.flatMap { $0 > 0 ? $0 : nil }
            return SeriesChapter(id: UUID(),
                                 title: resolvedChapterTitle(chapter, number: chapterNumber,
                                                             volumeName: nil, index: index, isSpecial: isSpecial),
                                 number: chapterNumber,
                                 pageCount: chapter.pages ?? 0,
                                 lastReadPage: (chapter.pagesRead ?? 0) > 0 ? chapter.pagesRead : nil,
                                 kavitaVolumeId: volumeID,
                                 kavitaChapterId: chapter.id,
                                 coverImageURL: generateChapterCoverURL(for: chapter.id),
                                 isSpecial: isSpecial)
        }
    }

    private func resolvedChapterNumber(_ chapter: KavitaChapterDTO, fallback: Double) -> Double {
        if let number = chapter.number.flatMap(Double.init), number > -10000 { return number }
        if let number = chapter.minNumber, number > -10000 { return number }
        if let number = chapter.sortOrder, number > -10000 { return number }
        return fallback
    }

    private func resolvedChapterTitle(_ chapter: KavitaChapterDTO, number: Double,
                                      volumeName: String?, index: Int, isSpecial: Bool) -> String
    {
        if let title = chapter.title, !title.isEmpty, !title.contains("-100000") { return title }
        if isSpecial { return "Special \(index + 1)" }
        if let volumeName, volumeName.contains("Volume") { return volumeName }
        return "Chapter \(Int(number))"
    }

    private func orderedChapters(_ chapters: [SeriesChapter]) -> [SeriesChapter] {
        var seenIDs = Set<Int>()
        let unique = chapters.filter { chapter in
            guard let id = chapter.kavitaChapterId else { return true }
            return seenIDs.insert(id).inserted
        }
        let regular = unique.filter { !$0.isSpecial }.sorted { lhs, rhs in
            if abs(lhs.number - rhs.number) < 0.1 { return lhs.title < rhs.title }
            return lhs.number < rhs.number
        }
        return regular + unique.filter(\.isSpecial)
    }

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

        if !apiKey.isEmpty {
            let bearerToken = try await authenticateWithAPIKey()
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        } else {
            // Fallback to Bearer JWT token from login
            let token = KavitaCredentials.read(server: baseURL.absoluteString, field: "token")
            if !token.isEmpty
            {
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

private struct UpdateWantToReadRequest: Encodable {
    let seriesIds: [Int]
}

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
                    URLQueryItem(name: "apiKey", value: apiKey),
                ])
        }

        return LibrarySeries(id: UUID(), // Generate a UUID for SwiftUI
                             kavitaSeriesId: seriesId, // Store the actual Kavita series ID
                             title: seriesName,
                             author: "", // Not available in this endpoint
                             coverColorHexes: ["#6B73FF", "#9B59B6"], // Default colors
                             coverURL: coverURL)
    }
}

// Full structure for recently-added and all series endpoints
private struct KavitaFullSeriesDTO: Decodable {
    let id: Int
    let name: String
    let primaryColor: String?
    let secondaryColor: String?
    let pages: Int?
    let pagesRead: Int?
    let latestReadDate: String?
    let originalName: String?
    let libraryId: Int?

    var isReading: Bool {
        guard let pagesRead, pagesRead > 0, let pages, pages > 0 else { return false }
        return pagesRead < pages
    }

    var isRead: Bool {
        guard let pages, pages > 0, let pagesRead else { return false }
        return pagesRead >= pages
    }
}

extension KavitaFullSeriesDTO {
    func toDomain(baseURL: URL? = nil, apiKey: String? = nil) -> LibrarySeries {
        // Extract colors from primaryColor and secondaryColor
        var colors = ["#6B73FF", "#9B59B6"] // Default colors
        if let primary = primaryColor, !primary.isEmpty {
            colors[0] = primary
        }
        if let secondary = secondaryColor, !secondary.isEmpty {
            colors[1] = secondary
        }

        // Generate cover image URL using discovered API pattern if baseURL and apiKey are available
        var coverURL: URL? = nil
        if let baseURL = baseURL, let apiKey = apiKey {
            coverURL = baseURL
                .appendingPathComponent("api/image/series-cover")
                .appendingQueryItems([
                    URLQueryItem(name: "seriesId", value: String(id)),
                    URLQueryItem(name: "apiKey", value: apiKey),
                ])
        }

        return LibrarySeries(id: UUID(), // Generate a UUID for SwiftUI
                             kavitaSeriesId: id, // Store the actual Kavita series ID
                             title: name,
                             author: "", // Not available in this endpoint
                             coverColorHexes: colors,
                             coverURL: coverURL,
                             isRead: isRead, totalPages: pages, pagesRead: pagesRead)
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

private struct KavitaSeriesMetadataDTO: Decodable {
    struct NamedTag: Decodable {
        let title: String?
    }

    let summary: String?
    let genres: [NamedTag]?
    let tags: [NamedTag]?
}

private struct KavitaSeriesContentsDTO: Decodable {
    let volumes: [KavitaVolumeDTO]?
    let chapters: [KavitaChapterDTO]?
    let specials: [KavitaChapterDTO]?
    let storylineChapters: [KavitaChapterDTO]?
}

private struct KavitaVolumeDTO: Decodable {
    let id: Int
    let name: String?
    let number: Int?
    let pages: Int?
    let chapters: [KavitaChapterDTO]?
    let minNumber: Double?
    let maxNumber: Double?
    let pagesRead: Int?
    let seriesId: Int?
}

private struct KavitaChapterDTO: Decodable {
    let id: Int
    let title: String?
    let number: String?
    let pages: Int?
    let volumeId: Int?
    let range: String?
    let minNumber: Double?
    let maxNumber: Double?
    let sortOrder: Double?
    let isSpecial: Bool?
    let pagesRead: Int?
}

extension KavitaSeriesDetailDTO {
    func toDomain() -> SeriesDetail {
        // For now, we'll create empty chapters array since chapters need to be fetched separately
        let allChapters: [SeriesChapter] = []

        return SeriesDetail(id: UUID(), // Generate UUID for SwiftUI
                            title: name,
                            author: "", // Not available in this DTO
                            summary: "총 \(pages ?? 0)페이지", // Use basic info for now
                            coverImageURL: nil, // Will be generated separately
                            chapters: allChapters)
    }
}

// MARK: - Fallback DTOs and helpers

private struct KavitaLibraryDTO: Decodable {
    let id: Int
    let name: String
}

// MARK: - Series fetching (fallback when hitting Kavita directly)

private extension KavitaLibraryService {
    func fetchSeriesItems(libraryId _: Int) async throws -> [SeriesInfo] {
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

            guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
                throw LibraryServiceError.requestFailed(statusCode: (response as? HTTPURLResponse)?.statusCode ?? -1)
            }

            // Check if we got HTML instead of JSON (SPA routing issue)
            if isHTMLResponse(data) {
                // Try the exact 3 sections from Kavita's home page
                let alternatives: [(path: String, queryItems: [URLQueryItem]?)] = [
                    ("/api/Series/recently-updated", [URLQueryItem(name: "pageSize", value: "20")]),
                    ("/api/Series/newly-added", [URLQueryItem(name: "pageSize", value: "20")]),
                    ("/api/Series/recently-added", [URLQueryItem(name: "pageSize", value: "20")]),
                    ("/api/account/dashboard", nil),
                ]

                for (altPath, altQuery) in alternatives {
                    do {
                        let altRequest = try await makeRequest(path: altPath, queryItems: altQuery)
                        let (altData, altResponse) = try await session.data(for: altRequest)

                        if let http = altResponse as? HTTPURLResponse,
                           (200 ..< 300).contains(http.statusCode),
                           !isHTMLResponse(altData)
                        {
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
                       (200 ..< 300).contains(http.statusCode),
                       !isHTMLResponse(retryData)
                    {
                        return parseSeriesArray(from: retryData) ?? []
                    }
                } catch {}

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
                if let s = obj["id"] as? String {
                    return UUID(uuidString: s) ?? deterministicUUID(from: "kavita-series-\(s)")
                }
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
            result.append(SeriesInfo(id: idValue, kavitaSeriesId: nil, title: title, author: author,
                                     coverColorHexes: colors, coverURL: coverURL))
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

            guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
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
    let uuid = uuid_t(bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7], bytes[8],
                      bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15])
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

extension KavitaLibraryService {
    // Ensure any URL is absolute against the service baseURL
    private func absolutizeIfNeeded(_ url: URL) -> URL {
        if url.scheme != nil { return url }
        var comps = URLComponents()
        comps.scheme = baseURL.scheme
        comps.host = baseURL.host
        comps.port = baseURL.port
        comps.path = url.absoluteString.hasPrefix("/") ? url.absoluteString : "/" + url.absoluteString
        return comps.url ?? url
    }

    // If using apiKey mode, attach it as query for image URLs (many backends expect api_key on images)
    private func attachApiKeyIfNeeded(_ url: URL) -> URL {
        guard KavitaCredentials.contains(url, server: baseURL.absoluteString) else { return url }
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
    private func isHTMLResponse(_ data: Data) -> Bool {
        guard let s = String(data: data, encoding: .utf8) else { return false }
        let lowered = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return lowered.hasPrefix("<!doctype") || lowered.hasPrefix("<html")
    }

    // Match Kavya/Paperback's API key flow: exchange the key for a JWT, then use Bearer auth.
    private func authenticateWithAPIKey() async throws -> String {
        guard let url = buildURL(path: "/api/Plugin/authenticate", queryItems: [
            URLQueryItem(name: "apiKey", value: apiKey),
            URLQueryItem(name: "pluginName", value: "KavaReader"),
        ]) else {
            throw LibraryServiceError.invalidBaseURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LibraryServiceError.invalidResponse
        }
        guard 200 ..< 300 ~= httpResponse.statusCode else {
            #if DEBUG
                Self.logger.error("Kavita API key authentication failed with status \(httpResponse.statusCode)")
            #endif
            throw LibraryServiceError.requestFailed(statusCode: httpResponse.statusCode)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["token"] as? String,
              !token.isEmpty
        else {
            throw LibraryServiceError.authenticationFailed
        }

        return token
    }

    // MARK: - Reading Progress Methods

    func stopReading(seriesId: Int) async throws {
        let request = try await makeRequest(path: "/api/Series/remove-from-on-deck",
                                            queryItems: [URLQueryItem(name: "seriesId", value: String(seriesId))],
                                            method: "POST")
        let (_, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw LibraryServiceError.invalidResponse
        }
        guard 200 ..< 300 ~= response.statusCode else {
            throw LibraryServiceError.requestFailed(statusCode: response.statusCode)
        }
    }

    func markSeriesReadState(seriesId: Int, read: Bool) async throws {
        let endpoint = read ? "/api/reader/mark-read" : "/api/reader/mark-unread"
        let body = try JSONEncoder().encode(MarkSeriesReadRequest(seriesId: seriesId,
                                                                  generateReadingSession: false))
        let request = try await makeRequest(path: endpoint, method: "POST", body: body)
        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LibraryServiceError.invalidResponse
        }
        guard 200 ..< 300 ~= httpResponse.statusCode else {
            throw LibraryServiceError.requestFailed(statusCode: httpResponse.statusCode)
        }
    }

    func getLibraryId(seriesId: Int) async throws -> Int {
        let request = try await makeRequest(path: "/api/series/\(seriesId)", method: "GET")
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200 ..< 300).contains(httpResponse.statusCode)
        else {
            throw LibraryServiceError.requestFailed(statusCode: (response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let libraryId = try decoder.decode(KavitaSeriesDetailDTO.self, from: data).libraryId else {
            throw LibraryServiceError.invalidResponse
        }
        return libraryId
    }

    /// 읽기 진행률을 Kavita 서버에 저장
    func saveProgress(seriesId: Int, libraryId: Int, volumeId: Int, chapterId: Int,
                      pageNumber: Int) async throws
    {
        let path = "/api/reader/progress"

        let progressRequest = ProgressUpdateRequest(volumeId: volumeId,
                                                    chapterId: chapterId,
                                                    pageNum: pageNumber,
                                                    seriesId: seriesId,
                                                    libraryId: libraryId,
                                                    bookScrollId: nil)

        let encoder = JSONEncoder()
        guard let requestBody = try? encoder.encode(progressRequest) else {
            throw LibraryServiceError.invalidResponse
        }

        let request = try await makeRequest(path: path, method: "POST", body: requestBody)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LibraryServiceError.invalidResponse
        }

        guard 200 ..< 300 ~= httpResponse.statusCode else {
            throw LibraryServiceError.requestFailed(statusCode: httpResponse.statusCode)
        }
    }

    /// 특정 챕터의 읽기 진행률을 조회
    func getProgress(chapterId: Int) async throws -> ProgressDto? {
        let path = "/api/reader/get-progress"
        let queryItems = [URLQueryItem(name: "chapterId", value: String(chapterId))]

        var request = try await makeRequest(path: path, queryItems: queryItems, method: "GET")
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LibraryServiceError.invalidResponse
        }

        guard 200 ..< 300 ~= httpResponse.statusCode else {
            if httpResponse.statusCode == 404 {
                return nil
            }
            throw LibraryServiceError.requestFailed(statusCode: httpResponse.statusCode)
        }

        if data.isEmpty || String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) == "null" {
            return nil
        }

        let decoder = JSONDecoder()

        do {
            let progress = try decoder.decode(ProgressDto.self, from: data)
            return progress
        } catch {
            throw LibraryServiceError.decodingFailed
        }
    }

    /// 시리즈의 이어서 읽기 지점을 조회
    func getContinuePoint(seriesId: Int) async throws -> ContinuePointDto? {
        let path = "/api/reader/continue-point"
        let queryItems = [URLQueryItem(name: "seriesId", value: String(seriesId))]

        var request = try await makeRequest(path: path, queryItems: queryItems, method: "GET")
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LibraryServiceError.invalidResponse
        }

        guard 200 ..< 300 ~= httpResponse.statusCode else {
            if httpResponse.statusCode == 404 {
                return nil
            }
            throw LibraryServiceError.requestFailed(statusCode: httpResponse.statusCode)
        }

        if data.isEmpty || String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) == "null" {
            return nil
        }

        let decoder = JSONDecoder()

        do {
            let continuePoint = try decoder.decode(ContinuePointDto.self, from: data)
            return continuePoint
        } catch {
            throw LibraryServiceError.decodingFailed
        }
    }

    /// 챕터의 진행률을 가져와서 SeriesChapter 모델을 업데이트
    func getChapterWithProgress(kavitaChapterId: Int, existingChapter: SeriesChapter) async -> SeriesChapter {
        do {
            if let progress = try await getProgress(chapterId: kavitaChapterId) {
                return SeriesChapter(id: existingChapter.id,
                                     title: existingChapter.title,
                                     number: existingChapter.number,
                                     pageCount: existingChapter.pageCount,
                                     lastReadPage: progress.pageNum > 0 ? progress.pageNum : nil,
                                     kavitaVolumeId: existingChapter.kavitaVolumeId,
                                     kavitaChapterId: existingChapter.kavitaChapterId,
                                     coverImageURL: existingChapter.coverImageURL,
                                     isSpecial: existingChapter.isSpecial)
            }
        } catch {
            // Failed to get progress
        }

        return existingChapter
    }

    /// On Deck returns SeriesDto records; resume chapters come from the reader API.
    internal func fetchContinueReadingItems() async throws -> [ContinueReadingItem] {
        do {
            let series = try await fetchSeriesFromEndpoint("/api/Series/on-deck", body: Data("{}".utf8))
            var items: [ContinueReadingItem] = []
            for dto in series.prefix(10) {
                try Task.checkCancellation()
                if let item = await createContinueReadingItem(from: dto) {
                    items.append(item)
                }
            }
            return items
        } catch {
            #if DEBUG
                Self.logger.error("Failed to fetch continue reading: \(error.localizedDescription)")
            #endif
            throw error
        }
    }

    private func createContinueReadingItem(from dto: KavitaFullSeriesDTO) async -> ContinueReadingItem? {
        do {
            async let pointTask = getContinuePoint(seriesId: dto.id)
            async let chaptersTask = fetchChaptersForSeries(kavitaSeriesId: dto.id)
            let (point, chapters) = try await (pointTask, chaptersTask)
            guard let point, point.chapterId > 0,
                  let chapter = chapters.first(where: { $0.kavitaChapterId == point.chapterId })
            else { return nil }

            let resumeChapter = SeriesChapter(id: chapter.id, title: chapter.title,
                                              number: chapter.number, pageCount: point.pages,
                                              lastReadPage: point.pagesRead,
                                              kavitaVolumeId: point.volumeId,
                                              kavitaChapterId: point.chapterId,
                                              coverImageURL: chapter.coverImageURL,
                                              isSpecial: chapter.isSpecial)
            let progress = ProgressDto(volumeId: point.volumeId, chapterId: point.chapterId,
                                       pageNum: point.pagesRead, seriesId: dto.id,
                                       libraryId: dto.libraryId ?? 0, bookScrollId: nil,
                                       lastModifiedUtc: dto.latestReadDate ?? "")
            return ContinueReadingItem(series: dto.toDomain(baseURL: baseURL, apiKey: optionalApiKey),
                                       lastReadChapter: resumeChapter, progress: progress)
        } catch {
            // A missing or inaccessible chapter must not hide other resumable series.
            #if DEBUG
                Self.logger.error("Failed to resolve continue reading for series \(dto.id): \(error.localizedDescription)")
            #endif
            return nil
        }
    }

}

// MARK: - Read state request

private struct MarkSeriesReadRequest: Encodable {
    let seriesId: Int
    let generateReadingSession: Bool
}
