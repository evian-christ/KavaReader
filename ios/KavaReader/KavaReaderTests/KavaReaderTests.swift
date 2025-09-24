import Foundation
@testable import KavaReader
import Testing

struct LibraryServiceTests {
    @MainActor
    @Test func mockServiceLoadsSections() async throws {
        let service: LibraryServicing = MockLibraryService(bundle: .main)
        let sections = try await service.fetchSections()

        #expect(!sections.isEmpty)
        #expect(sections.flatMap { $0.items }.count >= 3)
    }

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
    @Test func mockServiceReturnsSeriesDetail() async throws {
        let service: LibraryServicing = MockLibraryService(bundle: .main)
        let sections = try await service.fetchSections()
        guard let series = sections.first?.items.first else {
            Issue.record("예상한 시리즈 데이터를 찾지 못했습니다.")
            return
        }

        let detail = try await service.fetchSeriesDetail(seriesID: series.id)

        #expect(detail.id == series.id)
        #expect(!detail.chapters.isEmpty)
    }

    @MainActor
    @Test func pageImageURLValidation() async throws {
        let service: LibraryServicing = MockLibraryService(bundle: .main)
        let sections = try await service.fetchSections()
        guard
            let series = sections.first?.items.first,
            let chapter = try await service.fetchSeriesDetail(seriesID: series.id).chapters.first
        else {
            Issue.record("시리즈/챕터 데이터를 찾지 못했습니다.")
            return
        }

        let url = try service.pageImageURL(seriesID: series.id, chapterID: chapter.id, pageNumber: 1)

        #expect(url.absoluteString.contains(series.id.uuidString))
    }
}
