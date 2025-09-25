import Foundation

struct LibraryServiceFactory {
    var baseURLString: String?
    var apiKey: String?

    func makeService() -> LibraryServicing {
        let trimmed = baseURLString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return MockLibraryService() }

        guard var components = URLComponents(string: trimmed) else {
            return InvalidBaseURLLibraryService()
        }

        guard let scheme = components.scheme?.lowercased() else {
            return InvalidBaseURLLibraryService()
        }

        guard ["http", "https"].contains(scheme) else {
            return UnsupportedSchemeLibraryService(scheme: scheme)
        }

        guard let host = components.host, !host.isEmpty else {
            return InvalidBaseURLLibraryService()
        }

        if components.path == "/" {
            components.path = ""
        }

        guard let url = components.url else {
            return InvalidBaseURLLibraryService()
        }

        let token = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return KavitaLibraryService(baseURL: url, apiKey: token)
    }
}

// MARK: - Helpers

private struct InvalidBaseURLLibraryService: LibraryServicing {
    func fetchSections() async throws -> [LibrarySection] {
        throw LibraryServiceError.invalidBaseURL
    }

    func fetchSeriesDetail(seriesID: UUID) async throws -> SeriesDetail {
        throw LibraryServiceError.invalidBaseURL
    }

    func pageImageURL(seriesID: UUID, chapterID: UUID, pageNumber: Int) throws -> URL {
        throw LibraryServiceError.invalidBaseURL
    }

    func fetchPageImage(seriesID: UUID, chapterID: UUID, pageNumber: Int) async throws -> Data {
        throw LibraryServiceError.invalidBaseURL
    }
}

private struct UnsupportedSchemeLibraryService: LibraryServicing {
    let scheme: String

    func fetchSections() async throws -> [LibrarySection] {
        throw LibraryServiceError.unsupportedScheme(scheme)
    }

    func fetchSeriesDetail(seriesID: UUID) async throws -> SeriesDetail {
        throw LibraryServiceError.unsupportedScheme(scheme)
    }

    func pageImageURL(seriesID: UUID, chapterID: UUID, pageNumber: Int) throws -> URL {
        throw LibraryServiceError.unsupportedScheme(scheme)
    }

    func fetchPageImage(seriesID: UUID, chapterID: UUID, pageNumber: Int) async throws -> Data {
        throw LibraryServiceError.unsupportedScheme(scheme)
    }
}
