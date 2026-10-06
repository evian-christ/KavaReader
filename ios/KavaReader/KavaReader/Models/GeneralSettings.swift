import Foundation
import UIKit

enum GeneralSettings {
    static let homeItemsPerRowKey = "home_items_per_row"
    static let libraryItemsPerRowKey = "library_items_per_row"
    static let detailItemsPerRowKey = "detail_items_per_row"
    static var defaultItemsPerRow: Int { UIDevice.current.userInterfaceIdiom == .phone ? 3 : 5 }
    static let itemsPerRowRange = 2 ... 10

    static func itemsPerRow(_ value: Int) -> Int {
        min(max(value, itemsPerRowRange.lowerBound), itemsPerRowRange.upperBound)
    }
}

nonisolated enum IndexingSettings {
    static let alternateTitleSearchKey = "indexing_alternate_title_search"

    static var alternateTitleSearchEnabled: Bool {
        UserDefaults.standard.bool(forKey: alternateTitleSearchKey)
    }

    static func containsKorean(_ title: String) -> Bool {
        title.unicodeScalars.contains {
            (0xAC00 ... 0xD7A3).contains($0.value) || (0x1100 ... 0x11FF).contains($0.value) ||
                (0x3130 ... 0x318F).contains($0.value)
        }
    }

    static func needsAlternateSearch(title: String, hasMatch: Bool, attempted: Bool?, enabled: Bool) -> Bool {
        enabled && !hasMatch && attempted != true && containsKorean(title)
    }
}
