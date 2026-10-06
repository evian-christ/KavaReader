import Combine
import CryptoKit
import Foundation

/// Categories from a primary source (Kavita or an imported file).
nonisolated struct LibraryPlusMetadata: Codable, Hashable, Sendable {
    // MARK: Lifecycle

    init(summary: String, genres: [String], tags: [String]) {
        self.summary = summary.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.genres = MetadataCategoryRegistry.cleaned(genres, kind: .genre)
        self.tags = MetadataCategoryRegistry.cleaned(tags, kind: .tag)
    }

    // MARK: Internal

    let summary: String
    let genres: [String]
    let tags: [String]

    var hasCategories: Bool { !genres.isEmpty || !tags.isEmpty }

    static func resolved(kavita: LibraryPlusMetadata, external: ExternalSeriesMetadata?) -> LibraryPlusMetadata {
        resolved(primary: kavita, external: external)
    }

    static func resolved(primary: LibraryPlusMetadata, external: ExternalSeriesMetadata?,
                         manual: ManualSeriesMetadataRecord? = nil) -> LibraryPlusMetadata
    {
        if let manual {
            // A selected work is authoritative, including an intentionally unclassified work.
            guard let linked = manual.metadata else { return primary }
            return LibraryPlusMetadata(summary: primary.summary, genres: linked.genres, tags: linked.tags)
        }
        guard !primary.hasCategories, let external else { return primary }
        return LibraryPlusMetadata(summary: primary.summary,
                                   genres: external.genres, tags: external.tags)
    }

    private enum CodingKeys: String, CodingKey { case summary, genres, tags }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(summary: try values.decode(String.self, forKey: .summary),
                  genres: try values.decode([String].self, forKey: .genres),
                  tags: try values.decode([String].self, forKey: .tags))
    }
}

private actor LibraryPlusMetadataStore {
    // MARK: Internal

    static let shared = LibraryPlusMetadataStore()

    func load(identity: String) -> [Int: LibraryPlusMetadata] {
        guard let data = try? Data(contentsOf: fileURL(for: identity)) else { return [:] }
        return (try? JSONDecoder().decode([Int: LibraryPlusMetadata].self, from: data)) ?? [:]
    }

    func save(_ metadata: [Int: LibraryPlusMetadata], identity: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(metadata).write(to: fileURL(for: identity), options: .atomic)
    }

    // MARK: Private

    private let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("KavaReader/LibraryPlus", isDirectory: true)

    private func fileURL(for identity: String) -> URL {
        let hash = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(hash + ".json")
    }
}

private struct ExternalLookupRecord: Codable {
    let queriedTitle: String
    let checkedAt: Date
    let match: ExternalSeriesMetadata?
    var alternateTitleSearchAttempted: Bool? = nil

    func isFresh(for title: String, now: Date, alternateSearchEnabled: Bool = false) -> Bool {
        if IndexingSettings.needsAlternateSearch(title: title, hasMatch: match != nil,
                                                 attempted: alternateTitleSearchAttempted,
                                                 enabled: alternateSearchEnabled) { return false }
        let lifetime: TimeInterval = match == nil ? 30 * 24 * 60 * 60 : 365 * 24 * 60 * 60
        return queriedTitle == title && now.timeIntervalSince(checkedAt) < lifetime
    }
}

private struct ExternalLookupSnapshot: Codable {
    var records: [Int: ExternalLookupRecord] = [:]
    var dayKey = 0
    var requestsToday = 0
    var blockedUntil: Date? = nil
}

private actor ExternalLookupStore {
    // MARK: Internal

    static let shared = ExternalLookupStore()

    func load(identity: String) -> ExternalLookupSnapshot {
        guard let data = try? Data(contentsOf: fileURL(for: identity)) else { return ExternalLookupSnapshot() }
        return (try? JSONDecoder().decode(ExternalLookupSnapshot.self, from: data)) ?? ExternalLookupSnapshot()
    }

    func save(_ snapshot: ExternalLookupSnapshot, identity: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(snapshot).write(to: fileURL(for: identity), options: .atomic)
    }

    // MARK: Private

    private let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("KavaReader/LibraryPlus", isDirectory: true)

    private func fileURL(for identity: String) -> URL {
        let hash = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(hash + "-anilist.json")
    }
}

struct SeriesInformationSnapshot: Sendable {
    let kavita: LibraryPlusMetadata?
    let external: ExternalSeriesMetadata?
    let manual: ManualSeriesMetadataRecord?
}

enum SeriesInformationCache {
    static func load(identity: String, seriesID: Int, title: String) async -> SeriesInformationSnapshot {
        async let kavita = LibraryPlusMetadataStore.shared.load(identity: identity)
        async let external = ExternalLookupStore.shared.load(identity: identity)
        async let manualRecords = ManualSeriesMetadataStore.shared.load(identity: identity)
        let metadataByID = await kavita
        let snapshot = await external
        let record = snapshot.records[seriesID]
        let manual = await manualRecords
        return SeriesInformationSnapshot(kavita: metadataByID[seriesID],
                                         external: manual[seriesID] != nil ? manual[seriesID]?.metadata
                                             : (record?.isFresh(for: title, now: Date()) == true ? record?.match : nil),
                                         manual: manual[seriesID])
    }
}

