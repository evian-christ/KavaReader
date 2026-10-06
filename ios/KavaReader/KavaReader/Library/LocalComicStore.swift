import Combine
import CryptoKit
import Foundation
import ImageIO
import UIKit

extension Notification.Name {
    static let localComicsDidChange = Notification.Name("localComicsDidChange")
}

nonisolated struct LocalComicVolume: Codable, Identifiable, Sendable {
    let id: UUID
    let title: String
    let archive: String
    let digest: String
    let pageCount: Int
    let bytes: Int64
    var page = 0
    var epub: EpubPublication? = nil
    var epubLocation: EpubLocation? = nil
    var embeddedMetadata: LibraryPlusMetadata? = nil
    var metadataVersion: Int? = nil
}

nonisolated struct LocalComic: Codable, Identifiable, Sendable {
    let id: UUID
    var title: String
    var volumes: [LocalComicVolume]
    var author: String? = nil
    var coverAvailable: Bool? = nil
    var favourite = false
    let addedAt: Date
    var lastReadAt: Date?
    var lastChapterID: UUID?
}

actor LocalComicStore {
    static let shared = LocalComicStore()
    private let root: URL
    private var comics: [LocalComic] = []
    private var loadError: Error?
    private var cachedArchive: (id: UUID, archive: ComicArchive)?

    init(root: URL? = nil) {
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("KavaReader/LocalComics", isDirectory: true)
        let catalog = self.root.appendingPathComponent("catalog.json")
        if FileManager.default.fileExists(atPath: catalog.path) {
            do { comics = try JSONDecoder().decode([LocalComic].self, from: Data(contentsOf: catalog)) }
            catch { loadError = error }
        }
    }

    func all() throws -> [LocalComic] {
        if let loadError { throw loadError }
        return comics
    }

    /// Lazily migrate old imports; malformed optional XML does not prevent reading the work.
    func metadataCatalog() throws -> [LocalComic] {
        var updated = try all()
        var changed = false
        for s in updated.indices {
            for v in updated[s].volumes.indices where updated[s].volumes[v].metadataVersion != 1 {
                try Task.checkCancellation()
                let volume = updated[s].volumes[v]
                do {
                    let archive = try ComicArchive(url: root.appendingPathComponent(volume.archive), includeAllEntries: true)
                    let metadata: LibraryPlusMetadata
                    if volume.epub != nil {
                        let publication = try EpubPublication(archive: archive)
                        updated[s].volumes[v].epub = publication
                        metadata = publication.embeddedMetadata ?? LibraryPlusMetadata(summary: "", genres: [], tags: [])
                    } else {
                        metadata = (try? EmbeddedMetadataReader.comic(archive)) ?? LibraryPlusMetadata(summary: "", genres: [], tags: [])
                    }
                    updated[s].volumes[v].embeddedMetadata = metadata
                    updated[s].volumes[v].metadataVersion = 1
                    changed = true
                } catch is CancellationError { throw CancellationError() }
                catch { continue } // One unreadable archive must not hide metadata for every other work.
            }
        }
        // Metadata indexing does not change the catalog's progress or notify/restart itself.
        if changed { try commit(updated, notify: false) }
        return updated
    }

    func coverURL(_ id: UUID) -> URL? {
        guard comics.first(where: { $0.id == id })?.coverAvailable != false else { return nil }
        return root.appendingPathComponent("\(id.uuidString)/cover.jpg")
    }

    func importFile(_ source: URL, group: String?, target: UUID? = nil) throws -> Bool {
        if let loadError { throw loadError }
        guard LocalComicImport.supports(source) else { throw LocalComicImport.Failure.unsupportedFormat }
        try Task.checkCancellation()
        // Coordinate iCloud/File Provider downloads before reading or copying their content.
        var coordinationError: NSError?
        var result: Result<Bool, Error>?
        NSFileCoordinator().coordinate(readingItemAt: source, options: [], error: &coordinationError) { url in
            result = Result { try importCoordinatedFile(url, group: group, target: target) }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw ComicArchive.Failure.invalid }
        return try result.get()
    }

    private func importCoordinatedFile(_ source: URL, group: String?, target: UUID?) throws -> Bool {
        try Task.checkCancellation()
        guard LocalComicImport.supports(source) else { throw LocalComicImport.Failure.unsupportedFormat }
        let digest = try hash(source)
        if comics.flatMap(\.volumes).contains(where: { $0.digest == digest }) { return false }
        let archive = try ComicArchive(url: source)
        let embedded = (try? EmbeddedMetadataReader.comic(ComicArchive(url: source, includeAllEntries: true))) ??
            LibraryPlusMetadata(summary: "", genres: [], tags: [])
        guard let coverData = thumbnail(try archive.imageData(at: 0)) else { throw ComicArchive.Failure.noImages }
        let title = group ?? source.deletingPathExtension().lastPathComponent
        let existing = target.flatMap { id in comics.firstIndex { $0.id == id } } ??
            (group == nil ? nil : comics.firstIndex { $0.title == title })
        let id = existing.map { comics[$0].id } ?? UUID()
        let volumeID = UUID()
        let folder = root.appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = "\(volumeID.uuidString).cbz"
        let destination = folder.appendingPathComponent(name)
        do {
            try FileManager.default.copyItem(at: source, to: destination)
            if existing == nil { try coverData.write(to: folder.appendingPathComponent("cover.jpg"), options: .atomic) }
            let size = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            let volume = LocalComicVolume(id: volumeID, title: source.deletingPathExtension().lastPathComponent,
                                          archive: "\(id.uuidString)/\(name)", digest: digest,
                                          pageCount: archive.entries.count,
                                          bytes: Int64(size), embeddedMetadata: embedded, metadataVersion: 1)
            var updated = comics
            if let existing {
                updated[existing].volumes.append(volume)
                updated[existing].volumes.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            } else {
                updated.append(LocalComic(id: id, title: title, volumes: [volume],
                                          coverAvailable: true, addedAt: Date()))
            }
            try commit(updated)
            return true
        } catch {
            try? FileManager.default.removeItem(at: destination)
            if existing == nil { try? FileManager.default.removeItem(at: folder) }
            throw error
        }
    }

    func detail(_ id: UUID) async throws -> SeriesDetail {
        guard let comic = try all().first(where: { $0.id == id }) else { throw LibraryServiceError.noData }
        let cover = coverURL(id)
        return await MainActor.run { SeriesDetail(id: id, title: comic.title, author: comic.author ?? "", summary: comic.embeddedMetadata.summary, coverImageURL: cover,
                            chapters: comic.volumes.enumerated().map { index, volume in
            SeriesChapter(id: volume.id, title: volume.title, number: Double(index + 1), pageCount: volume.pageCount,
                          lastReadPage: volume.page, coverImageURL: cover, isEpub: volume.epub != nil)
        }) }
    }

    func pageData(chapterID: UUID, page: Int) throws -> Data {
        guard let volume = try all().flatMap(\.volumes).first(where: { $0.id == chapterID }) else {
            throw LibraryServiceError.noData
        }
        if cachedArchive?.id != chapterID {
            cachedArchive = (chapterID, try ComicArchive(url: root.appendingPathComponent(volume.archive)))
        }
        return try cachedArchive!.archive.imageData(at: page - 1)
    }

    func saveProgress(seriesID: UUID, chapterID: UUID, page: Int) throws {
        var updated = try all()
        guard let s = updated.firstIndex(where: { $0.id == seriesID }),
              let v = updated[s].volumes.firstIndex(where: { $0.id == chapterID }) else { return }
        updated[s].volumes[v].page = min(max(1, page), updated[s].volumes[v].pageCount)
        updated[s].lastReadAt = Date()
        updated[s].lastChapterID = chapterID
        try commit(updated)
    }

    func edit(_ id: UUID, title: String? = nil, favourite: Bool? = nil, read: Bool? = nil) throws {
        var updated = try all()
        guard let index = updated.firstIndex(where: { $0.id == id }) else { return }
        if let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            updated[index].title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let favourite { updated[index].favourite = favourite }
        if let read {
            for v in updated[index].volumes.indices {
                updated[index].volumes[v].page = read ? updated[index].volumes[v].pageCount : 0
                updated[index].volumes[v].epubLocation = nil
            }
            updated[index].lastReadAt = nil
            updated[index].lastChapterID = nil
        }
        try commit(updated)
    }

    func merge(_ source: UUID, into target: UUID) throws {
        var updated = try all()
        guard source != target, let from = updated.firstIndex(where: { $0.id == source }),
              let to = updated.firstIndex(where: { $0.id == target }) else { return }
        updated[to].volumes += updated[from].volumes
        updated[to].volumes.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        updated[to].favourite = updated[to].favourite || updated[from].favourite
        updated.remove(at: from)
        // Archive paths remain stable, even when a volume changes its parent work.
        try commit(updated)
    }

    func delete(_ id: UUID) throws {
        let current = try all()
        guard let comic = current.first(where: { $0.id == id }) else { return }
        let remaining = current.filter { $0.id != id }
        try commit(remaining)
        cachedArchive = nil
        for volume in comic.volumes { try? FileManager.default.removeItem(at: root.appendingPathComponent(volume.archive)) }
        // A merged work may still refer to archives in this folder.
        let folders = Set(comic.volumes.map { ($0.archive as NSString).deletingLastPathComponent } + [id.uuidString])
        for folder in folders where !remaining.flatMap(\.volumes).contains(where: { $0.archive.hasPrefix(folder + "/") }) {
            try? FileManager.default.removeItem(at: root.appendingPathComponent(folder))
        }
    }

    func epubVolume(_ id: UUID) throws -> LocalComicVolume {
        guard let volume = try all().flatMap(\.volumes).first(where: { $0.id == id }), volume.epub != nil else {
            throw EpubPublication.Failure.invalid
        }
        return volume
    }

    func epubResource(volumeID: UUID, path: String) throws -> (data: Data, mime: String) {
        let volume = try epubVolume(volumeID)
        guard let mime = volume.epub?.resources[path] else { throw EpubPublication.Failure.unsafePath }
        if cachedArchive?.id != volumeID {
            cachedArchive = (volumeID, try ComicArchive(url: root.appendingPathComponent(volume.archive), includeAllEntries: true))
        }
        return (try cachedArchive!.archive.resource(named: path), mime)
    }

    func saveEpubLocation(seriesID: UUID, volumeID: UUID, location: EpubLocation) throws {
        var updated = try all()
        guard let s = updated.firstIndex(where: { $0.id == seriesID }),
              let v = updated[s].volumes.firstIndex(where: { $0.id == volumeID }),
              let epub = updated[s].volumes[v].epub,
              epub.sections.indices.contains(location.section), location.fraction.isFinite else { return }
        let fraction = min(1, max(0, location.fraction))
        updated[s].volumes[v].epubLocation = EpubLocation(section: location.section, fraction: fraction)
        updated[s].volumes[v].page = max(1, location.section * 1000 + Int(fraction * 1000))
        updated[s].lastReadAt = Date()
        updated[s].lastChapterID = volumeID
        try commit(updated)
    }

    private func thumbnail(_ data: Data) -> Data? {
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                      kCGImageSourceThumbnailMaxPixelSize: 1024,
                                      kCGImageSourceCreateThumbnailWithTransform: true]
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: image).jpegData(compressionQuality: 0.8)
    }

    private func commit(_ updated: [LocalComic], notify: Bool = true) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try JSONEncoder().encode(updated).write(to: root.appendingPathComponent("catalog.json"), options: .atomic)
        comics = updated
        if notify { NotificationCenter.default.post(name: .localComicsDidChange, object: nil) }
    }

    private func hash(_ url: URL) throws -> String {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var hasher = SHA256()
        while let data = try file.read(upToCount: 1024 * 1024), !data.isEmpty {
            try Task.checkCancellation()
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

extension LocalComic {
    var embeddedMetadata: LibraryPlusMetadata {
        let values = volumes.compactMap { $0.embeddedMetadata ?? $0.epub?.embeddedMetadata }
        return LibraryPlusMetadata(summary: values.first { !$0.summary.isEmpty }?.summary ?? "",
                                   genres: values.flatMap(\.genres), tags: values.flatMap(\.tags))
    }

    @MainActor func series(coverURL: URL?) -> LibrarySeries {
        LibrarySeries(id: id, title: title, author: author ?? "", coverColorHexes: [], coverURL: coverURL,
                      isRead: volumes.allSatisfy { $0.page >= $0.pageCount },
                      totalPages: volumes.reduce(0) { $0 + $1.pageCount }, pagesRead: volumes.reduce(0) { $0 + $1.page }, isLocal: true)
    }
}
