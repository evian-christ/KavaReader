import Foundation
@testable import KavaReader
import Testing

struct LibraryServiceTests {
    @MainActor
    @Test func mockServiceLoadsSections() async throws {
        let service = MockLibraryService(bundle: .main)
        let sections = try await service.fetchSections()

        #expect(!sections.isEmpty)
        #expect(sections.flatMap { $0.items }.count >= 3)
    }
}
