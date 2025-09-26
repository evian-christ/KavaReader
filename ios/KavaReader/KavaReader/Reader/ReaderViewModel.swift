import Foundation
import SwiftUI
import Combine

@MainActor
final class ReaderViewModel: ObservableObject {
    // MARK: Lifecycle

    init(series: LibrarySeries, chapter: SeriesChapter, service: LibraryServicing) {
        self.series = series
        self.chapter = chapter
        self.service = service
        self.totalPages = chapter.pageCount
    }

    // MARK: Internal

    @Published var currentPage: Int = 1 {
        didSet {
            preloadNearbyPages()
        }
    }
    @Published private(set) var totalPages: Int = 0
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    let series: LibrarySeries
    let chapter: SeriesChapter

    // MARK: - Image Preloading
    private var preloadedImages: [Int: UIImage] = [:]
    private var preloadTasks: [Int: Task<Void, Never>] = [:]
    private let maxCacheSize = 10 // Maximum number of images to keep in memory

    func loadChapter() async {
        totalPages = chapter.pageCount
        isLoading = false
        errorMessage = nil

        // Start preloading nearby pages
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

    // MARK: Private

    private let service: LibraryServicing

    private func preloadNearbyPages() {
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
        // Don't preload if already cached or task is running
        guard preloadedImages[pageNumber] == nil && preloadTasks[pageNumber] == nil else {
            return
        }

        let task = Task {
            do {
                guard let url = pageImageURL(for: pageNumber) else { return }

                let (data, _) = try await URLSession.shared.data(from: url)
                guard let image = UIImage(data: data) else { return }

                // Check if task was cancelled
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    preloadedImages[pageNumber] = image
                    preloadTasks.removeValue(forKey: pageNumber)

                    // Maintain cache size limit
                    if preloadedImages.count > maxCacheSize {
                        let oldestPage = preloadedImages.keys.min() ?? pageNumber
                        preloadedImages.removeValue(forKey: oldestPage)
                    }
                }
            } catch {
                await MainActor.run {
                    preloadTasks.removeValue(forKey: pageNumber)
                }
            }
        }

        preloadTasks[pageNumber] = task
    }
}