import Combine
import Foundation

@MainActor
final class SeriesDetailViewModel: ObservableObject {
    // MARK: Lifecycle

    init(service: LibraryServicing) {
        self.service = service
    }

    // MARK: Internal

    @Published private(set) var detail: SeriesDetail?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    func load(seriesID: UUID, force: Bool = false) async {
        guard !isLoading else { return }
        if !force, let loaded = detail, loaded.id == seriesID {
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            let fetched = try await service.fetchSeriesDetail(seriesID: seriesID)
            detail = fetched
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            detail = nil
        }

        isLoading = false
    }

    func updateService(_ newService: LibraryServicing) {
        service = newService
    }

    // MARK: Private

    private var service: LibraryServicing
}
