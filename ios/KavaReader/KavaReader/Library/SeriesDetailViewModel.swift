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

    func load(kavitaSeriesId: Int, force: Bool = false) async {
        guard !isLoading else { return }
        if !force, let _ = detail {
            // We can't directly compare kavitaSeriesId with SeriesDetail since SeriesDetail uses UUID
            // For now, we'll always reload if forced or if no detail is loaded
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            let fetched = try await service.fetchSeriesDetail(kavitaSeriesId: kavitaSeriesId)
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

    func setError(_ message: String) {
        errorMessage = message
    }

    // MARK: Private

    private var service: LibraryServicing
}
