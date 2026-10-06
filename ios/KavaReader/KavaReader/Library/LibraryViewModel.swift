import Combine
import Foundation

extension Notification.Name {
    static let seriesWantToReadDidChange = Notification.Name("seriesWantToReadDidChange")
}

@MainActor
final class LibraryViewModel: ObservableObject {
    // MARK: Lifecycle

    init(service: LibraryServicing, catalogStore: LibraryCatalogStore = .shared) {
        self.service = service
        self.catalogStore = catalogStore
    }

    // MARK: Internal

    @Published private(set) var localStorageBytes: Int64 = 0
    @Published private(set) var catalogRevision = 0
    @Published private(set) var localComics: [LocalComic] = []
    @Published private(set) var localSeries: [LibrarySeries] = []
    private var localReloadID = UUID()
    private var localContinueReading: [ContinueReadingItem] = []
    private var continueReadingCollection = ContinueReadingCollection()
    private var continueRefreshID = UUID()
    private var isRefreshingContinueReading = false

    private var serverSource: ContinueReadingSource? {
        identity.map { .server(kind: "kavita", identity: $0) }
    }

    @Published private(set) var sections: [LibrarySection] = []
    @Published private(set) var continueReadingItems: [ContinueReadingItem] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastUpdatedAt: Date?
    @Published private(set) var libraryPlusRevision = "initial"

    func hasCatalog(identity: String) -> Bool {
        self.identity == identity && lastUpdatedAt != nil &&
            catalogSchemaVersion == LibraryCatalogSnapshot.currentSchemaVersion
    }