/// Frozen inputs for one local calendar day. Catalog models omit credentials and cover URLs.
struct LibraryPlusDailySnapshot: Codable {
    static let currentCurationVersion = 3

    var curationVersion: Int? = 3
    let day: Int
    let revision: String
    let catalog: LibraryCatalogSnapshot
    let metadata: [Int: LibraryPlusMetadata]
    var external: [Int: ExternalSeriesMetadata]
    var selection: LibraryPlusSelection? = nil
    var manualConnectionRevision: String? = nil
    var manualConnections: [Int: ManualSeriesMetadataRecord]? = nil

    func matches(day: Int, revision: String) -> Bool {
        self.day == day && self.revision == revision &&
            curationVersion == Self.currentCurationVersion
    }
}

/// Persist the selected IDs and their order, rather than rerunning curation during rendering.
struct LibraryPlusSelection: Codable, Equatable {
    struct Row: Codable, Equatable {
        let id: String
        let title: String
        let seriesIDs: [Int]
        let subtitle: String?
    }

    let featuredIDs: [Int]
    let rows: [Row]
    let hasRecommendations: Bool
    var anchorSeriesId: Int? = nil
}

struct LibraryPlusPresentation {
    let featured: [LibrarySeries]
    let rows: [LibraryPlusRow]
    let metadata: [Int: LibraryPlusMetadata]
    let favouriteIDs: Set<Int>
    let hasRecommendations: Bool
    let hasSeries: Bool
    var genreSeriesIDs: [HomeGenre: Set<Int>] = [:]
}

extension LibraryPlusDailySnapshot {
    private func resolvedMetadata(identity: String?) -> [Int: LibraryPlusMetadata] {
        var result = metadata
        let ids = Set(external.keys).union(manualConnections?.keys.map { $0 } ?? [])
        for id in ids {
            let primary = result[id] ?? LibraryPlusMetadata(summary: "", genres: [], tags: [])
            result[id] = LibraryPlusMetadata.resolved(primary: primary, external: external[id],
                                                      manual: manualConnections?[id])
        }
        if let identity {
            for item in catalog.sections.first(where: { $0.title == "All Series" })?.series ?? [] {
                let id = item.kavitaSeriesId
                let primary = result[id] ?? LibraryPlusMetadata(summary: "", genres: [], tags: [])
                let key = CustomSeriesCategoryStore.key(identity: identity, seriesID: String(id), isLocal: false)
                result[id] = CustomSeriesCategoryStore.applying(to: primary, key: key)
            }
        }
        return result
    }

    mutating func applyManualConnections(_ records: [Int: ManualSeriesMetadataRecord]) {
        let ids = Set(catalog.sections.first { $0.title == "All Series" }?.series.map(\.kavitaSeriesId) ?? [])
        let relevant = records.filter { ids.contains($0.key) }
        manualConnections = relevant
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        if let data = try? encoder.encode(relevant) {
            let revision = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            if manualConnectionRevision != revision { selection = nil }
            manualConnectionRevision = revision
        }
        for (id, record) in relevant {
            external[id] = record.metadata
        }
    }

    /// Used only for a new day/update or to migrate a legacy snapshot lacking selected IDs.
    mutating func prepareSelection(baseURL: URL?, apiKey: String,
                                   anchorHistory: [LibraryPlusAnchorRecord] = [], identity: String? = nil)
    {
        guard selection == nil else { return }
        let sections = catalog.domainSections(baseURL: baseURL, apiKey: apiKey)
        let series = sections.first { $0.title == "All Series" }?.series ?? []
        let continuing = catalog.domainContinueReading(baseURL: baseURL, apiKey: apiKey).map(\.series)
        let readingIDs = Set(sections.first { $0.title == "읽는 중" }?.items.compactMap(\.kavitaSeriesId) ?? [])
            .union(continuing.compactMap(\.kavitaSeriesId))
        let favouriteIDs = Set(sections.first { $0.title == "Favourite" }?.items.compactMap(\.kavitaSeriesId) ?? [])
        let curator = LibraryPlusCurator(series: series, metadata: resolvedMetadata(identity: identity), readingIDs: readingIDs,
                                         favouriteIDs: favouriteIDs,
                                         recent: sections.first { $0.title == "Recently Added" }?.series ?? [],
                                         day: day,
                                         anchorHistory: anchorHistory)
        let recommended = curator.recommended
        let recommendedIDs = Set(recommended.compactMap(\.kavitaSeriesId))
        let remaining = series.filter { !recommendedIDs.contains($0.kavitaSeriesId ?? 0) }
        let unread = curator.daily(remaining.filter { !$0.isRead })
        let completed = curator.daily(remaining.filter(\.isRead))
        let featured = Array((recommended + unread + completed).prefix(5))
        let rows = curator.rows(featured: featured, continuing: continuing)
        selection = LibraryPlusSelection(featuredIDs: featured.compactMap(\.kavitaSeriesId),
                                         rows: rows.map {
                                             LibraryPlusSelection.Row(id: $0.id, title: $0.title,
                                                                      seriesIDs: $0.items.compactMap(\.kavitaSeriesId),
                                                                      subtitle: $0.subtitle)
                                         }, hasRecommendations: !recommended.isEmpty,
                                         anchorSeriesId: rows.first { $0.id == "similar" }?.sourceSeriesId)
    }

