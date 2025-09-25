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

    @Published var currentPage: Int = 1
    @Published private(set) var totalPages: Int = 0
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    let series: LibrarySeries
    let chapter: SeriesChapter

    func loadChapter() async {
        totalPages = chapter.pageCount
        isLoading = false
        errorMessage = nil
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

    // MARK: Private

    private let service: LibraryServicing
}