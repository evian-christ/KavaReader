import CryptoKit
import Foundation

extension Notification.Name {
    static let seriesReadingPauseDidChange = Notification.Name("seriesReadingPauseDidChange")
}

/// Reading membership is separate from the saved chapter and page position.
enum ReadingPauseStore {
    static func pausedSeriesIDs(identity: String, defaults: UserDefaults = .standard) -> Set<Int> {
        Set(defaults.array(forKey: key(identity)) as? [Int] ?? [])
    }

    static func setPaused(_ paused: Bool, identity: String, seriesId: Int,
                          defaults: UserDefaults = .standard, notify: Bool = true) {
        var ids = pausedSeriesIDs(identity: identity, defaults: defaults)
        guard ids.contains(seriesId) != paused else { return }
        if paused { ids.insert(seriesId) } else { ids.remove(seriesId) }
        defaults.set(ids.sorted(), forKey: key(identity))
        if notify {
            NotificationCenter.default.post(name: .seriesReadingPauseDidChange, object: identity,
                                            userInfo: ["seriesId": seriesId, "paused": paused])
        }
    }

    private static func key(_ identity: String) -> String {
        let hash = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
        return "reading_paused_\(hash)"
    }
}
