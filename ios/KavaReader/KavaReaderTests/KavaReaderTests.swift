import Foundation
@testable import KavaReader
import Testing

struct KavitaLibraryServiceTests {
    @MainActor
    @Test func unsupportedSchemeThrowsError() async {
        let service = LibraryServiceFactory(baseURLString: "ftp://example.com", apiKey: nil).makeService()

        do {
            _ = try await service.fetchSections()
            Issue.record("FTP 스킴은 예외를 던져야 합니다.")
        } catch let error as LibraryServiceError {
            switch error {
            case let .unsupportedScheme(scheme):
                #expect(scheme == "ftp")
            default:
                Issue.record("예상과 다른 오류: \(error)")
            }
        } catch {
            Issue.record("예상과 다른 오류: \(error)")
        }
    }

    @MainActor
    @Test func invalidURLFallsBackToErrorService() async {
        let service = LibraryServiceFactory(baseURLString: "http://", apiKey: nil).makeService()

        do {
            _ = try await service.fetchSections()
            Issue.record("잘못된 URL은 예외를 던져야 합니다.")
        } catch let error as LibraryServiceError {
            #expect(error == .invalidBaseURL)
        } catch {
            Issue.record("예상과 다른 오류: \(error)")
        }
    }

    @MainActor
    @Test func kavitaServiceBuildsImageURL() async throws {
        guard let baseURL = URL(string: "https://kavita.example.com") else {
            Issue.record("잘못된 테스트 baseURL")
            return
        }
        let service = KavitaLibraryService(baseURL: baseURL, apiKey: "test-key")
        let dummySeries = LibrarySeries(title: "Dummy", author: "", coverColorHexes: [])
        let dummyChapter = SeriesChapter(id: UUID(), title: "Chapter 1", number: 1, pageCount: 20)

        let url = try service.pageImageURL(seriesID: dummySeries.id, chapterID: dummyChapter.id, pageNumber: 1)

        #expect(url.absoluteString.contains("chapterId"))
        #expect(url.absoluteString.contains(dummyChapter.id.uuidString))
    }
}
