import CryptoKit
import Foundation

/// A connection/account namespace, independent of the server's series ID format.
nonisolated struct ContinueReadingSource: Hashable, Comparable, Sendable {
    let id: String

    static let files = ContinueReadingSource(id: "device-files")

    static func server(kind: String, identity: String) -> Self {
        let hash = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
        return Self(id: "\(kind):\(hash)")
    }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.id < rhs.id }
}

/// Each adapter replaces only its own successful result. A failed request leaves
/// its cached items intact; other sources can still update independently.
struct ContinueReadingCollection {
    private struct Activity {
        let item: ContinueReadingItem
        let readAt: Date
    }

    private var cached: [ContinueReadingSource: [ContinueReadingItem]] = [:]
    private var activities: [ContinueReadingSource: [UUID: Activity]] = [:]

    mutating func setCachedItems(_ items: [ContinueReadingItem], source: ContinueReadingSource) {
        cached[source] = items.map { $0.withSource(source) }
    }

    mutating func acceptServerItems(_ items: [ContinueReadingItem], source: ContinueReadingSource,
                                   requestedAt: Date) {
        setCachedItems(items, source: source)
        // Reads that happened after the request began cannot be in that response.
        activities[source] = activities[source]?.filter { $0.value.readAt > requestedAt }
    }

    mutating func record(_ item: ContinueReadingItem, source: ContinueReadingSource, readAt: Date) {
        let sourcedItem = item.withSource(source).withReadDate(readAt)
        if let previous = activities[source]?[sourcedItem.id], previous.readAt > readAt { return }
        activities[source, default: [:]][sourcedItem.id] = Activity(item: sourcedItem, readAt: readAt)
    }

    mutating func removeActivity(itemID: UUID, source: ContinueReadingSource) {
        activities[source]?[itemID] = nil
    }

    func items(source: ContinueReadingSource) -> [ContinueReadingItem] {
        var byID = Dictionary(cached[source, default: []].map { ($0.id, $0) },
                              uniquingKeysWith: { _, newer in newer })
        for (id, activity) in activities[source, default: [:]] { byID[id] = activity.item }
        // Stable ties across devices, including servers with coarse timestamps.
        return ContinueReadingItem.sortedByLastRead(byID.values.sorted { $0.id.uuidString < $1.id.uuidString })
    }

    var items: [ContinueReadingItem] {
        let sources = Set(cached.keys).union(activities.keys).sorted()
        return ContinueReadingItem.sortedByLastRead(sources.flatMap { items(source: $0) })
    }
}
