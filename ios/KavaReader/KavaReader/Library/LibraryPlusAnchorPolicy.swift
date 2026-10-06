import Foundation

struct LibraryPlusAnchorRecord: Codable, Equatable, Sendable {
    let day: Int
    let seriesId: Int
}

/// Anchor eligibility uses whole-series progress, never the current chapter's percentage.
enum LibraryPlusAnchorPolicy {
    static func progress(_ series: LibrarySeries) -> Double? {
        if series.isRead { return 1 }
        guard let total = series.totalPages, total > 0,
              let read = series.pagesRead, read >= 0 else { return nil }
        return min(1, Double(read) / Double(total))
    }

    static func candidates(_ series: [LibrarySeries], history: [LibraryPlusAnchorRecord], day: Int,
                           rank: (Int) -> UInt64) -> [LibrarySeries] {
        let yesterday = Set(history.filter { $0.day == day - 1 }.map(\.seriesId))
        let eligible = series.filter { item in
            guard let id = item.kavitaSeriesId, !yesterday.contains(id),
                  let progress = progress(item), progress >= 0.5 else { return false }
            return true
        }
        return eligible.sorted { left, right in
            let leftComplete = progress(left) == 1
            let rightComplete = progress(right) == 1
            if leftComplete != rightComplete { return leftComplete }
            let leftScore = priority(left, history: history, day: day)
            let rightScore = priority(right, history: history, day: day)
            if leftScore != rightScore { return leftScore > rightScore }
            let leftId = left.kavitaSeriesId ?? 0
            let rightId = right.kavitaSeriesId ?? 0
            let leftRank = rank(leftId), rightRank = rank(rightId)
            return leftRank == rightRank ? leftId < rightId : leftRank < rightRank
        }
    }

    private static func priority(_ series: LibrarySeries, history: [LibraryPlusAnchorRecord], day: Int) -> Double {
        let penalty = history.reduce(0.0) { total, record in
            let age = day - record.day
            guard record.seriesId == series.kavitaSeriesId, (2 ... 30).contains(age) else { return total }
            return total + 30 * pow(0.85, Double(age - 2))
        }
        return (progress(series) ?? 0) * 100 - penalty
    }
}