    func presentation(baseURL: URL?, apiKey: String, identity: String? = nil) -> LibraryPlusPresentation {
        let catalogSeries = catalog.sections.first { $0.title == "All Series" }?.series ?? []
        let selectedIDs = Set((selection?.featuredIDs ?? []) + (selection?.rows.flatMap(\.seriesIDs) ?? []))
        var seriesByID: [Int: LibrarySeries] = [:]
        // Rebuild cover URLs only for the few selected works, once when installing a snapshot.
        for item in catalogSeries where selectedIDs.contains(item.kavitaSeriesId) {
            seriesByID[item.kavitaSeriesId] = item.toLibrarySeries(baseURL: baseURL, apiKey: apiKey)
        }
        let rows = (selection?.rows ?? []).map {
            LibraryPlusRow(id: $0.id, title: $0.title, items: $0.seriesIDs.compactMap { seriesByID[$0] },
                           subtitle: $0.subtitle)
        }
        let allMetadata = resolvedMetadata(identity: identity)
        let genreSeriesIDs = Dictionary(uniqueKeysWithValues: HomeGenre.allCases.map { genre in
            (genre, Set(catalogSeries.compactMap { item -> Int? in
                guard genre.matches(allMetadata[item.kavitaSeriesId]?.genres ?? []) else { return nil }
                return item.kavitaSeriesId
            }))
        })
        return LibraryPlusPresentation(featured: (selection?.featuredIDs ?? []).compactMap { seriesByID[$0] },
                                       rows: rows, metadata: allMetadata,
                                       favouriteIDs: Set(catalog.sections.first { $0.title == "Favourite" }?.series
                                           .map(\.kavitaSeriesId) ?? []),
                                       hasRecommendations: selection?.hasRecommendations ?? false,
                                       hasSeries: !catalogSeries.isEmpty, genreSeriesIDs: genreSeriesIDs)
    }
}

