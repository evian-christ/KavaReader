import Foundation
@testable import KavaReader
import XCTest

final class FeaturedPreviewCacheTests: XCTestCase {
    func testRestoresPartialPreviewAfterRecreatingCacheAndSeparatesAccounts() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let calendar = utcCalendar()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let preview = CachedFeaturedPreview(chapterId: 203, pageNumbers: [2, 3], pages: [
            CachedFeaturedPreviewPage(slot: 0, pageNumber: 2, imageData: Data([1, 2, 3])),
        ])
        let cache = FeaturedPreviewCache(directory: directory, calendar: calendar)
        try await cache.save(preview, identity: "account-a", seriesId: 42, requestedAt: now, now: now)

        let restored = FeaturedPreviewCache(directory: directory, calendar: calendar)
        let saved = try await restored.load(identity: "account-a", seriesId: 42, now: now)
        let otherAccount = try await restored.load(identity: "account-b", seriesId: 42, now: now)
        let otherSeries = try await restored.load(identity: "account-a", seriesId: 43, now: now)
        XCTAssertEqual(saved?.chapterId, 203)
        XCTAssertEqual(saved?.pageNumbers, [2, 3])
        XCTAssertEqual(saved?.pages.count, 1)
        XCTAssertEqual(saved?.pages.first?.slot, 0)
        XCTAssertEqual(saved?.pages.first?.imageData, Data([1, 2, 3]))
        XCTAssertNil(otherAccount)
        XCTAssertNil(otherSeries)
    }

    func testDeletesPreviousDayAtMidnightAndRejectsLateDownloads() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let calendar = utcCalendar()
        let midnight = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
        let yesterday = midnight.addingTimeInterval(-1)
        let cache = FeaturedPreviewCache(directory: directory, calendar: calendar)
        let preview = CachedFeaturedPreview(chapterId: 203, pageNumbers: [2, 3], pages: [])
        try await cache.save(preview, identity: "account-a", seriesId: 42,
                             requestedAt: yesterday, now: yesterday)
        let oldFolders = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        XCTAssertEqual(oldFolders.count, 1)

        try await cache.removeExpired(now: midnight)
        XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(oldFolders.first).path))
        try await cache.save(preview, identity: "account-a", seriesId: 42,
                             requestedAt: yesterday, now: midnight)
        let expired = try await cache.load(identity: "account-a", seriesId: 42, now: midnight)
        XCTAssertNil(expired)

        try await cache.save(preview, identity: "account-a", seriesId: 42,
                             requestedAt: midnight, now: midnight)
        let today = try await cache.load(identity: "account-a", seriesId: 42, now: midnight)
        XCTAssertEqual(today?.chapterId, 203)
        let remaining = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        XCTAssertEqual(remaining.count, 1)
    }

    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}
