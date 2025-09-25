import Combine
import Foundation

@MainActor
final class LibraryViewModel: ObservableObject {
    // MARK: Lifecycle

    init(service: LibraryServicing) {
        self.service = service
    }

    // MARK: Internal

    @Published private(set) var sections: [LibrarySection] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private var cachedSections: [LibrarySection]?
    private var lastServiceKey: String?

    func load(force: Bool = false) async {
        guard !isLoading else { return }

        // If we have cached data and not forcing refresh, use cache
        if !force, let cached = cachedSections, !cached.isEmpty {
            sections = cached
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            let loaded = try await service.fetchSections()
            sections = loaded
            cachedSections = loaded // Cache the results
            #if DEBUG
            print("📦 Library data cached: \(loaded.count) sections")
            #endif
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            sections = []
            cachedSections = nil
        }

        isLoading = false
    }

    func filteredSections(query: String) -> [LibrarySection] {
        guard !query.isEmpty else { return sections }
        return sections.compactMap { section -> LibrarySection? in
            let matches = section.items.filter { item in
                item.title.localizedCaseInsensitiveContains(query) ||
                    item.author.localizedCaseInsensitiveContains(query)
            }
            return matches.isEmpty ? nil : LibrarySection(id: section.id, title: section.title, items: matches)
        }
    }

    func updateService(_ newService: LibraryServicing) {
        service = newService
        // Clear cache when service changes (e.g., different server/API key)
        cachedSections = nil
        #if DEBUG
        print("🔄 Service updated, cache cleared")
        #endif
    }

    // MARK: Private

    private var service: LibraryServicing
}
