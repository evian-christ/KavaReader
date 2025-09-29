import Foundation
import SwiftUI
import Combine

protocol PageImageFetching {
    func fetchImage(from url: URL) async throws -> (Data, URLResponse)
}

struct URLSessionPageImageFetcher: PageImageFetching {
    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchImage(from url: URL) async throws -> (Data, URLResponse) {
        try await session.data(from: url)
    }
}

@MainActor
final class ReaderViewModel: ObservableObject {
    // MARK: Lifecycle

    init(series: LibrarySeries,
         chapter: SeriesChapter,
         service: LibraryServicing,
         imageFetcher: PageImageFetching? = nil)
    {
        self.series = series
        self.chapter = chapter
        self.service = service
        self.imageFetcher = imageFetcher ?? URLSessionPageImageFetcher()
        self.totalPages = chapter.pageCount
    }

    // MARK: Internal

    @Published var currentPage: Int = 1 {
        didSet {
            guard preloadingEnabled else { return }
            preloadNearbyPages()

            // 페이지 변경 시 진행률 저장 (디바운싱 적용)
            scheduleProgressSave()
        }
    }
    @Published private(set) var totalPages: Int = 0
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var retryCount: [Int: Int] = [:] // Page number -> retry count

    let series: LibrarySeries
    let chapter: SeriesChapter

    // MARK: - Image Preloading
    private var preloadedImages: [Int: UIImage] = [:]
    private var preloadTasks: [Int: Task<Void, Never>] = [:]
    private var failedPages: Set<Int> = []
    private let maxCacheSize = 10 // Maximum number of images to keep in memory
    private let maxRetryCount = 3

    func loadChapter() async {
        totalPages = chapter.pageCount
        isLoading = false
        errorMessage = nil

        // 저장된 진행률 불러오기
        await loadSavedProgress()

        // Start preloading nearby pages
        guard preloadingEnabled else { return }
        preloadNearbyPages()
    }

    func pageImageURL(for pageNumber: Int) -> URL? {
        do {
            // Use Kavita chapter ID if available
            if let kavitaChapterId = chapter.kavitaChapterId,
               let kavitaService = service as? KavitaLibraryService {
                return try kavitaService.pageImageURL(
                    kavitaChapterId: kavitaChapterId,
                    pageNumber: pageNumber
                )
            } else {
                // Fallback to generic service method
                return try service.pageImageURL(
                    seriesID: series.id,
                    chapterID: chapter.id,
                    pageNumber: pageNumber
                )
            }
        } catch {
            return nil
        }
    }

    func goToPage(_ page: Int) async {
        guard page >= 1 && page <= totalPages else { return }
        currentPage = page
    }

    func getPreloadedImage(for pageNumber: Int) -> UIImage? {
        return preloadedImages[pageNumber]
    }

    func loadImageForReader(pageNumber: Int) async -> UIImage? {
        if let cached = preloadedImages[pageNumber] {
            return cached
        }

        do {
            let image = try await fetchImageData(pageNumber: pageNumber)
            store(image: image, for: pageNumber)
            return image
        } catch let serviceError as LibraryServiceError {
            await handleImageLoadFailure(pageNumber: pageNumber, error: serviceError, allowRetry: false)
            return nil
        } catch {
            await handleImageLoadFailure(pageNumber: pageNumber, error: mapNetworkError(error), allowRetry: false)
            return nil
        }
    }

    func configurePreloading(enabled: Bool) {
        preloadingEnabled = enabled
    }

    // MARK: Private

    private let service: LibraryServicing
    private let imageFetcher: PageImageFetching
    private var preloadingEnabled = true

    private func store(image: UIImage, for pageNumber: Int) {
        preloadedImages[pageNumber] = image
        preloadTasks.removeValue(forKey: pageNumber)
        retryCount.removeValue(forKey: pageNumber)
        failedPages.remove(pageNumber)
        errorMessage = nil

        if preloadedImages.count > maxCacheSize {
            let oldestPage = preloadedImages.keys.min() ?? pageNumber
            preloadedImages.removeValue(forKey: oldestPage)
        }
    }

    private func fetchImageData(pageNumber: Int) async throws -> UIImage {
        guard let url = pageImageURL(for: pageNumber) else {
            throw LibraryServiceError.invalidResponse
        }

        let (data, response) = try await imageFetcher.fetchImage(from: url)

        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            throw LibraryServiceError.requestFailed(statusCode: httpResponse.statusCode)
        }

        guard let image = UIImage(data: data) else {
            throw LibraryServiceError.decodingFailed
        }

