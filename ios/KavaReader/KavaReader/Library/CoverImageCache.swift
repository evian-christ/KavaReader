import CryptoKit
import Foundation
import UIKit

enum CoverImageCacheError: Error {
    case invalidResponse
    case invalidImage
}

/// Stores only decoded, valid cover downloads in the app's purgeable Caches directory.
actor CoverImageCache {
    static let shared = CoverImageCache()

    init(directory: URL? = nil, session: URLSession = .shared) {
        self.directory = directory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CoverImages", isDirectory: true)
        self.session = session
    }

    func imageData(for request: URLRequest, identity: String, enabled: Bool) async throws -> Data {
        let fileURL = directory.appendingPathComponent(fileName(for: identity))
        if enabled, let cached = try? Data(contentsOf: fileURL) {
            if UIImage(data: cached) != nil { return cached }
            try? FileManager.default.removeItem(at: fileURL)
        }

        let currentGeneration = generation
        var networkRequest = request
        networkRequest.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await session.data(for: networkRequest)
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            throw CoverImageCacheError.invalidResponse
        }
        guard UIImage(data: data) != nil else { throw CoverImageCacheError.invalidImage }

        if enabled, !Task.isCancelled, currentGeneration == generation,
           UserDefaults.standard.object(forKey: "cover_cache_enabled") as? Bool ?? true
        {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? data.write(to: fileURL, options: .atomic)
        }
        return data
    }

    func sizeInBytes() -> Int64 {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        return files.reduce(0) { total, file in
            let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return total + Int64(size)
        }
    }

    func clear() throws {
        generation += 1
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }

    private let directory: URL
    private let session: URLSession
    private var generation = 0

    private func fileName(for identity: String) -> String {
        let digest = SHA256.hash(data: Data(identity.utf8))
        return digest.map { String(format: "%02x", $0) }.joined() + ".img"
    }
}