    /// Restore saved lists, then fetch them from Kavita when no current snapshot exists.
    func restore(service: LibraryServicing, identity: String, baseURL: String, apiKey: String) async
    {
        await reloadLocalComics()
        guard self.identity != identity else { return }
        self.service = service
        self.identity = identity
        libraryPlusRevision = LibraryPlusRevision.current(identity: identity)
        self.baseURL = URL(string: baseURL)
        self.apiKey = apiKey
        let restoreID = UUID()
        refreshID = restoreID
        isRefreshing = false
        errorMessage = nil
        sections = []
        continueReadingItems = []
        catalogSnapshot = nil
        continueReadingCollection = ContinueReadingCollection()
        continueRefreshID = UUID()
        isRefreshingContinueReading = false
        composeLocalCatalog()
        lastUpdatedAt = nil

        let snapshot = await catalogStore.load(identity: identity)
        guard self.identity == identity, refreshID == restoreID else { return }
        if let snapshot { apply(snapshot) }
        if baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return }
        if snapshot?.schemaVersion != LibraryCatalogSnapshot.currentSchemaVersion {
            await refresh(invalidateCovers: false)
        } else {
            await refreshContinueReading()
        }
    }

    /// A lightweight source refresh: recommendation inputs and cover caches stay fixed.
    func refreshContinueReading(replaceInFlight: Bool = false) async {
        guard (!isRefreshingContinueReading || replaceInFlight), !isRefreshing,
              let identity, let source = serverSource, baseURL != nil,
              let existing = catalogSnapshot else { return }
        let requestID = UUID()
        continueRefreshID = requestID
        isRefreshingContinueReading = true
        defer {
            if continueRefreshID == requestID { isRefreshingContinueReading = false }
        }
        let requestedAt = Date()
        let fullRefreshID = refreshID
        let currentService = service
        let generation = await catalogStore.currentGeneration()
        do {
            let items = try await currentService.fetchContinueReadingItems()
            guard self.identity == identity, continueRefreshID == requestID,
                  refreshID == fullRefreshID, !Task.isCancelled else { return }
            continueReadingCollection.acceptServerItems(items, source: source, requestedAt: requestedAt)
            // Keep the latest sections without rebuilding the entire catalog.
            let snapshot = (catalogSnapshot ?? existing).replacingContinueReading(continueReadingCollection.items(source: source))
            catalogSnapshot = snapshot
            updateContinueReadingItems()
            try await catalogStore.saveContinueReading(snapshot.continueReading, identity: identity, generation: generation)
            if self.identity == identity, continueRefreshID == requestID { errorMessage = nil }
        } catch {
            if self.identity == identity, continueRefreshID == requestID {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Immediate display while the adapter saves progress to the owning server.
    func recordReadingActivity(_ item: ContinueReadingItem, identity activityIdentity: String?,
                               readAt: Date) async {
        let source: ContinueReadingSource
        if item.series.isLocal {
            source = .files
        } else {
            guard activityIdentity == identity, let currentSource = serverSource else { return }
            source = currentSource
        }
        continueReadingCollection.record(item, source: source, readAt: readAt)
        updateContinueReadingItems()
        guard source != .files, let identity, let catalogSnapshot else { return }
        let snapshot = catalogSnapshot.replacingContinueReading(continueReadingCollection.items(source: source))
        self.catalogSnapshot = snapshot
        let generation = await catalogStore.currentGeneration()
        guard self.identity == identity, let latest = self.catalogSnapshot else { return }
        try? await catalogStore.saveContinueReading(latest.continueReading, identity: identity, generation: generation)
    }

    func refresh(invalidateCovers: Bool = true, replaceInFlight: Bool = false,
                 updateLibraryPlus: Bool = false) async {
        guard (!isRefreshing || replaceInFlight), let identity else { return }
        let requestID = UUID()
        refreshID = requestID
        continueRefreshID = UUID()
        isRefreshingContinueReading = false
        isRefreshing = true
        errorMessage = nil
        let cacheGeneration = await catalogStore.currentGeneration()
        guard refreshID == requestID else { return }
        let currentService = service
        let requestedAt = Date()

        do {
            async let sectionsTask = currentService.fetchSections()
            async let continueReadingTask = currentService.fetchContinueReadingItems()
            let loaded = try await sectionsTask
            let continueItems = try await continueReadingTask
            guard refreshID == requestID, self.identity == identity else { return }
            if let source = serverSource {
                continueReadingCollection.acceptServerItems(continueItems, source: source, requestedAt: requestedAt)
            }
            let snapshot = LibraryCatalogSnapshot(sections: loaded,
                                                  continueReading: serverSource.map { continueReadingCollection.items(source: $0) } ?? continueItems)
            apply(snapshot)
            if updateLibraryPlus {
                libraryPlusRevision = LibraryPlusRevision.advance(identity: identity)
            }
            do {
                try await catalogStore.save(snapshot, identity: identity,
                                                          generation: cacheGeneration)
            } catch {
                if refreshID == requestID {
                    errorMessage = AppLocalization.format("목록은 갱신됐지만 기기에 저장하지 못했습니다: %@",
                                                          error.localizedDescription)
                }
            }
            guard refreshID == requestID, self.identity == identity else { return }
            if invalidateCovers {
                do {
                    try await CoverImageCache.shared.clear()
                    if refreshID == requestID {
                        let key = "cover_cache_revision"
                        UserDefaults.standard.set(UserDefaults.standard.integer(forKey: key) + 1, forKey: key)
                    }
                } catch {
                    if refreshID == requestID, errorMessage == nil {
                        errorMessage = "목록은 갱신됐지만 이전 표지를 삭제하지 못했습니다."
                    }
                }
            }
        } catch {
            if refreshID == requestID {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
        if refreshID == requestID { isRefreshing = false }
    }

    /// A successful server mutation removes the old reading markers before reloading the catalog.
    func applyReadStateChange(seriesId: Int, read: Bool) async {
        guard let identity else { return }
        if let source = serverSource {
            for item in continueReadingCollection.items(source: source) where item.series.kavitaSeriesId == seriesId {
                continueReadingCollection.removeActivity(itemID: item.id, source: source)
            }
        }
        let updateID = UUID()
        refreshID = updateID
        isRefreshing = false
        var sections = catalogSnapshot?.domainSections(baseURL: baseURL, apiKey: apiKey) ?? self.sections
        var continueReadingItems = catalogSnapshot?.domainContinueReading(baseURL: baseURL, apiKey: apiKey) ?? self.continueReadingItems
        sections = sections.compactMap { section in
            if section.title == "읽는 중" {
                let items = section.items.filter { $0.kavitaSeriesId != seriesId }
                return items.isEmpty ? nil : LibrarySection(id: section.id, title: section.title, items: items)
            }
            let items = section.items.map { item in
                guard item.kavitaSeriesId == seriesId else { return item }
                return SeriesInfo(id: item.id, kavitaSeriesId: item.kavitaSeriesId,
                                  title: item.title, author: item.author,
                                  coverColorHexes: item.coverColorHexes, coverURL: item.coverURL,
                                  isRead: read, totalPages: item.totalPages,
                                  pagesRead: read ? item.totalPages : 0)
            }
            return LibrarySection(id: section.id, title: section.title, items: items)
        }
        continueReadingItems.removeAll { $0.series.kavitaSeriesId == seriesId }

        let generation = await catalogStore.currentGeneration()
        guard self.identity == identity, refreshID == updateID else { return }
        let snapshot = LibraryCatalogSnapshot(sections: sections, continueReading: continueReadingItems)
        apply(snapshot)
        try? await catalogStore.save(snapshot, identity: identity, generation: generation)
        guard self.identity == identity, refreshID == updateID else { return }
        await refresh(invalidateCovers: false, replaceInFlight: true)
    }

    /// Keep the Favourite section and its saved catalog in sync after a confirmed server change.
    func applyWantToReadChange(series: LibrarySeries, isWanted: Bool) async {
        guard let identity, let seriesId = series.kavitaSeriesId else { return }
        let updateID = UUID()
        refreshID = updateID
        isRefreshing = false

        var sections = catalogSnapshot?.domainSections(baseURL: baseURL, apiKey: apiKey) ?? self.sections
        let continueReadingItems = catalogSnapshot?.domainContinueReading(baseURL: baseURL, apiKey: apiKey) ?? self.continueReadingItems
        let existingIndex = sections.firstIndex(where: { $0.title == "Favourite" })
        var items = existingIndex.map { sections[$0].items } ?? []
        items.removeAll { $0.kavitaSeriesId == seriesId }
        if isWanted {
            let currentReadState = sections.lazy.flatMap(\.items)
                .first(where: { $0.kavitaSeriesId == seriesId })?.isRead ?? series.isRead
            items.insert(SeriesInfo(id: series.id, kavitaSeriesId: seriesId, title: series.title,
                                    author: series.author, coverColorHexes: series.coverColorHexes,
                                    coverURL: series.coverURL, isRead: currentReadState,
                                    totalPages: series.totalPages, pagesRead: series.pagesRead), at: 0)
        }
        let updated = LibrarySection(id: existingIndex.map { sections[$0].id } ?? UUID(),
                                     title: "Favourite", items: items)
        if let existingIndex {
            sections[existingIndex] = updated
        } else {
            sections.insert(updated, at: 0)
        }
        lastUpdatedAt = Date()

        let generation = await catalogStore.currentGeneration()
        guard self.identity == identity, refreshID == updateID else { return }
        let snapshot = LibraryCatalogSnapshot(sections: sections, continueReading: continueReadingItems)
        apply(snapshot)
        try? await catalogStore.save(snapshot, identity: identity, generation: generation)
    }

    func applyReadingPauseChange() {
        if let catalogSnapshot { apply(catalogSnapshot) } else { composeLocalCatalog() }
    }

    func reloadLocalComics() async {
        let reloadID = UUID()
        let requestedAt = Date()
        localReloadID = reloadID
        do {
            let loaded = try await LocalComicStore.shared.all()
            var series: [LibrarySeries] = []
            var continuing: [ContinueReadingItem] = []
            let readDateFormatter = ISO8601DateFormatter()
            readDateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            for comic in loaded {
                let item = comic.series(coverURL: await LocalComicStore.shared.coverURL(comic.id))
                series.append(item)
                if let chapterID = comic.lastChapterID,
                   let detail = try? await LocalComicStore.shared.detail(comic.id),
                   let chapter = detail.chapters.first(where: { $0.id == chapterID }),
                   !item.isRead {
                    continuing.append(ContinueReadingItem(series: item, lastReadChapter: chapter,
                        progress: ProgressDto(volumeId: 0, chapterId: 0, pageNum: chapter.lastReadPage ?? 1,
                                              seriesId: 0, libraryId: 0, bookScrollId: nil,
                                              lastModifiedUtc: comic.lastReadAt.map { readDateFormatter.string(from: $0) } ?? "")))
                }
            }
            guard localReloadID == reloadID, !Task.isCancelled else { return }
            localComics = loaded
            localStorageBytes = loaded.flatMap(\.volumes).reduce(0) { $0 + $1.bytes }
            localSeries = series
            let dates = Dictionary(uniqueKeysWithValues: loaded.map { ($0.id, $0.lastReadAt ?? .distantPast) })
            localContinueReading = continuing.sorted { (dates[$0.series.id] ?? .distantPast) > (dates[$1.series.id] ?? .distantPast) }
            continueReadingCollection.acceptServerItems(localContinueReading, source: .files, requestedAt: requestedAt)
            if let catalogSnapshot { apply(catalogSnapshot) } else { composeLocalCatalog() }
        } catch { errorMessage = error.localizedDescription }
    }

    func isFavourite(_ series: LibrarySeries) -> Bool {
        sections.first { $0.title == "Favourite" }?.items.contains { $0.id == series.id } ?? false
    }

    func isReading(_ series: LibrarySeries) -> Bool {
        sections.first { $0.title == "읽는 중" }?.items.contains { $0.id == series.id } ?? false
    }

    private func composeLocalCatalog() {
        sections = sections.filter { $0.title != "Files" }.map { section in
            LibrarySection(id: section.id, title: section.title, items: section.items.filter { $0.kavitaSeriesId != nil })
        }
        func append(_ title: String, _ series: [LibrarySeries]) {
            let old = sections.first { $0.title == title }
            let items = (old?.items ?? []) + series.map {
                SeriesInfo(id: $0.id, kavitaSeriesId: nil, title: $0.title, author: $0.author,
                           coverColorHexes: $0.coverColorHexes, coverURL: $0.coverURL,
                           isRead: $0.isRead, totalPages: $0.totalPages, pagesRead: $0.pagesRead, isLocal: true)
            }
            let section = LibrarySection(id: old?.id ?? UUID(), title: title, items: items)
            if let index = sections.firstIndex(where: { $0.title == title }) { sections[index] = section }
            else { sections.append(section) }
        }
        append("Files", localSeries)
        append("All Series", localSeries)
        let favourites = Set(localComics.filter(\.favourite).map(\.id))
        let byID = Dictionary(uniqueKeysWithValues: localSeries.map { ($0.id, $0) })
        append("Favourite", localSeries.filter { favourites.contains($0.id) })
        append("Recently Added", localComics.sorted { $0.addedAt > $1.addedAt }.compactMap { byID[$0.id] })
        append("읽는 중", localContinueReading.map(\.series))
        continueReadingCollection.setCachedItems(localContinueReading, source: .files)
        updateContinueReadingItems()
        catalogRevision += 1
    }

    private func updateContinueReadingItems() {
        let localIDs = Set(localSeries.filter { !$0.isRead }.map(\.id))
        let pausedIDs = identity.map { ReadingPauseStore.pausedSeriesIDs(identity: $0) } ?? []
        continueReadingItems = continueReadingCollection.items.filter { item in
            if item.source == .files { return localIDs.contains(item.series.id) }
            return !pausedIDs.contains(item.series.kavitaSeriesId ?? -1)
        }
    }

    func searchSeries(query: String) -> [LibrarySeries] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return [] }

        var seenIDs = Set<UUID>()
        return sections.flatMap(\.items)
            .filter { item in
                let matches = item.title.localizedCaseInsensitiveContains(term) ||
                    item.author.localizedCaseInsensitiveContains(term)
                return matches && seenIDs.insert(item.id).inserted
            }
            .map { $0.toLibrarySeries() }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    // MARK: Private

    private var catalogSnapshot: LibraryCatalogSnapshot?
    private var catalogSchemaVersion: Int?
    private var identity: String?
    private var baseURL: URL?
    private var apiKey = ""
    private var refreshID = UUID()
    private var service: LibraryServicing
    private let catalogStore: LibraryCatalogStore

    private func apply(_ snapshot: LibraryCatalogSnapshot) {
        catalogSnapshot = snapshot
        catalogSchemaVersion = snapshot.schemaVersion
        let pausedIDs = identity.map { ReadingPauseStore.pausedSeriesIDs(identity: $0) } ?? []
        sections = snapshot.domainSections(baseURL: baseURL, apiKey: apiKey).compactMap { section in
            guard section.title == "읽는 중" else { return section }
            let items = section.items.filter { !pausedIDs.contains($0.kavitaSeriesId ?? -1) }
            return items.isEmpty ? nil : LibrarySection(id: section.id, title: section.title, items: items)
        }
        if let source = serverSource {
            continueReadingCollection.setCachedItems(snapshot.domainContinueReading(baseURL: baseURL, apiKey: apiKey), source: source)
        }
        lastUpdatedAt = snapshot.savedAt
        composeLocalCatalog()
    }
}
