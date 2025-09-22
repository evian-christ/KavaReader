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

        if components.path.isEmpty {
            components.path = ""
        }

        if let last = components.path.last, last == "/" {
            components.path.removeLast()
        }

        guard let url = components.url else {
            return InvalidBaseURLLibraryService()
        }

        let token = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return NetworkLibraryService(baseURL: url, apiKey: token)
    }
}

// MARK: - Helpers

private struct InvalidBaseURLLibraryService: LibraryServicing {
    func fetchSections() async throws -> [LibrarySection] {
        throw LibraryServiceError.invalidBaseURL
    }
}

private struct UnsupportedSchemeLibraryService: LibraryServicing {
    let scheme: String

    func fetchSections() async throws -> [LibrarySection] {
        throw LibraryServiceError.unsupportedScheme(scheme)
    }
}
