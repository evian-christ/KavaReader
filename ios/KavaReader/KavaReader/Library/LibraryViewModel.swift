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

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        do {
            let loaded = try await service.fetchSections()
            sections = loaded
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            sections = []
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
    }

    // MARK: Private

    private var service: LibraryServicing
}
