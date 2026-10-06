import Foundation

/// Optional fallback when the primary source has no genres or tags.
nonisolated struct ExternalSeriesMetadata: Codable, Sendable {
    let aniListID: Int
    let sourceTitle: String
    let sourceURL: URL
    let genres: [String]
    let tags: [String]
}

nonisolated enum ExternalLookupError: Error {
    case rateLimited(TimeInterval)
    case invalidResponse
}

nonisolated struct AniListSearchCandidate: Identifiable, Sendable {
    let id: Int
    let title: String
    let nativeTitle: String?
    let creators: [String]
    let year: Int?
    let format: String?
    let coverURL: URL?
    let metadata: ExternalSeriesMetadata
}

nonisolated struct AniListSearchPage: Sendable {
    let candidates: [AniListSearchCandidate]
    let hasNextPage: Bool
}

nonisolated struct AniListMetadataService: Sendable {
    // MARK: Lifecycle

    init(session: URLSession = .shared, includeNovels: Bool = false) {
        self.session = session
        self.includeNovels = includeNovels
    }

    // MARK: Internal

    let session: URLSession
    let includeNovels: Bool

    static func searchPage(data: Data, includeNovels: Bool = false) throws -> AniListSearchPage {
        let decoded = try JSONDecoder().decode(QueryResponse.self, from: data)
        guard decoded.errors?.isEmpty != false, let page = decoded.data?.page, let media = page.media
        else { throw ExternalLookupError.invalidResponse }
        let candidates = media.filter { includeNovels || $0.format != "NOVEL" }.map { media in
            let metadata = Self.metadata(for: media)
            var seen = Set<String>()
            let creators = (media.staff?.edges ?? []).filter {
                guard let role = $0.role else { return false }
                return ["Story", "Art", "Story & Art", "Original Creator"].contains(role)
            }.compactMap { $0.node?.name?.native ?? $0.node?.name?.full }
                .filter { seen.insert($0).inserted }
            return AniListSearchCandidate(id: media.id, title: metadata.sourceTitle,
                                          nativeTitle: media.title.native, creators: creators,
                                          year: media.startDate?.year, format: media.format,
                                          coverURL: (media.coverImage?.large).flatMap { URL(string: $0) },
                                          metadata: metadata)
        }
        return AniListSearchPage(candidates: candidates, hasNextPage: page.pageInfo?.hasNextPage ?? false)
    }

    static func match(data: Data, title: String, includeNovels: Bool = false) throws -> ExternalSeriesMetadata? {
        if case let .matched(metadata) = try automaticMatch(data: data, title: title, includeNovels: includeNovels) {
            return metadata
        }
        return nil
    }

    /// Human selection does not use the automatic exact-title matcher.
    func search(title: String, page: Int = 1) async throws -> AniListSearchPage {
        let search = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !search.isEmpty else { return AniListSearchPage(candidates: [], hasNextPage: false) }
        let query = includeNovels
            ? Self.searchQuery.replacingOccurrences(of: ", format_not: NOVEL", with: "") : Self.searchQuery
        let data = try await request(query: query, variables: Variables(search: search, page: page))
        return try Self.searchPage(data: data, includeNovels: includeNovels)
    }

    func metadata(id: Int) async throws -> ExternalSeriesMetadata {
        let data = try await request(query: Self.detailQuery, variables: Variables(id: id))
        let decoded = try JSONDecoder().decode(QueryResponse.self, from: data)
        guard decoded.errors?.isEmpty != false, let media = decoded.data?.media,
              media.id == id, includeNovels || media.format != "NOVEL"
        else { throw ExternalLookupError.invalidResponse }
        return Self.metadata(for: media)
    }

    func lookup(title: String, retryWithEnglishTitle: Bool = false) async throws -> ExternalSeriesMetadata? {
        switch try await lookupExact(title: title) {
        case let .matched(metadata): return metadata
        case .ambiguous: return nil
        case .noMatch: break
        }
        guard retryWithEnglishTitle, IndexingSettings.containsKorean(title) else { return nil }
        try Task.checkCancellation()
        guard let englishTitle = try await WikipediaTitleService(session: session).englishTitle(for: title)
        else { return nil }
        // Preserve AniList's pacing even when one work requires two searches.
        try await Task.sleep(for: .seconds(2.5))
        try Task.checkCancellation()
        if case let .matched(metadata) = try await lookupExact(title: englishTitle) { return metadata }
        return nil
    }

    // MARK: Private

    private enum AutomaticMatch {
        case matched(ExternalSeriesMetadata)
        case noMatch
        case ambiguous
    }

    private struct QueryRequest: Encodable {
        let query: String
        let variables: Variables
    }

    private struct Variables: Encodable {
        var search: String? = nil
        var page: Int? = nil
        var id: Int? = nil
    }

    private struct QueryResponse: Decodable {
        struct DataPayload: Decodable {
            enum CodingKeys: String, CodingKey { case page = "Page", media = "Media" }

            let page: Page?
            let media: Media?
        }

        struct Page: Decodable {
            struct PageInfo: Decodable {
                let hasNextPage: Bool?
            }

            let media: [Media]?
            let pageInfo: PageInfo?
        }

        struct Media: Decodable {
            struct StartDate: Decodable { let year: Int? }
            struct CoverImage: Decodable { let large: String? }
            struct Staff: Decodable {
                struct Edge: Decodable {
                    struct Node: Decodable {
                        struct Name: Decodable { let full: String?; let native: String? }

                        let name: Name?
                    }

                    let role: String?
                    let node: Node?
                }

                let edges: [Edge]?
            }

            struct Title: Decodable {
                let romaji: String?
                let english: String?
                let native: String?
            }

            struct Tag: Decodable {
                let name: String?
                let rank: Int?
                let isGeneralSpoiler: Bool?
                let isMediaSpoiler: Bool?
            }

            let id: Int
            let title: Title
            let synonyms: [String]?
            let genres: [String]?
            let tags: [Tag]?
            let format: String?
            let startDate: StartDate?
            let coverImage: CoverImage?
            let staff: Staff?
        }

        struct GraphQLError: Decodable {
            let message: String?
        }

        let data: DataPayload?
        let errors: [GraphQLError]?
    }

    private static let query = """
    query ($search: String!) {
      Page(page: 1, perPage: 50) {
        pageInfo { hasNextPage }
        media(search: $search, type: MANGA) {
          id
          title { romaji english native }
          synonyms
          format
          genres
          tags { name rank isGeneralSpoiler isMediaSpoiler }
        }
      }
    }
    """

    private static let candidateFields = """
    id
    title { romaji english native }
    format
    startDate { year }
    coverImage { large }
    staff(perPage: 10) { edges { role node { name { full native } } } }
    genres
    tags { name rank isGeneralSpoiler isMediaSpoiler }
    """

    private static let searchQuery = """
    query ($search: String!, $page: Int!) {
      Page(page: $page, perPage: 20) {
        pageInfo { hasNextPage }
        media(search: $search, type: MANGA, format_not: NOVEL) {
          \(candidateFields)
        }
      }
    }
    """

    private static let detailQuery = """
    query ($id: Int!) {
      Media(id: $id, type: MANGA) { \(candidateFields) }
    }
    """

    private static func automaticMatch(data: Data, title: String, includeNovels: Bool) throws -> AutomaticMatch {
        let normalizedTitle = normalized(title)
        let decoded = try JSONDecoder().decode(QueryResponse.self, from: data)
        guard decoded.errors?.isEmpty != false,
              let page = decoded.data?.page, let media = page.media
        else { throw ExternalLookupError.invalidResponse }

        let matches = media.filter { media in
            let titles = [media.title.romaji, media.title.english, media.title.native]
                .compactMap { $0 } + (media.synonyms ?? [])
            return titles.contains { normalized($0) == normalizedTitle }
        }
        // Identical names can identify different works or editions. Do not guess.
        guard page.pageInfo?.hasNextPage != true, matches.count <= 1 else { return .ambiguous }
        guard let match = matches.first, includeNovels || match.format != "NOVEL" else { return .noMatch }
        let genres = LibraryPlusMetadata(summary: "", genres: match.genres ?? [], tags: []).genres
        let tags = (match.tags ?? [])
            .filter { ($0.rank ?? 0) >= 75 && $0.isGeneralSpoiler != true && $0.isMediaSpoiler != true }
            .compactMap(\.name)
        let cleaned = LibraryPlusMetadata(summary: "", genres: genres, tags: Array(tags.prefix(8)))
        guard cleaned.hasCategories,
              let sourceURL = URL(string: "https://anilist.co/manga/\(match.id)")
        else { return .noMatch }
        return .matched(ExternalSeriesMetadata(aniListID: match.id,
                                               sourceTitle: match.title.english ?? match.title.romaji ?? title,
                                               sourceURL: sourceURL,
                                               genres: cleaned.genres, tags: cleaned.tags))
    }

    private static func metadata(for media: QueryResponse.Media) -> ExternalSeriesMetadata {
        let tags = (media.tags ?? [])
            .filter { ($0.rank ?? 0) >= 75 && $0.isGeneralSpoiler != true && $0.isMediaSpoiler != true }
            .compactMap(\.name)
        let cleaned = LibraryPlusMetadata(summary: "", genres: media.genres ?? [], tags: Array(tags.prefix(8)))
        return ExternalSeriesMetadata(aniListID: media.id,
                                      sourceTitle: media.title.english ?? media.title.romaji ?? media.title
                                          .native ?? "AniList \(media.id)",
                                      sourceURL: URL(string: "https://anilist.co/manga/\(media.id)")!,
                                      genres: cleaned.genres, tags: cleaned.tags)
    }

    private static func normalized(_ title: String) -> String {
        let folded = title.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                                   locale: Locale(identifier: "en_US_POSIX"))
        return folded.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
            .map { String($0) }.joined()
    }

    private func lookupExact(title: String) async throws -> AutomaticMatch {
        let normalizedTitle = Self.normalized(title)
        guard normalizedTitle.count >= 2,
              let url = URL(string: "https://graphql.anilist.co")
        else { return .noMatch }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(QueryRequest(query: Self.query,
                                                                 variables: Variables(search: title)))

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ExternalLookupError.invalidResponse }
        if http.statusCode == 429 {
            let retryAfter = TimeInterval(http.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 60
            throw ExternalLookupError.rateLimited(max(1, retryAfter))
        }
        guard 200 ..< 300 ~= http.statusCode else { throw ExternalLookupError.invalidResponse }
        return try Self.automaticMatch(data: data, title: title, includeNovels: includeNovels)
    }

    private func request(query: String, variables: Variables) async throws -> Data {
        var request = URLRequest(url: URL(string: "https://graphql.anilist.co")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(QueryRequest(query: query, variables: variables))
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ExternalLookupError.invalidResponse }
        if http.statusCode == 429 {
            let retryAfter = TimeInterval(http.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 60
            throw ExternalLookupError.rateLimited(max(1, retryAfter))
        }
        guard 200 ..< 300 ~= http.statusCode else { throw ExternalLookupError.invalidResponse }
        return data
    }
}
