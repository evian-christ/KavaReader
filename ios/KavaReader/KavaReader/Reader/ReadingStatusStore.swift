import CryptoKit
import Foundation

/// A hint for the read button and an offline fallback, never the server's authority.
struct ReadingStatus: Codable {
    let chapterId: Int?
    let volumeId: Int?
    let page: Int
    let confirmedByServer: Bool
    let revision: UUID?

    var hasProgress: Bool { chapterId != nil && page > 0 }
}

enum ReadingStatusStore {
    static func clear(identity: String, seriesId: Int) {
        UserDefaults.standard.removeObject(forKey: key(identity: identity, seriesId: seriesId))
    }

    static func load(identity: String, seriesId: Int) -> ReadingStatus? {
        guard let data = UserDefaults.standard.data(forKey: key(identity: identity, seriesId: seriesId)) else {
            return nil
        }
        return try? JSONDecoder().decode(ReadingStatus.self, from: data)
    }

    static func saveServerPoint(_ point: ContinuePointDto?, identity: String, seriesId: Int) {
        let status = ReadingStatus(chapterId: point?.chapterId, volumeId: point?.volumeId,
                                   page: point?.pagesRead ?? 0, confirmedByServer: true, revision: nil)
        save(status, identity: identity, seriesId: seriesId)
    }

    static func saveConfirmedProgress(chapterId: Int, volumeId: Int, page: Int,
                                      identity: String, seriesId: Int, revision: UUID)
    {
        guard let current = load(identity: identity, seriesId: seriesId),
              current.revision == revision,
              current.chapterId == chapterId, current.page == page
        else { return }
        save(ReadingStatus(chapterId: chapterId, volumeId: volumeId, page: page,
                           confirmedByServer: true, revision: revision), identity: identity, seriesId: seriesId)
    }

    @discardableResult
    static func saveLocalProgress(chapterId: Int, volumeId: Int?, page: Int,
                                  identity: String, seriesId: Int) -> UUID
    {
        let revision = UUID()
        save(ReadingStatus(chapterId: chapterId, volumeId: volumeId, page: page,
                           confirmedByServer: false, revision: revision),
             identity: identity, seriesId: seriesId)
        return revision
    }

    private static func save(_ status: ReadingStatus, identity: String, seriesId: Int) {
        guard let data = try? JSONEncoder().encode(status) else { return }
        UserDefaults.standard.set(data, forKey: key(identity: identity, seriesId: seriesId))
    }

    private static func key(identity: String, seriesId: Int) -> String {
        let value = "\(identity)|\(seriesId)"
        let hash = SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
        return "reading_status_\(hash)"
    }
}
