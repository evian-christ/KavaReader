import CryptoKit
import Foundation

struct CachedFeaturedPreviewPage: Codable, Sendable {
    let slot: Int
    let pageNumber: Int
    let imageData: Data
}

struct CachedFeaturedPreview: Codable, Sendable {
    let chapterId: Int
    let pageNumbers: [Int]
    var pages: [CachedFeaturedPreviewPage]
}

/// Daily preview thumbnails, separate from cover images and reading progress.
actor FeaturedPreviewCache {
    static let shared = FeaturedPreviewCache()

    init(directory: URL? = nil, calendar: Calendar = .current) {
        self.directory = directory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("KavaReader/FeaturedPreviews", isDirectory: true)
        self.calendar = calendar
    }

    func load(identity: String, seriesId: Int, now: Date = Date()) throws -> CachedFeaturedPreview? {
        try removeExpired(now: now)
        let file = fileURL(identity: identity, seriesId: seriesId, now: now)
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(CachedFeaturedPreview.self, from: data)
    }

    func save(_ preview: CachedFeaturedPreview, identity: String, seriesId: Int,
              requestedAt: Date, now: Date = Date()) throws {
        try removeExpired(now: now)
        // A download crossing midnight must not recreate yesterday's cache.
        guard calendar.isDate(requestedAt, inSameDayAs: now) else { return }
        let file = fileURL(identity: identity, seriesId: seriesId, now: now)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try JSONEncoder().encode(preview).write(to: file, options: .atomic)
    }

    func removeExpired(now: Date = Date()) throws {
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        let currentDay = dayName(now)
        let folders = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        for folder in folders where folder.lastPathComponent.hasPrefix("day-") && folder.lastPathComponent != currentDay {
            try FileManager.default.removeItem(at: folder)
        }
    }

    private let directory: URL
    private let calendar: Calendar

    private func dayName(_ date: Date) -> String {
        "day-\(Int(calendar.startOfDay(for: date).timeIntervalSince1970))"
    }

    private func fileURL(identity: String, seriesId: Int, now: Date) -> URL {
        let digest = SHA256.hash(data: Data("\(identity)|\(seriesId)".utf8))
            .map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(dayName(now), isDirectory: true)
            .appendingPathComponent(digest + ".json")
    }
}