        return image
    }

    private func preloadNearbyPages() {
        guard preloadingEnabled else { return }
        let preloadRange = max(1, currentPage - 2)...min(totalPages, currentPage + 2)

        // Cancel tasks for pages outside the range
        for (page, task) in preloadTasks {
            if !preloadRange.contains(page) {
                task.cancel()
                preloadTasks.removeValue(forKey: page)
            }
        }

        // Remove old images to manage memory
        let imagesToRemove = preloadedImages.keys.filter { !preloadRange.contains($0) }
        for page in imagesToRemove {
            preloadedImages.removeValue(forKey: page)
        }

        // Start preloading for pages in range
        for page in preloadRange {
            preloadImage(for: page)
        }
    }

    private func preloadImage(for pageNumber: Int) {
        guard preloadingEnabled else { return }
        // Don't preload if already cached or task is running
        guard preloadedImages[pageNumber] == nil && preloadTasks[pageNumber] == nil else {
            return
        }

        let task = Task {
            await loadImageWithRetry(pageNumber: pageNumber)
        }

        preloadTasks[pageNumber] = task
    }

    private func loadImageWithRetry(pageNumber: Int) async {
        do {
            let image = try await fetchImageData(pageNumber: pageNumber)
            guard !Task.isCancelled else { return }
            store(image: image, for: pageNumber)
        } catch let serviceError as LibraryServiceError {
            await handleImageLoadFailure(pageNumber: pageNumber, error: serviceError)
        } catch {
            await handleImageLoadFailure(pageNumber: pageNumber, error: mapNetworkError(error))
        }
    }

    private func handleImageLoadFailure(pageNumber: Int, error: LibraryServiceError, allowRetry: Bool = true) async {
        preloadTasks.removeValue(forKey: pageNumber)
        let currentRetryCount = retryCount[pageNumber] ?? 0

        if allowRetry && currentRetryCount < maxRetryCount && error.isRetryable {
            retryCount[pageNumber] = currentRetryCount + 1
            let retryTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(currentRetryCount)) * 1_000_000_000))
                guard !Task.isCancelled else { return }
                await self?.loadImageWithRetry(pageNumber: pageNumber)
            }
            preloadTasks[pageNumber] = retryTask
        } else {
            failedPages.insert(pageNumber)
            if pageNumber == currentPage {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func mapNetworkError(_ error: Error) -> LibraryServiceError {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return .networkFailure(underlying: error)
            case .timedOut:
                return .timeout
            case .cannotConnectToHost, .cannotFindHost:
                return .serverUnavailable
            default:
                return .networkFailure(underlying: error)
            }
        }
        return .networkFailure(underlying: error)
    }

    func retryFailedPage(_ pageNumber: Int) async {
        guard failedPages.contains(pageNumber) else { return }

        await MainActor.run { [weak self] in
            guard let self = self else { return }
            failedPages.remove(pageNumber)
            retryCount.removeValue(forKey: pageNumber)
            errorMessage = nil
        }

        await loadImageWithRetry(pageNumber: pageNumber)
    }

    func isPageFailed(_ pageNumber: Int) -> Bool {
        return failedPages.contains(pageNumber)
    }

    func clearError() {
        errorMessage = nil
    }

    // MARK: - Reading Progress

    private var progressSaveTask: Task<Void, Never>?

    /// 저장된 읽기 진행률을 불러와서 currentPage 설정
    private func loadSavedProgress() async {

        guard let kavitaService = service as? KavitaLibraryService,
              let kavitaChapterId = chapter.kavitaChapterId else {
            // 로컬 저장 진행률 확인 (Kavita API 사용 불가능한 경우)
            if let localProgress = getLocalProgress() {
                currentPage = localProgress
            }
            return
        }

        do {
            if let progress = try await kavitaService.getProgress(chapterId: kavitaChapterId) {
                let savedPage = max(1, min(totalPages, progress.pageNum))
                currentPage = savedPage
            } else {
                if let localProgress = getLocalProgress() {
                    currentPage = localProgress
                }
            }
        } catch {
            // Kavita에서 진행률을 가져올 수 없는 경우 로컬 저장소 확인
            if let localProgress = getLocalProgress() {
                currentPage = localProgress
            }
        }
    }

    /// 진행률 저장을 디바운싱하여 스케줄링
    private func scheduleProgressSave() {
        // 이전 태스크 취소
        progressSaveTask?.cancel()

        // 1초 후에 진행률 저장 (디바운싱)
        progressSaveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1초 대기
            guard !Task.isCancelled else { return }
            await saveCurrentProgress()
        }
    }

    /// 현재 페이지를 Kavita 서버와 로컬에 저장
    private func saveCurrentProgress() async {
        guard let kavitaService = service as? KavitaLibraryService,
              let kavitaSeriesId = series.kavitaSeriesId,
              let kavitaVolumeId = chapter.kavitaVolumeId,
              let kavitaChapterId = chapter.kavitaChapterId else {
            // Kavita API 사용 불가능한 경우 로컬에만 저장
            saveLocalProgress(page: currentPage)
            return
        }

        do {
            try await kavitaService.saveProgress(
                seriesId: kavitaSeriesId,
                volumeId: kavitaVolumeId,
                chapterId: kavitaChapterId,
                pageNumber: currentPage
            )

            // Kavita 저장 성공 시 로컬에도 백업 저장
            saveLocalProgress(page: currentPage)

        } catch {
            // Kavita 저장 실패 시 로컬에만 저장
            saveLocalProgress(page: currentPage)
        }
    }

    /// 수동으로 진행률 저장 (예: 앱이 백그라운드로 갈 때)
    func saveProgressNow() async {
        progressSaveTask?.cancel()
        await saveCurrentProgress()
    }

    // MARK: - Local Progress Storage (Fallback)

    private func getLocalProgress() -> Int? {
        let key = "chapter_progress_\(chapter.id.uuidString)"
        let savedPage = UserDefaults.standard.integer(forKey: key)
        return savedPage > 0 ? savedPage : nil
    }

    private func saveLocalProgress(page: Int) {
        let key = "chapter_progress_\(chapter.id.uuidString)"
        UserDefaults.standard.set(page, forKey: key)
    }
}
