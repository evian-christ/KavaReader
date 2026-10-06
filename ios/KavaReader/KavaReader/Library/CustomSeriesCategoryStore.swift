import CryptoKit
import Foundation

/// User additions stored on this device, separate from source metadata and lookup caches.
nonisolated enum CustomSeriesCategoryStore {
    static let didChange = Notification.Name("customSeriesCategoriesDidChange")

    static func applying(to metadata: LibraryPlusMetadata, key: String,
                         defaults: UserDefaults = .standard) -> LibraryPlusMetadata
    {
        let additions = load(key: key, defaults: defaults)
        return LibraryPlusMetadata(summary: metadata.summary, genres: metadata.genres + additions.genres,
                                   tags: metadata.tags + additions.tags)
    }

    static func key(identity: String, seriesID: String, isLocal: Bool) -> String {
        let scope = isLocal ? "local" : "server|\(identity)"
        let hash = SHA256.hash(data: Data(scope.utf8)).map { String(format: "%02x", $0) }.joined()
        // Preserve the existing key so development additions remain available.
        return "development_series_categories_\(hash)_\(seriesID)"
    }

    static func load(key: String, defaults: UserDefaults = .standard) -> LibraryPlusMetadata {
        guard let data = defaults.data(forKey: key),
              let metadata = try? JSONDecoder().decode(LibraryPlusMetadata.self, from: data)
        else { return LibraryPlusMetadata(summary: "", genres: [], tags: []) }
        return normalized(metadata)
    }

    static func save(_ metadata: LibraryPlusMetadata, key: String,
                     defaults: UserDefaults = .standard) throws
    {
        let data = try JSONEncoder().encode(normalized(metadata))
        defaults.set(data, forKey: key)
    }

    private static func normalized(_ metadata: LibraryPlusMetadata) -> LibraryPlusMetadata {
        LibraryPlusMetadata(summary: metadata.summary,
                            genres: metadata.genres.map { MetadataCategoryRegistry.storageValue($0, kind: .genre) },
                            tags: metadata.tags.map { MetadataCategoryRegistry.storageValue($0, kind: .tag) })
    }

    static func reset(key: String, defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }
}
