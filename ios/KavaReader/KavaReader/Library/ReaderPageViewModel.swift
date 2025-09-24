import Combine
import Foundation
import UIKit

@MainActor
final class ReaderPageViewModel: ObservableObject {
    // MARK: Nested Types

    enum Phase {
        case idle
        case loading
        case success(UIImage)
        case failure(String)
    }

    // MARK: Lifecycle

    init(seriesID: UUID,
         chapterID: UUID,
         pageNumber: Int,
         serviceFactory: LibraryServiceFactory)
    {
        self.seriesID = seriesID
        self.chapterID = chapterID
        self.pageNumber = pageNumber
        self.serviceFactory = serviceFactory
    }

    // MARK: Internal

    @Published private(set) var phase: Phase = .idle

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        phase = .loading

        let service = serviceFactory.makeService()

        do {
            let data = try await service.fetchPageImage(seriesID: seriesID,
                                                        chapterID: chapterID,
                                                        pageNumber: pageNumber)
            if let image = UIImage(data: data) {
                phase = .success(image)
            } else {
                phase = .failure("이미지를 불러올 수 없습니다.")
            }
        } catch {
            phase = .failure((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }

        isLoading = false
    }

    // MARK: Private

    private let seriesID: UUID
    private let chapterID: UUID
    private let pageNumber: Int
    private let serviceFactory: LibraryServiceFactory
    private var isLoading = false
}
