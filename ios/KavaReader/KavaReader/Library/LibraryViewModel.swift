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
    @Published private(set) var continueReadingItems: [ContinueReadingItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

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
            // 섹션과 이어서 읽기 데이터를 병렬로 로드
            async let sectionsTask = service.fetchSections()
            async let continueReadingTask = service.fetchContinueReadingItems()

            let loaded = try await sectionsTask
            let continueItems = await continueReadingTask

            sections = loaded
            continueReadingItems = continueItems
            cachedSections = loaded // Cache the results

        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            sections = []
            continueReadingItems = []
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
    }

    // MARK: Private

    private var cachedSections: [LibrarySection]?
    private var lastServiceKey: String?

    private var service: LibraryServicing
}
