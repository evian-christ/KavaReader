import Foundation

/// Uses existing interlanguage links rather than translating or guessing a title.
nonisolated struct WikipediaTitleService: Sendable {
    // MARK: Internal

    let session: URLSession

    static func englishTitle(data: Data) throws -> String? {
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard response.error == nil, let pages = response.query?.pages else {
            throw ExternalLookupError.invalidResponse
        }
        let existingPages = pages.filter { $0.missing != true }
        guard existingPages.count == 1, existingPages.first?.pageprops?["disambiguation"] == nil else { return nil }
        let titles = Set(existingPages
            .flatMap { $0.langlinks ?? [] }.filter { $0.lang == "en" }
            .map { cleanTitle($0.title) }.filter { !$0.isEmpty })
        // Multiple distinct works/editions must never be resolved by result order.
        return titles.count == 1 ? titles.first : nil
    }

    func englishTitle(for title: String) async throws -> String? {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard IndexingSettings.containsKorean(title), !title.contains("|") else { return nil }
        var components = URLComponents(string: "https://ko.wikipedia.org/w/api.php")!
        components.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "formatversion", value: "2"),
            URLQueryItem(name: "redirects", value: "1"),
            URLQueryItem(name: "prop", value: "langlinks|pageprops"),
            URLQueryItem(name: "ppprop", value: "disambiguation"),
            URLQueryItem(name: "lllang", value: "en"),
            URLQueryItem(name: "lllimit", value: "10"),
            URLQueryItem(name: "titles", value: [title, "\(title) (만화)", "\(title) (소설)"].joined(separator: "|")),
        ]
        guard let url = components.url else { throw ExternalLookupError.invalidResponse }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("KavaReader/1.0 (title metadata lookup; kavareader@gmail.com)",
                         forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ExternalLookupError.invalidResponse }
        if http.statusCode == 429 {
            throw ExternalLookupError
                .rateLimited(TimeInterval(http.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 60)
        }
        guard 200 ..< 300 ~= http.statusCode else { throw ExternalLookupError.invalidResponse }
        return try Self.englishTitle(data: data)
    }

    // MARK: Private

    private struct Response: Decodable {
        let query: Query?
        let error: APIError?
    }

    private struct APIError: Decodable { let code: String }
    private struct Query: Decodable { let pages: [Page] }
    private struct Page: Decodable {
        let missing: Bool?
        let pageprops: [String: String]?
        let langlinks: [LanguageLink]?
    }

    private struct LanguageLink: Decodable {
        let lang: String
        let title: String
    }

    private static func cleanTitle(_ title: String) -> String {
        let suffixes = [" (manga)", " (manhwa)", " (novel)", " (light novel)", " (comics)"]
        if let suffix = suffixes.first(where: { title.lowercased().hasSuffix($0) }) {
            return String(title.dropLast(suffix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return title.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