actor LibraryPlusDailyStore {
    // MARK: Lifecycle

    init(directory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("KavaReader/LibraryPlus", isDirectory: true))
    {
        self.directory = directory
    }

    // MARK: Internal

    static let shared = LibraryPlusDailyStore()

    func load(identity: String) -> LibraryPlusDailySnapshot? {
        guard let data = try? Data(contentsOf: fileURL(identity)) else { return nil }
        return try? JSONDecoder().decode(LibraryPlusDailySnapshot.self, from: data)
    }

    func loadAnchorHistory(identity: String) -> [LibraryPlusAnchorRecord] {
        var history: [LibraryPlusAnchorRecord] = []
        if let data = try? Data(contentsOf: historyURL(identity)),
           let saved = try? JSONDecoder().decode([LibraryPlusAnchorRecord].self, from: data)
        {
            history = saved
        }
        // Recover the last shown anchor from older daily files that had no history.
        if let snapshot = load(identity: identity), let id = anchorID(in: snapshot) {
            let record = LibraryPlusAnchorRecord(day: snapshot.day, seriesId: id)
            if !history.contains(record) { history.append(record) }
        }
        return history
    }

    func save(_ snapshot: LibraryPlusDailySnapshot, identity: String) throws {
        var history = loadAnchorHistory(identity: identity)
        if let id = anchorID(in: snapshot) {
            let record = LibraryPlusAnchorRecord(day: snapshot.day, seriesId: id)
            if !history.contains(record) { history.append(record) }
        }
        history = history.filter { (snapshot.day - 30 ... snapshot.day).contains($0.day) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Keep history even if a same-day Settings update replaces today's selection.
        try JSONEncoder().encode(history).write(to: historyURL(identity), options: .atomic)
        try JSONEncoder().encode(snapshot).write(to: fileURL(identity), options: .atomic)
    }

    // MARK: Private

    private let directory: URL

    private func anchorID(in snapshot: LibraryPlusDailySnapshot) -> Int? {
        if let id = snapshot.selection?.anchorSeriesId { return id }
        guard let title = snapshot.selection?.rows.first(where: { $0.id == "similar" })?.subtitle else { return nil }
        let matches = snapshot.catalog.sections.first(where: { $0.title == "All Series" })?.series
            .filter { $0.title == title } ?? []
        return matches.count == 1 ? matches.first?.kavitaSeriesId : nil
    }

    private func historyURL(_ identity: String) -> URL {
        let hash = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
#if DEBUG
        return directory.appendingPathComponent(hash + "-anchors-debug.json")
#else
        return directory.appendingPathComponent(hash + "-anchors.json")
#endif
    }

    private func fileURL(_ identity: String) -> URL {
        let hash = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
#if DEBUG
        return directory.appendingPathComponent(hash + "-daily-debug.json")
#else
        return directory.appendingPathComponent(hash + "-daily.json")
#endif
    }
}

/// Only the Settings catalog update changes this persisted, account-scoped revision.
enum LibraryPlusRevision {
    // MARK: Internal

    static func current(identity: String) -> String {
        UserDefaults.standard.string(forKey: key(identity)) ?? "initial"
    }

    static func advance(identity: String) -> String {
        let revision = UUID().uuidString
        UserDefaults.standard.set(revision, forKey: key(identity))
        return revision
    }

    // MARK: Private

    private static func key(_ identity: String) -> String {
        let hash = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
        return "library_plus_revision_" + hash
    }
}

@MainActor
final class LibraryPlusDiagnostics: ObservableObject {
    @Published var completedCount: Int = 0
    @Published var totalCount: Int = 0
    @Published var failedCount: Int = 0
    @Published var isLoading: Bool = false
    @Published var isEnriching: Bool = false
    @Published var externalTotalCount: Int = 0
    @Published var externalCompletedCount: Int = 0
    @Published var externalLookupCount: Int = 0
    @Published var externalFailedCount: Int = 0
    @Published var externalRateLimited: Bool = false
    @Published var externalDeferredCount: Int = 0
}

@MainActor
final class LibraryPlusViewModel: ObservableObject {
    // MARK: Lifecycle

    init(dailyStore: LibraryPlusDailyStore = .shared, localStore: LocalComicStore = .shared,
         localExternalStore: LocalSeriesMetadataStore = .shared)
    {
        self.dailyStore = dailyStore
        self.localStore = localStore
        self.localExternalStore = localExternalStore
        indexingSettingsObserver = NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let enabled = IndexingSettings.alternateTitleSearchEnabled
                    guard enabled != self.lastAlternateSearchEnabled else { return }
                    self.lastAlternateSearchEnabled = enabled
                    self.prepareLocalMetadata(force: true)
                }
            }
        connectionObserver = NotificationCenter.default.publisher(for: .seriesMetadataConnectionDidChange)
            .sink { [weak self] notification in
                guard let identity = notification.object as? String else { return }
                Task { @MainActor [weak self] in
                    if identity == LocalSeriesMetadataStore.notificationIdentity {
                        self?.prepareLocalMetadata(force: true)
                    } else {
                        await self?.reloadManualConnections(identity: identity)
                    }
                }
            }
        customCategoryObserver = NotificationCenter.default.publisher(for: CustomSeriesCategoryStore.didChange)
            .sink { [weak self] notification in
                guard let identity = notification.object as? String else { return }
                Task { @MainActor [weak self] in
                    if identity == LocalSeriesMetadataStore.notificationIdentity {
                        self?.prepareLocalMetadata(force: true)
                    } else {
                        await self?.reloadManualConnections(identity: identity)
                    }
                }
            }
    }

    // MARK: Internal

    @Published private(set) var dailyMetadataRevision = 0
    @Published private(set) var dailyPresentation: LibraryPlusPresentation?
    @Published private(set) var dailySnapshot: LibraryPlusDailySnapshot?
    @Published private(set) var isPreparingDaily = false
    @Published private(set) var localMetadata: [UUID: LibraryPlusMetadata] = [:]
    @Published private(set) var localMetadataRevision = 0
    let localDiagnostics = LibraryPlusDiagnostics()
    private(set) var metadataByID: [Int: LibraryPlusMetadata] = [:]
    private(set) var externalByID: [Int: ExternalSeriesMetadata] = [:]
    let diagnostics = LibraryPlusDiagnostics()

    var availableGenres: [HomeGenre] {
        HomeGenre.allCases.filter { genre in
            !(dailyPresentation?.genreSeriesIDs[genre] ?? []).isEmpty ||
                localMetadata.values.contains { genre.matches($0.genres) }
        }
    }

    /// Use the same membership for genre navigation and development counts.
    func series(in genre: HomeGenre, catalog: [LibrarySeries]) -> [LibrarySeries] {
        let ids = dailyPresentation?.genreSeriesIDs[genre] ?? []
        return catalog.filter { item in
            item.isLocal ? genre.matches(localMetadata[item.id]?.genres ?? []) :
                (item.kavitaSeriesId.map(ids.contains) ?? false)
        }
    }

    private(set) var completedCount: Int {
        get { diagnostics.completedCount }
        set { diagnostics.completedCount = newValue }
    }

    private(set) var totalCount: Int {
        get { diagnostics.totalCount }
        set { diagnostics.totalCount = newValue }
    }

    private(set) var failedCount: Int {
        get { diagnostics.failedCount }
        set { diagnostics.failedCount = newValue }
    }

    private(set) var isLoading: Bool {
        get { diagnostics.isLoading }
        set { diagnostics.isLoading = newValue }
    }

    private(set) var isEnriching: Bool {
        get { diagnostics.isEnriching }
        set { diagnostics.isEnriching = newValue }
    }

    private(set) var externalLookupCount: Int {
        get { diagnostics.externalLookupCount }
        set { diagnostics.externalLookupCount = newValue }
    }

    private(set) var externalFailedCount: Int {
        get { diagnostics.externalFailedCount }
        set { diagnostics.externalFailedCount = newValue }
    }

    private(set) var externalRateLimited: Bool {
        get { diagnostics.externalRateLimited }
        set { diagnostics.externalRateLimited = newValue }
    }

    private(set) var externalDeferredCount: Int {
        get { diagnostics.externalDeferredCount }
        set { diagnostics.externalDeferredCount = newValue }
    }

    /// The model owns indexing even when the user switches tabs or dismisses the importer.
    @discardableResult
    func prepareLocalMetadata(force: Bool = false) -> Task<Void, Never> {
        Task { [weak self] in
            guard let self, let comics = try? await self.localStore.all() else { return }
            let key = Self.localKey(comics)
            // Reading progress/favourite notifications do not restart indexing.
            guard force || self.localMetadataKey != key else { return }
            self.localMetadataKey = key
            self.localMetadataTask?.cancel()
            let run = UUID()
            self.localMetadataRun = run
            let status = self.localDiagnostics
            status.completedCount = 0
            status.totalCount = comics.count
            status.failedCount = 0
            status.externalTotalCount = 0
            status.externalCompletedCount = 0
            status.externalLookupCount = 0
            status.externalFailedCount = 0
            status.externalDeferredCount = 0
            status.externalRateLimited = false
            status.isEnriching = false
            status.isLoading = !comics.isEmpty
            let task = Task<Void, Never> { [weak self] in
                guard let self else { return }
                await self.loadLocalMetadata(run: run)
            }
            self.localMetadataTask = task
            await task.value
        }
    }

    func selectIdentity(_ identity: String) {
        guard dailyIdentity != identity else { return }
        dailyTask?.cancel()
        dailyTask = nil
        dailyIdentity = identity
        dailyBaseURL = nil
        dailyAPIKey = ""
        manualReloadID = UUID()
        dailyRequestKey = nil
        activeLoadID = UUID()
        activeExternalID = UUID()
        dailySnapshot = nil
        dailyPresentation = nil
        metadataByID = [:]
        externalByID = [:]
        isLoading = false
        isEnriching = false
        isPreparingDaily = false
        failedCount = 0
        externalFailedCount = 0
        externalRateLimited = false
        externalDeferredCount = 0
    }

    func needsDailyPreparation(identity: String, day: Int, revision: String) -> Bool {
        dailyIdentity != identity || dailyRequestKey != "\(day)|\(revision)|\(IndexingSettings.alternateTitleSearchEnabled)"
    }

    /// The model owns this task: leaving the tab must not cancel or restart today's preparation.
    @discardableResult
    func prepareDaily(catalog: LibraryCatalogSnapshot, identity: String, baseURL: URL?, apiKey: String,
                      day: Int, revision: String, service: KavitaLibraryService) -> Task<Void, Never>?
    {
        selectIdentity(identity)
        dailyBaseURL = baseURL
        dailyAPIKey = apiKey
        let requestKey = "\(day)|\(revision)|\(IndexingSettings.alternateTitleSearchEnabled)"
        guard dailyRequestKey != requestKey else { return dailyTask }
        dailyTask?.cancel()
        dailyRequestKey = requestKey
        activeLoadID = UUID()
        activeExternalID = UUID()
        isLoading = false
        isEnriching = false
        failedCount = 0
        externalFailedCount = 0
        externalRateLimited = false
        externalDeferredCount = 0
        isPreparingDaily = true
        dailyTask = Task { [weak self] in
            guard let self else { return }
            let saved = await self.dailyStore.load(identity: identity)
            let anchorHistory = await self.dailyStore.loadAnchorHistory(identity: identity)
            guard self.isCurrentDaily(identity: identity, key: requestKey) else { return }
            let sections = catalog.domainSections(baseURL: baseURL, apiKey: apiKey)
            let series = sections.first { $0.title == "All Series" }?.series ?? []
            if var saved, saved.matches(day: day, revision: revision) {
                let automatic = await ExternalLookupStore.shared.load(identity: identity)
                let manual = await ManualSeriesMetadataStore.shared.load(identity: identity)
                guard self.isCurrentDaily(identity: identity, key: requestKey) else { return }
                saved.external = Dictionary(uniqueKeysWithValues: series.compactMap { item in
                    guard let id = item.kavitaSeriesId, let record = automatic.records[id],
                          record.isFresh(for: item.title, now: Date()), let match = record.match else { return nil }
                    return (id, match)
                })
                saved.applyManualConnections(manual)
                let needsMigration = saved.selection == nil
                saved.prepareSelection(baseURL: baseURL, apiKey: apiKey, anchorHistory: anchorHistory, identity: identity)
                self.install(saved, baseURL: baseURL, apiKey: apiKey)
                if needsMigration { try? await self.dailyStore.save(saved, identity: identity) }
            } else {
                // Freeze today's view using only information already on disk, before any requests.
                async let cachedKavita = LibraryPlusMetadataStore.shared.load(identity: identity)
                async let cachedExternal = ExternalLookupStore.shared.load(identity: identity)
                let kavita = await cachedKavita
                let externalSnapshot = await cachedExternal
                guard self.isCurrentDaily(identity: identity, key: requestKey) else { return }
                let ids = Set(series.compactMap(\.kavitaSeriesId))
                let external = Dictionary(uniqueKeysWithValues: series.compactMap { item -> (Int,
                                                                                             ExternalSeriesMetadata)? in
                        guard let id = item.kavitaSeriesId,
                              kavita[id]?.hasCategories != true,
                              let record = externalSnapshot.records[id],
                              record.isFresh(for: item.title, now: Date()), let match = record.match
                        else { return nil }
                        return (id, match)
                    })
                var snapshot = LibraryPlusDailySnapshot(day: day, revision: revision, catalog: catalog,
                                                        metadata: kavita.filter { ids.contains($0.key) },
                                                        external: external)
                let manual = await ManualSeriesMetadataStore.shared.load(identity: identity)
                guard self.isCurrentDaily(identity: identity, key: requestKey) else { return }
                snapshot.applyManualConnections(manual)
                snapshot.prepareSelection(baseURL: baseURL, apiKey: apiKey, anchorHistory: anchorHistory, identity: identity)
                self.install(snapshot, baseURL: baseURL, apiKey: apiKey)
                try? await self.dailyStore.save(snapshot, identity: identity)
            }
            guard self.isCurrentDaily(identity: identity, key: requestKey) else { return }
            self.isPreparingDaily = false

            // Keep the current home visible while indexing, then rebuild it from the collected metadata.
            let readingIDs = sections.first { $0.title == "읽는 중" }?.items.compactMap(\.kavitaSeriesId) ?? []
            let favouriteIDs = sections.first { $0.title == "Favourite" }?.items.compactMap(\.kavitaSeriesId) ?? []
            let force = revision != "initial" && saved?.revision != revision
            await self.load(series: series, identity: identity, service: service, force: force)
            guard self.isCurrentDaily(identity: identity, key: requestKey) else { return }
            await self.enrich(series: series, identity: identity,
                              priorityIDs: Set(readingIDs).union(favouriteIDs))
            guard self.isCurrentDaily(identity: identity, key: requestKey) else { return }

            // Refresh every part of the home together after both indexing stages finish.
            // Retain the request key so installing the result does not start indexing again.
            var refreshed = LibraryPlusDailySnapshot(day: day, revision: revision, catalog: catalog,
                                                     metadata: self.metadataByID, external: self.externalByID)
            let manual = await ManualSeriesMetadataStore.shared.load(identity: identity)
            guard self.isCurrentDaily(identity: identity, key: requestKey) else { return }
            refreshed.applyManualConnections(manual)
            refreshed.prepareSelection(baseURL: baseURL, apiKey: apiKey, anchorHistory: anchorHistory, identity: identity)
            self.install(refreshed, baseURL: baseURL, apiKey: apiKey)
            try? await self.dailyStore.save(refreshed, identity: identity)
        }
        return dailyTask
    }

    func load(series: [LibrarySeries], identity: String, service: KavitaLibraryService, force: Bool = false) async {
        let loadID = UUID()
        activeLoadID = loadID
        activeExternalID = UUID()
        isEnriching = false
        externalByID = [:]
        if currentIdentity != identity {
            metadataByID = [:]
            currentIdentity = identity
        }
        completedCount = 0
        totalCount = 0
        isLoading = true
        failedCount = 0

        let ids = Array(Set(series.filter { !$0.isLocal }.compactMap(\.kavitaSeriesId))).sorted()
        let allIDs = Set(ids)
        totalCount = ids.count

        let saved: [Int: LibraryPlusMetadata]
        if force {
            saved = [:]
        } else {
            saved = await LibraryPlusMetadataStore.shared.load(identity: identity)
        }
        guard activeLoadID == loadID, !Task.isCancelled else { return }
        metadataByID = saved.filter { allIDs.contains($0.key) }
        completedCount = metadataByID.count
        let missing = ids.filter { metadataByID[$0] == nil }

        await withTaskGroup(of: (Int, LibraryPlusMetadata?).self) { group in
            var pending = missing.makeIterator()
            for _ in 0 ..< min(4, missing.count) {
                if let id = pending.next() { Self.addFetch(id, service: service, to: &group) }
            }

            while let (id, metadata) = await group.next() {
                guard activeLoadID == loadID, !Task.isCancelled else {
                    group.cancelAll()
                    break
                }
                completedCount += 1
                if let metadata {
                    metadataByID[id] = metadata
                } else {
                    failedCount += 1
                }
                if completedCount % 8 == 0 {
                    try? await LibraryPlusMetadataStore.shared.save(metadataByID, identity: identity)
                }
                if let nextID = pending.next() { Self.addFetch(nextID, service: service, to: &group) }
            }
        }

        guard activeLoadID == loadID else { return }
        try? await LibraryPlusMetadataStore.shared.save(metadataByID, identity: identity)
        isLoading = false
    }

    /// Search only works with no Kavita genres or tags. A unique exact title/alias match is required.
    func enrich(series: [LibrarySeries], identity: String, priorityIDs: Set<Int>,
                service: AniListMetadataService = AniListMetadataService()) async
    {
        let loadID = UUID()
        activeExternalID = loadID
        isEnriching = true
        externalLookupCount = 0
        diagnostics.externalTotalCount = 0
        diagnostics.externalCompletedCount = 0
        externalFailedCount = 0
        externalRateLimited = false
        externalDeferredCount = 0

        let now = Date()
        let day = Calendar.current.ordinality(of: .day, in: .era, for: now) ?? 0
        var snapshot = await ExternalLookupStore.shared.load(identity: identity)
        let manual = await ManualSeriesMetadataStore.shared.load(identity: identity)
        guard activeExternalID == loadID, !Task.isCancelled else { return }
        if snapshot.dayKey != day {
            snapshot.dayKey = day
            snapshot.requestsToday = 0
        }

        let eligible = series.filter { item in
            guard !item.isLocal, let id = item.kavitaSeriesId, let kavita = metadataByID[id] else { return false }
            return !kavita.hasCategories
        }.sorted { lhs, rhs in
            let lhsPriority = lhs.kavitaSeriesId.map(priorityIDs.contains) ?? false
            let rhsPriority = rhs.kavitaSeriesId.map(priorityIDs.contains) ?? false
            return lhsPriority == rhsPriority
                ? (lhs.kavitaSeriesId ?? 0) > (rhs.kavitaSeriesId ?? 0)
                : lhsPriority
        }
        externalByID = Dictionary(uniqueKeysWithValues: eligible.compactMap { item in
            guard let id = item.kavitaSeriesId,
                  let record = snapshot.records[id], record.isFresh(for: item.title, now: now),
                  let match = record.match
            else { return nil }
            return (id, match)
        })
        let allIDs = Set(series.compactMap(\.kavitaSeriesId))
        for (id, record) in manual where allIDs.contains(id) {
            externalByID[id] = record.metadata
        }

        let unsearched = eligible.filter { item in
            guard let id = item.kavitaSeriesId else { return false }
            guard manual[id] == nil else { return false }
            return snapshot.records[id]?.isFresh(for: item.title, now: now,
                                                 alternateSearchEnabled: IndexingSettings
                                                     .alternateTitleSearchEnabled) !=
                true
        }
        diagnostics.externalTotalCount = unsearched.count
        externalDeferredCount = unsearched.count
        if let blockedUntil = snapshot.blockedUntil, blockedUntil > now {
            externalRateLimited = true
            isEnriching = false
            return
        }
        var nextRequestAt = Date()
        for (index, item) in unsearched.enumerated() {
            guard activeExternalID == loadID, !Task.isCancelled, let id = item.kavitaSeriesId else { break }
            let wait = nextRequestAt.timeIntervalSinceNow
            if wait > 0 {
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            }
            guard activeExternalID == loadID, !Task.isCancelled else { break }
            let currentManual = await ManualSeriesMetadataStore.shared.load(identity: identity)
            guard activeExternalID == loadID, !Task.isCancelled else { break }
            if let record = currentManual[id] {
                externalByID[id] = record.metadata
                diagnostics.externalCompletedCount += 1
                externalDeferredCount = unsearched.count - index - 1
                continue
            }
            nextRequestAt = Date().addingTimeInterval(2.5)
            externalLookupCount += 1
            do {
                let alternateSearch = IndexingSettings.alternateTitleSearchEnabled
                let match = try await service.lookup(title: item.title, retryWithEnglishTitle: alternateSearch)
                nextRequestAt = Date().addingTimeInterval(2.5)
                guard activeExternalID == loadID, !Task.isCancelled else { break }
                snapshot.requestsToday += 1
                snapshot.records[id] = ExternalLookupRecord(queriedTitle: item.title,
                                                            checkedAt: Date(), match: match,
                                                            alternateTitleSearchAttempted: alternateSearch)
                let latestManual = await ManualSeriesMetadataStore.shared.load(identity: identity)
                guard activeExternalID == loadID, !Task.isCancelled else { break }
                externalByID[id] = latestManual[id] != nil ? latestManual[id]?.metadata : match
            } catch let ExternalLookupError.rateLimited(retryAfter) {
                snapshot.requestsToday += 1
                snapshot.blockedUntil = Date().addingTimeInterval(retryAfter)
                externalRateLimited = true
                externalDeferredCount = unsearched.count - index
                try? await ExternalLookupStore.shared.save(snapshot, identity: identity)
                break
            } catch {
                externalFailedCount += 1
                externalDeferredCount = unsearched.count - index
                break
            }
            diagnostics.externalCompletedCount += 1
            externalDeferredCount = unsearched.count - index - 1
            try? await ExternalLookupStore.shared.save(snapshot, identity: identity)
        }
        guard activeExternalID == loadID else { return }
        isEnriching = false
    }

    // MARK: Private

    private var dailyIdentity: String?
    private var dailyRequestKey: String?
    private var dailyTask: Task<Void, Never>?
    private let dailyStore: LibraryPlusDailyStore
    private var connectionObserver: AnyCancellable?
    private var customCategoryObserver: AnyCancellable?
    private var indexingSettingsObserver: AnyCancellable?
    private var lastAlternateSearchEnabled = IndexingSettings.alternateTitleSearchEnabled
    private var manualReloadID = UUID()

    private let localStore: LocalComicStore
    private let localExternalStore: LocalSeriesMetadataStore
    private var localMetadataKey: String?
    private var localMetadataTask: Task<Void, Never>?
    private var localMetadataRun = UUID()

    private var dailyBaseURL: URL?
    private var dailyAPIKey = ""

    private var activeLoadID = UUID()
    private var activeExternalID = UUID()
    private var currentIdentity: String?

    private static func localKey(_ comics: [LocalComic]) -> String {
        comics.sorted { $0.id.uuidString < $1.id.uuidString }.map {
            "\($0.id)|\($0.title)|" + $0.volumes.map { "\($0.digest):\($0.metadataVersion ?? 0)" }
                .joined(separator: ",")
        }.joined(separator: "|")
    }

    private static func addFetch(_ id: Int, service: KavitaLibraryService,
                                 to group: inout TaskGroup<(Int, LibraryPlusMetadata?)>)
    {
        group.addTask {
            let metadata = try? await service.fetchSeriesMetadata(kavitaSeriesId: id)
            return (id, metadata)
        }
    }

    /// Rebuild from local caches only; editing one connection must not restart indexing.
    private func reloadManualConnections(identity: String) async {
        guard dailyIdentity == identity else { return }
        let reloadID = UUID()
        manualReloadID = reloadID
        let requestKey = dailyRequestKey
        async let automatic = ExternalLookupStore.shared.load(identity: identity)
        async let manual = ManualSeriesMetadataStore.shared.load(identity: identity)
        let automaticRecords = await automatic
        let manualRecords = await manual
        let history = await dailyStore.loadAnchorHistory(identity: identity)
        guard manualReloadID == reloadID, dailyIdentity == identity,
              dailyRequestKey == requestKey, var snapshot = dailySnapshot else { return }
        let series = snapshot.catalog.sections.first { $0.title == "All Series" }?.series ?? []
        snapshot.external = Dictionary(uniqueKeysWithValues: series.compactMap { item in
            guard let record = automaticRecords.records[item.kavitaSeriesId],
                  record.isFresh(for: item.title, now: Date()), let match = record.match else { return nil }
            return (item.kavitaSeriesId, match)
        })
        snapshot.applyManualConnections(manualRecords)
        externalByID = snapshot.external
        snapshot.selection = nil
        snapshot.prepareSelection(baseURL: dailyBaseURL, apiKey: dailyAPIKey, anchorHistory: history, identity: identity)
        install(snapshot, baseURL: dailyBaseURL, apiKey: dailyAPIKey)
        try? await dailyStore.save(snapshot, identity: identity)
    }

    private func loadLocalMetadata(run: UUID) async {
        let status = localDiagnostics
        defer {
            // Cancellation of an older import batch must not hide the replacement task's status.
            if localMetadataRun == run {
                status.isLoading = false
                status.isEnriching = false
            }
        }
        let comics: [LocalComic]
        do { comics = try await localStore.metadataCatalog() }
        catch {
            if localMetadataRun == run { status.failedCount = status.totalCount }
            return
        }
        guard !Task.isCancelled, localMetadataRun == run else { return }
        localMetadataKey = Self.localKey(comics)
        status.totalCount = comics.count
        var resolved: [UUID: LibraryPlusMetadata] = [:]
        var pending: [LocalComic] = []
        for comic in comics {
            let primary = comic.embeddedMetadata
            let saved = await localExternalStore.information(id: comic.id, title: comic.title)
            guard !Task.isCancelled, localMetadataRun == run else { return }
            resolved[comic.id] = .resolved(primary: primary, external: saved.external, manual: saved.manual)
            if let value = resolved[comic.id] {
                let key = CustomSeriesCategoryStore.key(identity: "", seriesID: comic.id.uuidString, isLocal: true)
                resolved[comic.id] = CustomSeriesCategoryStore.applying(to: value, key: key)
            }
            if !primary.hasCategories,
               await localExternalStore.needsLookup(id: comic.id, title: comic.title,
                                                    includeNovels: comic.volumes.contains { $0.epub != nil })
            {
                pending.append(comic)
            }
            guard !Task.isCancelled, localMetadataRun == run else { return }
            status.completedCount += 1
        }
        if localMetadata != resolved {
            localMetadata = resolved
            localMetadataRevision += 1
        }
        status.externalTotalCount = pending.count
        status.externalDeferredCount = pending.count
        status.isEnriching = !pending.isEmpty
        status.isLoading = false
        // Only uncached external lookups count in this stage; bulk imports retain completed results.
        for (index, comic) in pending.enumerated() {
            guard !Task.isCancelled, localMetadataRun == run else { return }
            do {
                status.externalLookupCount += 1
                let match = try await localExternalStore.lookup(id: comic.id, title: comic.title,
                                                                includeNovels: comic.volumes
                                                                    .contains { $0.epub != nil })
                guard !Task.isCancelled, localMetadataRun == run else { return }
                let latest = await localExternalStore.information(id: comic.id, title: comic.title)
                guard !Task.isCancelled, localMetadataRun == run else { return }
                var value = LibraryPlusMetadata.resolved(primary: comic.embeddedMetadata, external: match,
                                                         manual: latest.manual)
                let key = CustomSeriesCategoryStore.key(identity: "", seriesID: comic.id.uuidString, isLocal: true)
                value = CustomSeriesCategoryStore.applying(to: value, key: key)
                if localMetadata[comic.id] != value {
                    localMetadata[comic.id] = value
                    localMetadataRevision += 1
                }
                status.externalCompletedCount += 1
                status.externalDeferredCount = pending.count - index - 1
            } catch is CancellationError { return }
            catch ExternalLookupError.rateLimited {
                guard localMetadataRun == run else { return }
                status.externalRateLimited = true
                break
            } catch {
                guard localMetadataRun == run else { return }
                status.externalFailedCount += 1
                break // Retry later; communication failures are not confirmed title misses.
            }
        }
    }

    private func install(_ snapshot: LibraryPlusDailySnapshot, baseURL: URL?, apiKey: String) {
        dailyPresentation = snapshot.presentation(baseURL: baseURL, apiKey: apiKey, identity: dailyIdentity)
        dailySnapshot = snapshot
        dailyMetadataRevision += 1
    }

    private func isCurrentDaily(identity: String, key: String) -> Bool {
        !Task.isCancelled && dailyIdentity == identity && dailyRequestKey == key
    }
}
