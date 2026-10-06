import Combine
import Foundation
import SwiftUI

protocol PageImageFetching {
    func fetchImage(from url: URL) async throws -> (Data, URLResponse)
}

struct URLSessionPageImageFetcher: PageImageFetching {
    // MARK: Lifecycle

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: Internal

    let session: URLSession

    func fetchImage(from url: URL) async throws -> (Data, URLResponse) {
        try await session.data(from: url)
    }
}

@MainActor
final class ReaderProgressSaveQueue {
    static let shared = ReaderProgressSaveQueue()

    private var pending: [String: (id: UUID, task: Task<Void, Never>)] = [:]

    func enqueue(identity: String, seriesId: Int, operation: @escaping @MainActor () async -> Void) {
        let key = "\(identity)|\(seriesId)"
        let previous = pending[key]?.task
        let id = UUID()
        let task = Task { @MainActor in
            await previous?.value
            await operation()
            if pending[key]?.id == id {
                pending.removeValue(forKey: key)
            }
        }
        pending[key] = (id, task)
    }

    func wait(identity: String, seriesId: Int) async {
        let key = "\(identity)|\(seriesId)"
        while let task = pending[key]?.task {
            await task.value
        }
    }

    func wait(identity: String) async {
        while let task = pending.first(where: { $0.key.hasPrefix(identity + "|") })?.value.task {
            await task.value
        }
    }
}

@MainActor
final class ReaderViewModel: ObservableObject {
    // MARK: Lifecycle

    init(series: LibrarySeries,
         chapter: SeriesChapter,
         service: LibraryServicing,
         imageFetcher: PageImageFetching? = nil,
         initialPage: Int? = nil,
         preparedImage: UIImage? = nil,
         readingIdentity: String? = nil,
         isContinuePointVerified: Bool = true)
    {
        self.series = series
        self.chapter = chapter
        self.service = service
        self.imageFetcher = imageFetcher ?? URLSessionPageImageFetcher()
        self.initialPage = initialPage
        self.readingIdentity = readingIdentity
        self.isContinuePointVerified = isContinuePointVerified
        totalPages = chapter.pageCount
        currentPage = max(1, min(chapter.pageCount, initialPage ?? 1))
        if let preparedImage {
            preloadedImages[currentPage] = preparedImage
        }
    }

    // MARK: Internal

    @Published private(set) var totalPages: Int = 0
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var retryCount: [Int: Int] = [:] // Page number -> retry count

    let series: LibrarySeries
    let chapter: SeriesChapter

    @Published var currentPage: Int = 1 {
        didSet {
            guard isReaderActive else { return }
            if preloadingEnabled { preloadNearbyPages() }

            if !isRestoringProgress, hasDisplayedContent, oldValue != currentPage {
                recordLocalProgress(page: currentPage)
                postReadingActivity()
                scheduleProgressSave()
            }
        }
    }

    func loadChapter() async {
        totalPages = chapter.pageCount
        isLoading = false
        errorMessage = nil
        isChapterProgressVerified = false
        isRestoringProgress = true

        if let initialPage {
            currentPage = max(1, min(totalPages, initialPage))
            isChapterProgressVerified = isContinuePointVerified
        } else {
            // 명시된 진입 위치가 없을 때만 챕터 진행률을 조회합니다.
            await loadSavedProgress()
        }

        guard !Task.isCancelled else {
            isRestoringProgress = false
            return
        }
        isRestoringProgress = false
        if hasDisplayedContent { beginReadingVisibleContent() }

        // Start preloading nearby pages
        guard preloadingEnabled else { return }
        preloadNearbyPages()
    }

    func pageImageURL(for pageNumber: Int) -> URL? {
        do {
            // Use Kavita chapter ID if available
            if let kavitaChapterId = chapter.kavitaChapterId,
               let kavitaService = service as? KavitaLibraryService
            {
                return try kavitaService.pageImageURL(kavitaChapterId: kavitaChapterId,
                                                      pageNumber: pageNumber)
            } else {
                // Fallback to generic service method
                return try service.pageImageURL(seriesID: series.id,
                                                chapterID: chapter.id,
                                                pageNumber: pageNumber)
            }
        } catch {
            return nil
        }
    }

