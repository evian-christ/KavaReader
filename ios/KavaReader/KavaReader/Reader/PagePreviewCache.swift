import CryptoKit
import ImageIO
import UIKit

/// Small page previews are independent of the reader's full-resolution image cache.
actor PagePreviewCache {
    static let shared = PagePreviewCache()

    init(directory: URL? = nil, session: URLSession = .shared) {
        self.directory = directory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("KavaReader/PagePreviews", isDirectory: true)
        self.session = session
        memory.totalCostLimit = 12 * 1024 * 1024
    }

    func cachedImage(for url: URL) -> UIImage? {
        let key = cacheKey(for: url)
        if let image = memory.object(forKey: key as NSString) { return image }
        let file = directory.appendingPathComponent(key + ".jpg")
        guard let data = try? Data(contentsOf: file), let image = downsample(data) else { return nil }
        remember(image, key: key)
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: file.path)
        return image
    }

    func image(for url: URL, sourceImage: UIImage?) async -> UIImage? {
        guard !Task.isCancelled else { return nil }
        if let cached = cachedImage(for: url) { return cached }

        let image: UIImage?
        if let sourceImage {
            let size = sourceImage.size
            guard size.width > 0, size.height > 0 else { return nil }
            let scale = min(1, 360 / max(size.width, size.height))
            let outputSize = CGSize(width: size.width * scale, height: size.height * scale)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            image = UIGraphicsImageRenderer(size: outputSize, format: format).image { _ in
                sourceImage.draw(in: CGRect(origin: .zero, size: outputSize))
            }
        } else {
            do {
                let (data, response) = try await session.data(from: url)
                guard !Task.isCancelled,
                      let http = response as? HTTPURLResponse,
                      (200 ..< 300).contains(http.statusCode) else { return nil }
                image = downsample(data)
            } catch {
                return nil
            }
        }

        guard !Task.isCancelled, let image else { return nil }
        let key = cacheKey(for: url)
        remember(image, key: key)
        if let data = image.jpegData(compressionQuality: 0.75) {
            let file = directory.appendingPathComponent(key + ".jpg")
            let previousSize = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try data.write(to: file, options: .atomic)
                if let diskSize { self.diskSize = diskSize + data.count - previousSize }
                trimDiskCache()
            } catch {
                // A disk cache failure must not prevent displaying the memory preview.
            }
        }
        return image
    }

    private let directory: URL
    private let session: URLSession
    private let memory = NSCache<NSString, UIImage>()
    private let diskLimit = 100 * 1024 * 1024
    private var diskSize: Int?

    private func cacheKey(for url: URL) -> String {
        SHA256.hash(data: Data(("v1|" + url.absoluteString).utf8))
            .map { String(format: "%02x", $0) }.joined()
    }

    private func remember(_ image: UIImage, key: String) {
        let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 360 * 360 * 4
        memory.setObject(image, forKey: key as NSString, cost: cost)
    }

    private func downsample(_ data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [
            kCGImageSourceShouldCache: false,
        ] as CFDictionary),
            let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 360,
                kCGImageSourceShouldCacheImmediately: true,
            ] as CFDictionary)
        else { return nil }
        return UIImage(cgImage: image)
    }

    private func trimDiskCache() {
        // Scan once, then again only when new writes cross the size limit.
        if let diskSize, diskSize <= diskLimit { return }
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey]
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: Array(keys)) else { return }
        let entries = files.compactMap { file -> (URL, Int, Date)? in
            guard let values = try? file.resourceValues(forKeys: keys) else { return nil }
            return (file, values.fileSize ?? 0, values.contentModificationDate ?? .distantPast)
        }
        var total = entries.reduce(0) { $0 + $1.1 }
        defer { diskSize = total }
        guard total > diskLimit else { return }
        for entry in entries.sorted(by: { $0.2 < $1.2 }) {
            do {
                try FileManager.default.removeItem(at: entry.0)
                total -= entry.1
            } catch {}
            if total <= diskLimit { break }
        }
    }
}
