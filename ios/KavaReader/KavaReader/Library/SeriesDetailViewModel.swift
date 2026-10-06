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
    @Published private(set) var isUnavailable = false

    func load(kavitaSeriesId: Int, identity: String, baseURL: URL?, apiKey: String,
              force: Bool = false) async
    {
        let loadID = UUID()
        currentLoadID = loadID
        if currentIdentity != identity || currentSeriesId != kavitaSeriesId {
            detail = nil
            currentIdentity = identity
            currentSeriesId = kavitaSeriesId
        }
        isLoading = true
        errorMessage = nil
        isUnavailable = false

        if !force {
            let cached = await ChapterCatalogStore.shared.load(identity: identity, seriesId: kavitaSeriesId,
                                                               baseURL: baseURL, apiKey: apiKey)
            guard currentLoadID == loadID else { return }
            if let cached {
                detail = cached
                isLoading = false
                return
            }
        }

        let cacheGeneration = await ChapterCatalogStore.shared.currentGeneration()
        guard currentLoadID == loadID else { return }
        let currentService = service
        do {
            let fetched = try await currentService.fetchSeriesDetail(kavitaSeriesId: kavitaSeriesId)
            guard currentLoadID == loadID else { return }
            detail = fetched
            do {
                try await ChapterCatalogStore.shared.save(fetched, identity: identity, seriesId: kavitaSeriesId,
                                                          generation: cacheGeneration)
            } catch {
                if currentLoadID == loadID {
                    errorMessage = AppLocalization.format("챕터 목록은 표시했지만 기기에 저장하지 못했습니다: %@",
                                                          error.localizedDescription)
                }
            }
        } catch {
            guard currentLoadID == loadID else { return }
            if let serviceError = error as? LibraryServiceError {
                switch serviceError {
                case .requestFailed(statusCode: 404), .requestFailed(statusCode: 403):
                    isUnavailable = true
                    errorMessage = "서버에서 이 작품을 찾을 수 없거나 접근할 수 없습니다. 설정의 서버 설정에서 라이브러리를 업데이트해 주세요."
                default:
                    errorMessage = serviceError.errorDescription
                }
            } else {
                errorMessage = error.localizedDescription
            }
            if isUnavailable { detail = nil }
        }

        if currentLoadID == loadID { isLoading = false }
    }

    func loadLocal(id: UUID) async {
        isLoading = true
        errorMessage = nil
        do { detail = try await LocalComicStore.shared.detail(id) }
        catch { detail = nil; errorMessage = error.localizedDescription }
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
    private var currentIdentity: String?
    private var currentSeriesId: Int?
    private var currentLoadID = UUID()
}