    func goToPage(_ page: Int) async {
        guard isReaderActive, page >= 1, page <= totalPages else { return }
        currentPage = page
    }

    func updateCurrentPage(_ page: Int) async {
        guard isReaderActive, page >= 1, page <= totalPages, page != currentPage else { return }
        currentPage = page
    }

    func getPreloadedImage(for pageNumber: Int) -> UIImage? {
        return preloadedImages[pageNumber]
    }

    func pagePreview(for pageNumber: Int) async -> UIImage? {
        if series.isLocal { return await loadImageForReader(pageNumber: pageNumber) }
        guard isReaderActive, !Task.isCancelled, totalPages > 0,
              (1 ... totalPages).contains(pageNumber),
              let url = pageImageURL(for: pageNumber) else { return nil }
        if let cached = await PagePreviewCache.shared.cachedImage(for: url) { return cached }
        // Reuse a reader download already in flight rather than downloading it again.
        if let task = preloadTasks[pageNumber] { await task.value }
        guard isReaderActive, !Task.isCancelled else { return nil }
        return await PagePreviewCache.shared.image(for: url, sourceImage: preloadedImages[pageNumber])
    }

    func loadImageForReader(pageNumber: Int) async -> UIImage? {
        if let cached = preloadedImages[pageNumber] {
            return cached
        }

        do {
            let image = try await fetchImageData(pageNumber: pageNumber)
            guard !Task.isCancelled, isReaderActive else { return nil }
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

    func didDisplayPage(_ pageNumber: Int) {
        if pageNumber == currentPage { beginReadingVisibleContent() }
    }

    func configurePreloading(enabled: Bool) {
        preloadingEnabled = enabled
    }

    func configurePreloadingLayout(displayMode: HorizontalDisplayMode, firstPageAlone: Bool) {
        guard preloadingDisplayMode != displayMode || preloadingFirstPageAlone != firstPageAlone else { return }
        preloadingDisplayMode = displayMode
        preloadingFirstPageAlone = firstPageAlone
        guard isReaderActive else { return }
        preloadNearbyPages()
    }

    func configureLibraryId(_ libraryId: Int?) {
        resolvedLibraryId = libraryId.flatMap { $0 > 0 ? $0 : nil }
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

    /// 수동으로 진행률 저장 (예: 앱이 백그라운드로 갈 때)
    func saveProgressNow() async {
        enqueueProgressSaveNow()
        if series.isLocal {
            await ReaderProgressSaveQueue.shared.wait(identity: "local:\(chapter.id)", seriesId: 0)
        }
        if let readingIdentity, let seriesId = series.kavitaSeriesId {
            await ReaderProgressSaveQueue.shared.wait(identity: readingIdentity, seriesId: seriesId)
        }
    }

    func enqueueProgressSaveNow() {
        guard !isRestoringProgress, hasDisplayedContent else { return }
        progressSaveTask?.cancel()
        enqueueCurrentProgress()
    }

    func deactivate() {
        isReaderActive = false
        progressSaveTask?.cancel()
    }

    // MARK: Private

    private var hasDisplayedContent = false
    private var didBeginReading = false

    private func beginReadingVisibleContent() {
        guard isReaderActive, totalPages > 0 else { return }
        hasDisplayedContent = true
        guard !isRestoringProgress, !didBeginReading else { return }
        didBeginReading = true
        recordLocalProgress(page: currentPage)
        postReadingActivity()
        enqueueProgressSaveNow()
    }

    private func postReadingActivity() {
        let readAt = Date()
        let item = ContinueReadingItem(series: series, lastReadChapter: chapter,
                                       progress: ProgressDto(volumeId: chapter.kavitaVolumeId ?? 0,
                                                             chapterId: chapter.kavitaChapterId ?? 0,
                                                             pageNum: currentPage, seriesId: series.kavitaSeriesId ?? 0,
                                                             libraryId: resolvedLibraryId ?? 0,
                                                             bookScrollId: nil, lastModifiedUtc: ""))
        NotificationCenter.default.post(name: .readerDidRead, object: readingIdentity,
                                        userInfo: ["item": item, "readAt": readAt])
    }

    // MARK: - Image Preloading

    private var preloadedImages: [Int: UIImage] = [:]
    private var preloadTasks: [Int: Task<Void, Never>] = [:]
    private var failedPages: Set<Int> = []
    private let maxCacheSize = 10 // Maximum number of images to keep in memory
    private let maxRetryCount = 3

    private let service: LibraryServicing
    private let imageFetcher: PageImageFetching
    private let initialPage: Int?
    private let readingIdentity: String?
    private let isContinuePointVerified: Bool
    private var preloadingEnabled = true
    private var preloadingDisplayMode: HorizontalDisplayMode = .singlePage
    private var preloadingFirstPageAlone = false
    private var isReaderActive = true
    private var isRestoringProgress = false
    private var isChapterProgressVerified = false
    private var currentRevision: UUID?
    private var resolvedLibraryId: Int?
    private var queuedRevisions: Set<UUID> = []
    private var confirmedRevision: UUID?

    // MARK: - Reading Progress

    private var progressSaveTask: Task<Void, Never>?

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
        if series.isLocal {
            let data = try await LocalComicStore.shared.pageData(chapterID: chapter.id, page: pageNumber)
            guard let image = UIImage(data: data) else { throw LibraryServiceError.decodingFailed }
            return image
        }
        guard let url = pageImageURL(for: pageNumber) else {
            throw LibraryServiceError.invalidResponse
        }

        let (data, response) = try await imageFetcher.fetchImage(from: url)

        if let httpResponse = response as? HTTPURLResponse,
           !(200 ..< 300).contains(httpResponse.statusCode)
        {
            throw LibraryServiceError.requestFailed(statusCode: httpResponse.statusCode)
        }

        guard let image = UIImage(data: data) else {
            throw LibraryServiceError.decodingFailed
        }

        return image
    }

    private func preloadNearbyPages() {
        guard preloadingEnabled, totalPages > 0 else { return }
        let pageCount = preloadingDisplayMode.pageCount
        let showsFirstPageAlone = preloadingDisplayMode == .doublePage && preloadingFirstPageAlone
        let startPage = showsFirstPageAlone ? 2 : 1
        let firstVisiblePage = showsFirstPageAlone && currentPage == 1
            ? 1
            : (max(currentPage, startPage) - startPage) / pageCount * pageCount + startPage
        let lastVisiblePage = showsFirstPageAlone && firstVisiblePage == 1
            ? 1
            : min(totalPages, firstVisiblePage + pageCount - 1)
        let preloadRange = max(1, firstVisiblePage - 2) ... min(totalPages, lastVisiblePage + 2)

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
        guard preloadedImages[pageNumber] == nil, preloadTasks[pageNumber] == nil else {
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

        if allowRetry, currentRetryCount < maxRetryCount, error.isRetryable {
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
                switch error {
                case .requestFailed(statusCode: 404), .requestFailed(statusCode: 403):
                    errorMessage = "이 작품이나 화를 서버에서 찾을 수 없거나 접근할 수 없습니다. 설정의 서버 설정에서 라이브러리를 업데이트해 주세요."
                default:
                    errorMessage = error.localizedDescription
                }
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

    /// 저장된 읽기 진행률을 불러와서 currentPage 설정
    private func loadSavedProgress() async {
        if series.isLocal {
            currentPage = max(1, min(totalPages, chapter.lastReadPage ?? 1))
            return
        }
        guard let kavitaService = service as? KavitaLibraryService,
              let kavitaChapterId = chapter.kavitaChapterId
        else {
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
            }
            isChapterProgressVerified = true
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
            enqueueCurrentProgress()
        }
    }

    private func enqueueCurrentProgress() {
        if series.isLocal {
            let page = currentPage
            ReaderProgressSaveQueue.shared.enqueue(identity: "local:\(chapter.id)", seriesId: 0) { [self] in
                do { try await LocalComicStore.shared.saveProgress(seriesID: series.id, chapterID: chapter.id, page: page) }
                catch { errorMessage = error.localizedDescription }
            }
            return
        }
        guard let readingIdentity, let seriesId = series.kavitaSeriesId,
              let revision = currentRevision,
              !queuedRevisions.contains(revision), confirmedRevision != revision
        else { return }
        queuedRevisions.insert(revision)
        let page = currentPage
        ReaderProgressSaveQueue.shared.enqueue(identity: readingIdentity, seriesId: seriesId) { [self] in
            let saved = await persistProgress(page: page, revision: revision)
            queuedRevisions.remove(revision)
            if saved { confirmedRevision = revision }
        }
    }

    private func persistProgress(page: Int, revision: UUID) async -> Bool {
        guard currentRevision == revision, isContinuePointVerified, isChapterProgressVerified else { return false }
        guard let kavitaService = service as? KavitaLibraryService,
              let kavitaSeriesId = series.kavitaSeriesId,
              let kavitaVolumeId = chapter.kavitaVolumeId,
              let kavitaChapterId = chapter.kavitaChapterId
        else { return false }

        do {
            let libraryId: Int
            if let resolvedLibraryId {
                libraryId = resolvedLibraryId
            } else {
                libraryId = try await kavitaService.getLibraryId(seriesId: kavitaSeriesId)
                resolvedLibraryId = libraryId
            }
            try await kavitaService.saveProgress(seriesId: kavitaSeriesId,
                                                 libraryId: libraryId,
                                                 volumeId: kavitaVolumeId,
                                                 chapterId: kavitaChapterId,
                                                 pageNumber: page)

            if let readingIdentity {
                ReadingStatusStore.saveConfirmedProgress(chapterId: kavitaChapterId,
                                                         volumeId: kavitaVolumeId,
                                                         page: page,
                                                         identity: readingIdentity,
                                                         seriesId: kavitaSeriesId,
                                                         revision: revision)
            }
            return true
        } catch {
            return false
        }
    }

    // MARK: - Local Progress Storage (Fallback)

    private func getLocalProgress() -> Int? {
        guard totalPages > 0 else { return nil }
        let key = "chapter_progress_\(chapter.id.uuidString)"
        let savedPage = UserDefaults.standard.integer(forKey: key)
        if savedPage > 0 { return max(1, min(totalPages, savedPage)) }
        if let readingIdentity, let seriesId = series.kavitaSeriesId,
           let chapterId = chapter.kavitaChapterId,
           let status = ReadingStatusStore.load(identity: readingIdentity, seriesId: seriesId),
           status.chapterId == chapterId, status.hasProgress
        {
            return max(1, min(totalPages, status.page))
        }
        return nil
    }

    private func recordLocalProgress(page: Int) {
        guard !series.isLocal else { return }
        let key = "chapter_progress_\(chapter.id.uuidString)"
        UserDefaults.standard.set(page, forKey: key)
        if let readingIdentity, let seriesId = series.kavitaSeriesId,
           let chapterId = chapter.kavitaChapterId
        {
            ReadingPauseStore.setPaused(false, identity: readingIdentity, seriesId: seriesId)
            currentRevision = ReadingStatusStore.saveLocalProgress(chapterId: chapterId,
                                                                   volumeId: chapter.kavitaVolumeId,
                                                                   page: page,
                                                                   identity: readingIdentity,
                                                                   seriesId: seriesId)
        }
    }
}
