import Combine
import CryptoKit
import Foundation
import ImageIO
import SwiftUI
import UIKit

/// A shared home curated from metadata belonging to each source.
struct LibraryPlusView: View {
    // MARK: Internal

    let isActive: Bool
    let openFiles: () -> Void
    let openServerSettings: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 30) {
                    if !featuredSeries.isEmpty { featuredCarousel }
                    // Reading progress is live; it must not depend on the daily recommendation cache.
                    if !library.continueReadingItems.isEmpty { continueReadingSection }
                    if !hasLibrarySeries && library.continueReadingItems.isEmpty {
                        emptyState
                    } else if !library.localSeries.isEmpty {
                        recommendationSections
                    } else if metadata.dailySnapshot == nil && metadata.isPreparingDaily {
                        ProgressView(AppLocalization.text("홈을 준비하고 있어요"))
                            .frame(maxWidth: .infinity, minHeight: 280)
                    } else {
                        recommendationSections
                    }
                    LibraryIndexingStatus(diagnostics: metadata.diagnostics)
                    LibraryIndexingStatus(diagnostics: metadata.localDiagnostics)
                }
                .padding(.vertical, 20)
            }
            .background(AppTheme.background)
            .onScrollPhaseChange { _, phase in
                let wasScrolling = isHomeScrolling
                isHomeScrolling = phase == .interacting || phase == .decelerating || phase == .animating
                if isHomeScrolling || wasScrolling { lastHomeScrollTime = Date() }
            }
            .onGeometryChange(for: CGSize.self) { geometry in
                geometry.size
            } action: { size in
                viewportWidth = size.width
                viewportHeight = size.height
            }
            .navigationTitle("홈")
            .navigationBarTitleDisplayMode(.inline)
#if DEBUG
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    AppGlassActionButton(title: nil, systemImage: "chart.bar.xaxis",
                                         size: CGSize(width: 44, height: 44),
                                         isEnabled: true, isHighlighted: false, variant: .standard,
                                         accessibilityLabel: AppLocalization.text("개발용 장르 데이터"))
                    {
                        showGenreDiagnostics = true
                    }
                    .frame(width: 44, height: 44)
                }
                .sharedBackgroundVisibility(.hidden)
            }
            .sheet(isPresented: $showGenreDiagnostics) {
                HomeGenreDiagnosticsSheet()
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
#endif
            .navigationDestination(item: $selectedGenre) { genre in
                HomeGenreDetailView(genre: genre)
            }
            .navigationDestination(for: LibrarySeries.self) { series in
                SeriesDetailView(series: series,
                                 initialWantToRead: library.isFavourite(series))
            }
        }
        .task(id: mixedContentSignature) { rebuildMixedHome() }
        .task(id: dayKey) {
            try? await FeaturedPreviewCache.shared.removeExpired()
            metadata.prepareLocalMetadata(force: true)
        }
        .task(id: loadSignature) {
            updateDay()
            prepareDaily()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                updateDay()
                prepareDaily()
                metadata.prepareLocalMetadata(force: true)
            }
        }
        .onReceive(carouselTimer) { _ in
            updateDay()
            guard isActive, scenePhase == .active, !reduceMotion, !voiceOverEnabled,
                  featuredSeries.count > 1, featuredSeries.indices.contains(featuredIndex) else { return }
            withAnimation(.easeInOut(duration: 0.45)) {
                featuredIndex += 1
            }
        }
        .onChange(of: featuredSeries.map(\.id)) { _, _ in featuredIndex = 0 }
    }

    // MARK: Private

    @AppStorage(GeneralSettings.homeItemsPerRowKey) private var homeItemsPerRow = GeneralSettings.defaultItemsPerRow
    @AppStorage(IndexingSettings.alternateTitleSearchKey) private var alternateTitleSearch = false
    @State private var viewportWidth: CGFloat = 0
    @State private var viewportHeight: CGFloat = 0
    @State private var selectedGenre: HomeGenre?
    @State private var isHomeScrolling = false
    @State private var lastHomeScrollTime = Date.distantPast
    @State private var isGenreScrolling = false
    @State private var lastGenreScrollTime = Date.distantPast
#if DEBUG
    @State private var showGenreDiagnostics = false
#endif

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @EnvironmentObject private var library: LibraryViewModel
    @AppStorage("server_base_url") private var serverBaseURL = ""
    @AppStorage(KavitaCredentials.revisionKey) private var credentialRevision = 0
    @EnvironmentObject private var metadata: LibraryPlusViewModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var featuredIndex = 0
    @State private var mixedFeatured: [LibrarySeries] = []
    @State private var mixedRows: [LibraryPlusRow] = []
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @ScaledMetric(relativeTo: .body) private var compactFeaturedHeight: CGFloat = 240
    @ScaledMetric(relativeTo: .body) private var wideFeaturedHeight: CGFloat = 280

    @State private var dayKey = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0

    private let carouselTimer = Timer.publish(every: 6, on: .main, in: .common).autoconnect()

    private var shelfCoverWidth: CGFloat {
        guard viewportWidth > 0 else { return 128 }
        let count = CGFloat(GeneralSettings.itemsPerRow(homeItemsPerRow))
        return max(1, (viewportWidth - 48 - 14 * (count - 1)) / count)
    }

    private var apiKey: String {
        _ = credentialRevision
        return KavitaCredentials.read(server: serverBaseURL, field: "apiKey")
    }

    private var featuredPanelHeight: CGFloat {
        horizontalSizeClass == .regular ? wideFeaturedHeight : compactFeaturedHeight
    }

    private var favouriteIDs: Set<Int> { metadata.dailyPresentation?.favouriteIDs ?? [] }
    private var readingIDs: Set<Int> {
        Set(library.sections.first(where: { $0.title == "읽는 중" })?.items.compactMap(\.kavitaSeriesId) ?? [])
    }

    private var loadSignature: String {
        "\(alternateTitleSearch)|\(isActive)|\(dayKey)|\(serverBaseURL)|\(apiKey)|\(library.libraryPlusRevision)|\(library.hasCatalog(identity: "\(serverBaseURL)|\(apiKey)"))"
    }

    // Daily selections stay fixed, but completed works must disappear as soon as
    // the shared catalog receives a read-state change.
    private var completedSeriesIDs: Set<Int> {
        Set(library.sections.first(where: { $0.title == "All Series" })?.items
            .filter(\.isRead).compactMap(\.kavitaSeriesId) ?? [])
    }

    private var featuredSeries: [LibrarySeries] {
        if !library.localSeries.isEmpty { return mixedFeatured }
        let completedIDs = completedSeriesIDs
        let server = (metadata.dailyPresentation?.featured ?? []).filter {
            !($0.kavitaSeriesId.map(completedIDs.contains) ?? $0.isRead)
        }
        return server
    }

    private var featuredPageIndices: [Int] {
        featuredSeries.count > 1 ? Array(-1 ... featuredSeries.count) : Array(featuredSeries.indices)
    }

    private var visibleFeaturedIndex: Int {
        guard !featuredSeries.isEmpty else { return 0 }
        return (featuredIndex + featuredSeries.count) % featuredSeries.count
    }

    private var rows: [LibraryPlusRow] {
        if !library.localSeries.isEmpty { return mixedRows }
        let completedIDs = completedSeriesIDs
        return (metadata.dailyPresentation?.rows ?? []).compactMap { row in
            let items = row.items.filter {
                !($0.kavitaSeriesId.map(completedIDs.contains) ?? $0.isRead)
            }
            guard !items.isEmpty else { return nil }
            return LibraryPlusRow(id: row.id, title: row.title, items: items,
                                  subtitle: row.subtitle, sourceSeriesId: row.sourceSeriesId)
        }
    }

    private var mixedContentSignature: String {
        let presentation = metadata.dailyPresentation
        let selection = (presentation?.featured.map(\.id) ?? []).map(\.uuidString).joined() +
            (presentation?.rows.map { $0.id + $0.items.map { $0.id.uuidString }.joined() } ?? []).joined()
        return "\(dayKey)|\(library.catalogRevision)|\(metadata.localMetadataRevision)|\(metadata.dailyMetadataRevision)|\(selection)"
    }

    private var hasLibrarySeries: Bool {
        !library.localSeries.isEmpty || library.sections.contains { section in
            section.items.contains { $0.kavitaSeriesId != nil }
        }
    }

    private var emptyStateCopy: (title: String, message: String, symbol: String) {
        if library.isRefreshing {
            return ("작품 목록을 불러오고 있어요", "잠시만 기다려 주세요.", "arrow.triangle.2.circlepath")
        }
        if serverBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return ("첫 작품을 추가해 보세요", "기기의 파일을 가져오거나 Kavita 서버를 연결해 읽을 수 있어요.", "books.vertical")
        }
        if library.errorMessage != nil {
            return ("라이브러리를 확인해 주세요", "서버 설정에서 연결 상태를 확인하고 라이브러리를 다시 업데이트해 주세요.", "exclamationmark.triangle")
        }
        if library.lastUpdatedAt == nil {
            return ("서버의 작품 목록을 불러오세요", "서버 설정에서 라이브러리를 업데이트하거나 기기의 파일을 가져올 수 있어요.", "server.rack")
        }
        return ("서버에서 작품을 찾지 못했어요", "서버에 작품을 추가한 뒤 라이브러리를 업데이트하거나 기기의 파일을 가져와 주세요.", "books.vertical")
    }

    @ViewBuilder
    private var recommendationSections: some View {
        let visibleRows = rows
        ForEach(Array(visibleRows.enumerated()), id: \.element.id) { index, row in
            LibraryPlusCarousel(row: row, readingIDs: readingIDs, coverWidth: shelfCoverWidth)
            if index == 1 { genreSection }
        }
        if visibleRows.count < 2 { genreSection }
        readTagSection
    }

    @ViewBuilder
    private var readTagSection: some View {
        let tags = HomeReadTag.ranked(
            catalog: library.sections.first { $0.title == "All Series" }?.series ?? [],
            serverMetadata: metadata.dailyPresentation?.metadata ?? [:],
            localMetadata: metadata.localMetadata
        )
        if !tags.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Text("자주 읽은 태그")
                    .font(.title2.weight(.semibold))
                    .padding(.horizontal, 24)
                HomeReadTagCarousel(tags: tags, isActive: isActive, canNavigate: { canOpenHomeCategory })
            }
            .padding(.bottom, 32)
        }
    }

    private var genreSection: some View {
        let availableGenres = metadata.availableGenres
        return Group {
            if !availableGenres.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    Text("장르 둘러보기")
                        .font(.title2.weight(.semibold))
                        .padding(.horizontal, 24)
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 14) {
                            ForEach(availableGenres) { genre in
                                Button {
                                    guard canOpenHomeCategory else { return }
                                    selectedGenre = genre
                                } label: {
                                    HomeGenreCard(genre: genre)
                                        .frame(width: UIDevice.current.userInterfaceIdiom == .phone
                                               ? max(1, (viewportWidth - 48 - 14) / 2) : 223)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 24)
                    }
                    .onScrollPhaseChange { _, phase in
                        let wasScrolling = isGenreScrolling
                        isGenreScrolling = phase == .interacting || phase == .decelerating || phase == .animating
                        if isGenreScrolling || wasScrolling { lastGenreScrollTime = Date() }
                    }
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 4)
                            .onChanged { _ in lastGenreScrollTime = Date() }
                            .onEnded { _ in lastGenreScrollTime = Date() }
                    )
                }
            }
        }
    }

    private var canOpenHomeCategory: Bool {
        !isHomeScrolling && !isGenreScrolling &&
            Date().timeIntervalSince(lastHomeScrollTime) > 0.25 &&
            Date().timeIntervalSince(lastGenreScrollTime) > 0.25
    }

    private var continueReadingSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("이어서 읽기")
                .font(.title2.weight(.semibold))
                .padding(.horizontal, 24)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    ForEach(library.continueReadingItems) { item in
                        NavigationLink(value: item.series) {
                            LibraryShelfCoverView(series: item.series, isReading: true, width: shelfCoverWidth)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(item.series.title)
                    }
                }
                .padding(.horizontal, 24)
            }
        }
    }

    private var emptyState: some View {
        let copy = emptyStateCopy
        return VStack(spacing: 12) {
            Image(systemName: copy.symbol)
                .font(.largeTitle)
                .foregroundStyle(AppTheme.accent)
                .accessibilityHidden(true)
            Text(AppLocalization.text(copy.title))
                .font(.headline)
            Text(AppLocalization.text(copy.message))
                .font(.subheadline)
                .foregroundStyle(AppTheme.secondaryText)
            if library.isRefreshing {
                ProgressView()
            } else if !serverBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      let error = library.errorMessage
            {
                Text(AppLocalization.text(error))
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            VStack(spacing: 12) {
                emptyStateButton(title: "파일 가져오기", symbol: "folder.badge.plus",
                                 variant: .primary, action: openFiles)
                emptyStateButton(title: "서버 연결하기", symbol: "server.rack",
                                 variant: .standard, action: openServerSettings)
            }
            .padding(.top, 12)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: 440, minHeight: 280)
        .padding(.top, min(160, max(24, viewportHeight * 0.16)))
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
    }

    private var featuredCarousel: some View {
        VStack(alignment: .leading, spacing: 16) {
            GeometryReader { geometry in
                TabView(selection: $featuredIndex) {
                    ForEach(featuredPageIndices, id: \.self) { index in
                        let seriesIndex = (index + featuredSeries.count) % featuredSeries.count
                        let series = featuredSeries[seriesIndex]
                        LibraryPlusFeaturedCard(series: series,
                                                details: details(for: series),
                                                isWide: geometry.size.width >= 600,
                                                panelHeight: featuredPanelHeight,
                                                previewDay: dayKey,
                                                isPreviewActive: isActive && scenePhase == .active && featuredIndex ==
                                                    index)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 2)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .task(id: featuredIndex) {
                    let count = featuredSeries.count
                    let boundaryIndex = featuredIndex
                    guard count > 1, boundaryIndex == -1 || boundaryIndex == count else { return }
                    // Let the swipe settle on an identical boundary page before resetting.
                    do {
                        try await Task.sleep(for: .milliseconds(500))
                    } catch { return }
                    guard featuredSeries.count == count, featuredIndex == boundaryIndex else { return }
                    var transaction = Transaction(animation: nil)
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        featuredIndex = boundaryIndex == -1 ? count - 1 : 0
                    }
                }
            }
            .frame(height: featuredPanelHeight + 4)
            .accessibilityLabel("오늘의 발견")

            if featuredSeries.count > 1 {
                HStack(spacing: 6) {
                    ForEach(Array(featuredSeries.indices), id: \.self) { index in
                        Capsule()
                            .fill(index == visibleFeaturedIndex ? AppTheme.accent : Color.white.opacity(0.2))
                            .frame(width: index == visibleFeaturedIndex ? 22 : 6, height: 6)
                    }
                }
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)
            }
        }
    }

    private func emptyStateButton(title: String, symbol: String,
                                  variant: AppGlassButtonVariant, action: @escaping () -> Void) -> some View
    {
        AppGlassActionButton(title: AppLocalization.text(title), systemImage: symbol,
                             size: CGSize(width: 200, height: 48), isEnabled: true,
                             isHighlighted: false, variant: variant, expandsToFitTitle: true,
                             accessibilityLabel: AppLocalization.text(title), action: action)
            .fixedSize(horizontal: true, vertical: false)
            .frame(height: 48)
    }

    private func details(for series: LibrarySeries) -> LibraryPlusMetadata? {
        if series.isLocal { return metadata.localMetadata[series.id] }
        return series.kavitaSeriesId.flatMap { metadata.dailyPresentation?.metadata[$0] }
    }

    private func rebuildMixedHome() {
        guard !library.localSeries.isEmpty else { mixedFeatured = []; mixedRows = []; return }
        let all = library.sections.first { $0.title == "All Series" }?.series ?? []
        let continuing = library.continueReadingItems.map(\.series)
        let reading = Set(continuing.map(\.id))
            .union(library.sections.first { $0.title == "읽는 중" }?.series.map(\.id) ?? [
            ])
        let favourites = library.sections.first { $0.title == "Favourite" }?.series ?? []
        let curator = LibraryPlusCurator(series: all, metadata: metadata.dailyPresentation?.metadata ?? [:],
                                         readingIDs: Set(all.filter { reading.contains($0.id) }
                                             .compactMap(\.kavitaSeriesId)),
                                         favouriteIDs: Set(favourites.compactMap(\.kavitaSeriesId)),
                                         recent: library.sections.first { $0.title == "Recently Added" }?.series ?? [],
                                         day: dayKey,
                                         localMetadata: metadata.localMetadata, localReadingIDs: reading,
                                         localFavouriteIDs: Set(favourites.map(\.id)))
        let recommended = curator.recommended
        let recommendedIDs = Set(recommended.map(\.id))
        let remaining = curator
            .daily(all.filter { !$0.isRead && !reading.contains($0.id) && !recommendedIDs.contains($0.id) })
        mixedFeatured = Array((recommended + remaining).prefix(6))
        mixedRows = curator.rows(featured: mixedFeatured, continuing: continuing)
        // Small libraries still get a useful shelf before enough works exist for themed rows.
        if mixedRows.isEmpty, !remaining.isEmpty {
            mixedRows = [LibraryPlusRow(id: "discovery", title: "오늘 시작해 볼 작품", items: Array(remaining.prefix(12)))]
        }
    }

    private func updateDay() {
        let currentDay = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? dayKey
        if currentDay != dayKey { dayKey = currentDay }
    }

    private func prepareDaily() {
        let identity = "\(serverBaseURL)|\(apiKey)"
        metadata.selectIdentity(identity)
        guard isActive, library.hasCatalog(identity: identity),
              metadata.needsDailyPreparation(identity: identity, day: dayKey, revision: library.libraryPlusRevision),
              let service = LibraryServiceFactory(baseURLString: serverBaseURL,
                                                  apiKey: apiKey.isEmpty ? nil : apiKey).makeService()
              as? KavitaLibraryService
        else { return }
        metadata.prepareDaily(catalog: LibraryCatalogSnapshot(sections: library.sections,
                                                              continueReading: library.continueReadingItems),
                              identity: identity, baseURL: URL(string: serverBaseURL), apiKey: apiKey,
                              day: dayKey, revision: library.libraryPlusRevision, service: service)
    }
}

/// A cover-led daily pick that adapts to the available window width.
private struct LibraryPlusFeaturedCard: View {
    let series: LibrarySeries
    let details: LibraryPlusMetadata?
    let isWide: Bool
    let panelHeight: CGFloat
    let previewDay: Int
    let isPreviewActive: Bool

    @AppStorage("server_base_url") private var serverBaseURL = ""
    @AppStorage(KavitaCredentials.revisionKey) private var credentialRevision = 0
    private var apiKey: String {
        _ = credentialRevision
        return KavitaCredentials.read(server: serverBaseURL, field: "apiKey")
    }

    @State private var previewPages: [FeaturedPreviewPage] = []
    @State private var previewIdentity: String?
    @AppStorage(AppLanguage.storageKey) private var selectedLanguage = AppLanguage.korean.rawValue

    private var accountIdentity: String { "\(serverBaseURL)|\(apiKey)" }
    private var previewLoadSignature: String {
        "\(accountIdentity)|\(series.kavitaSeriesId ?? 0)|\(previewDay)|\(isPreviewActive)"
    }

    private let coverOverhang: CGFloat = 16
    private var panelPadding: CGFloat { isWide ? 28 : 20 }
    private var coverWidth: CGFloat { (panelHeight - panelPadding + coverOverhang) / 1.5 }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var coverColors: [Color] {
        let primary = series.coverColorHexes.first.flatMap(Color.init(hex:)) ?? AppTheme.accentFill
        // Older catalogs appended the server's secondary color after a fallback.
        let secondary = series.coverColorHexes.count > 1
            ? series.coverColorHexes.last.flatMap(Color.init(hex:)) : nil
        return [primary, secondary ?? AppTheme.surface]
    }

    var body: some View {
        NavigationLink(value: series) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(AppTheme.surface)
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(LinearGradient(colors: coverColors.map { $0.opacity(0.4) },
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                    }
                    .frame(height: panelHeight)

                if UIDevice.current.userInterfaceIdiom == .phone {
                    phonePanel
                } else if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 16) {
                        cover(width: 80)
                        title
                        categoryLabel
                        introduction
                        Spacer(minLength: 0)
                        viewSeriesLabel
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .layoutPriority(2)
                    }
                    .padding(panelPadding)
                    .frame(height: panelHeight)
                } else {
                    // Keep the cover's position; the panel clips its lower edge.
                    cover(width: coverWidth)
                        .padding(.leading, panelPadding)
                        .padding(.top, panelPadding)

                    VStack(alignment: .leading, spacing: 12) {
                        title
                            .layoutPriority(2)
                        categoryLabel
                            .layoutPriority(1)
                        ViewThatFits(in: .vertical) {
                            introduction
                            Color.clear.frame(height: 0)
                        }
                        Spacer(minLength: 0)
                        viewSeriesLabel
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .layoutPriority(2)
                    }
                    .padding(.leading, panelPadding + coverWidth + (isWide ? 68 : 44))
                    .padding(.trailing, panelPadding)
                    .padding(.vertical, panelPadding)
                    .frame(height: panelHeight)
                }
            }
            .frame(height: panelHeight, alignment: .topLeading)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .task(id: previewLoadSignature) { await loadPreviewPages() }
    }

    private var phonePanel: some View {
        GeometryReader { geometry in
            let availableWidth = max(1, geometry.size.width - panelPadding * 2)
            let mainCoverWidth = min(coverWidth, availableWidth)
            let pageSpread = max(0, (availableWidth - mainCoverWidth) / 2)
            ZStack(alignment: .bottomLeading) {
                // Keep the cover in front, unfolding the two pages underneath it.
                // Top and side margins remain; only the lower edge is clipped by the panel.
                cover(width: mainCoverWidth, pageSpread: pageSpread)
                    .padding(.leading, panelPadding)
                    .padding(.top, panelPadding)
                    .frame(width: geometry.size.width, height: panelHeight, alignment: .topLeading)

                LinearGradient(stops: [.init(color: .clear, location: 0),
                                       .init(color: .black.opacity(0.45), location: 0.45),
                                       .init(color: .black.opacity(0.9), location: 1)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: panelHeight * 0.65)

                VStack(alignment: .leading, spacing: 8) {
                    phoneGenreLabel
                    Text(series.title)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.leading)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
        }
        .frame(height: panelHeight)
    }

    @ViewBuilder
    private var phoneGenreLabel: some View {
        let genres = Array((details?.genres ?? []).prefix(2))
        if !genres.isEmpty {
            Text(genres.map {
                MetadataLocalization.displayName($0, language: AppLanguage(rawValue: selectedLanguage) ?? .korean)
            }.joined(separator: "  ·  "))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.black.opacity(0.35), in: Capsule())
        }
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(series.title)
                .font(isWide ? .largeTitle.weight(.bold) : .title2.weight(.bold))
                .foregroundStyle(AppTheme.text)
                .multilineTextAlignment(.leading)
                .lineLimit(isWide || dynamicTypeSize.isAccessibilitySize ? 3 : 2)
            if !series.author.isEmpty {
                Text(series.author)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
                    .lineLimit(isWide ? 2 : 1)
            }
        }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let summary = details?.summary, !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
                    .multilineTextAlignment(.leading)
                    .lineLimit(isWide ? 3 : 2)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var categoryLabel: some View {
        let categories = Array((details?.genres ?? []).prefix(2))
            + Array((details?.tags ?? []).prefix(3))
        if !categories.isEmpty {
            Text(categories.map {
                MetadataLocalization.displayName($0, language: AppLanguage(rawValue: selectedLanguage) ?? .korean)
            }.joined(separator: "  ·  "))
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.accent)
                .lineLimit(1)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var viewSeriesLabel: some View {
        Label("작품 보기", systemImage: "arrow.right")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .glassEffect(.regular.tint(AppTheme.accentFill), in: .capsule)
            .fixedSize()
    }

    private func cover(width: CGFloat, pageSpread: CGFloat? = nil) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach((0 ..< 2).reversed(), id: \.self) { index in
                ZStack {
                    Color.white
                    if let page = previewPages.first(where: { $0.slot == index }) {
                        Image(uiImage: page.image)
                            .resizable()
                            .scaledToFill()
                    }
                }
                .frame(width: width, height: width * 1.5)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(.black.opacity(0.15), lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.22), radius: 4, x: 2, y: 2)
                .offset(x: CGFloat(index + 1) * (pageSpread ?? (isWide ? 21 : 15)))
            }

            Group {
                if let url = series.coverURL {
                    CoverImageView(url: url, height: width * 1.5, cornerRadius: 10,
                                   gradientColors: coverColors)
                } else {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(LinearGradient(colors: coverColors,
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .overlay {
                            Image(systemName: "book.closed")
                                .font(.largeTitle)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                }
            }
            .frame(width: width, height: width * 1.5)
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 1)
            }
            .background(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.black)
                    .frame(width: width, height: width * 1.5)
                    .shadow(color: .black.opacity(0.65), radius: 8, x: 5, y: 2)
                    .frame(width: width + 32, height: width * 1.5, alignment: .leading)
                    .mask(alignment: .topLeading) {
                        // Include the space outside the rounded corners, while
                        // keeping the stronger shadow confined to the right edge.
                        ZStack(alignment: .topLeading) {
                            Rectangle()
                                .frame(width: width + 32, height: width * 1.5)
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .frame(width: width, height: width * 1.5)
                                .blendMode(.destinationOut)
                        }
                        .compositingGroup()
                        .mask(alignment: .trailing) {
                            Rectangle()
                                .frame(width: 42, height: width * 1.5)
                        }
                    }
                    .allowsHitTesting(false)
            }
        }
        .frame(width: width, height: width * 1.5)
        .shadow(color: .black.opacity(0.3), radius: 12, y: 8)
        .accessibilityHidden(true)
    }

    @MainActor
    private func loadPreviewPages() async {
        let identity = accountIdentity
        let contentIdentity = "\(identity)|\(series.kavitaSeriesId ?? 0)|\(previewDay)"
        let requestedAt = Date()
        if previewIdentity != contentIdentity {
            previewPages = []
            previewIdentity = contentIdentity
        }
        guard isPreviewActive, previewPages.count < 2, let seriesId = series.kavitaSeriesId,
              let service = LibraryServiceFactory(baseURLString: serverBaseURL,
                                                  apiKey: apiKey.isEmpty ? nil : apiKey).makeService()
              as? KavitaLibraryService
        else { return }

        do {
            var cached: CachedFeaturedPreview
            if let saved = try? await FeaturedPreviewCache.shared.load(identity: identity, seriesId: seriesId) {
                cached = saved
            } else {
                let detail: SeriesDetail
                if let saved = await ChapterCatalogStore.shared.load(identity: identity, seriesId: seriesId,
                                                                     baseURL: service.baseURL, apiKey: service.apiKey)
                {
                    detail = saved
                } else {
                    detail = try await service.fetchSeriesDetail(kavitaSeriesId: seriesId)
                }
                try Task.checkCancellation()
                guard let chapter = detail.chapters.first(where: { !$0.isSpecial && $0.pageCount > 0 })
                    ?? detail.chapters.first(where: { $0.pageCount > 0 }),
                    let chapterId = chapter.kavitaChapterId
                else { return }
                let pageNumbers = chapter.pageCount > 1 ? Array(2 ... min(3, chapter.pageCount)) : [1]
                cached = CachedFeaturedPreview(chapterId: chapterId, pageNumbers: pageNumbers, pages: [])
                try? await FeaturedPreviewCache.shared.save(cached, identity: identity, seriesId: seriesId,
                                                            requestedAt: requestedAt)
            }
            try Task.checkCancellation()
            guard accountIdentity == identity, previewIdentity == contentIdentity else { return }
            // Drop invalid images so only missing slots need another download.
            cached.pages.removeAll { UIImage(data: $0.imageData) == nil }
            previewPages = cached.pages.compactMap { page in
                UIImage(data: page.imageData).map {
                    FeaturedPreviewPage(slot: page.slot, pageNumber: page.pageNumber, image: $0)
                }
            }
            guard cached.pages.count < cached.pageNumbers.count else { return }
            // Daily thumbnails are the sole persistent cache for these requests.
            let configuration = URLSessionConfiguration.ephemeral
            configuration.urlCache = nil
            let fetcher = URLSessionPageImageFetcher(session: URLSession(configuration: configuration))
            defer { fetcher.session.invalidateAndCancel() }

            for (index, page) in cached.pageNumbers.enumerated() {
                try Task.checkCancellation()
                if cached.pages.contains(where: { $0.pageNumber == page }) { continue }
                do {
                    let url = try service.pageImageURL(kavitaChapterId: cached.chapterId, pageNumber: page)
                    let (data, response) = try await fetcher.fetchImage(from: url)
                    try Task.checkCancellation()
                    guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode),
                          let source = CGImageSourceCreateWithData(data as CFData, nil),
                          let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                              kCGImageSourceCreateThumbnailFromImageAlways: true,
                              kCGImageSourceCreateThumbnailWithTransform: true,
                              kCGImageSourceThumbnailMaxPixelSize: 600,
                          ] as CFDictionary)
                    else { continue }
                    let image = UIImage(cgImage: thumbnail)
                    guard let imageData = image.jpegData(compressionQuality: 0.85) else { continue }
                    cached.pages.append(CachedFeaturedPreviewPage(slot: index, pageNumber: page, imageData: imageData))
                    // Persist each completed slot, even if the carousel advances before the next one finishes.
                    try? await FeaturedPreviewCache.shared.save(cached, identity: identity, seriesId: seriesId,
                                                                requestedAt: requestedAt)
                    try Task.checkCancellation()
                    guard accountIdentity == identity, previewIdentity == contentIdentity else { return }
                    previewPages.append(FeaturedPreviewPage(slot: index, pageNumber: page, image: image))
                } catch {
                    try Task.checkCancellation()
                }
            }
        } catch {
            // Unloaded slots retain their white page placeholders.
        }
    }

    private struct FeaturedPreviewPage {
        let slot: Int
        let pageNumber: Int
        let image: UIImage
    }
}

struct LibraryPlusRow: Identifiable {
    let id: String
    let title: String
    let items: [LibrarySeries]
    var subtitle: String? = nil
    var sourceSeriesId: Int? = nil
}

private struct LibraryPlusCarousel: View {
    @EnvironmentObject private var library: LibraryViewModel
    let row: LibraryPlusRow
    let readingIDs: Set<Int>
    let coverWidth: CGFloat

    private var heading: String {
        if row.id == "similar", let sourceTitle = row.subtitle {
            return AppLocalization.format("읽으신 %@ 기반 추천", sourceTitle)
        }
        return AppLocalization.text(row.title)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(heading)
                .font(.title2.weight(.semibold))
                .padding(.horizontal, 24)
            if row.id != "similar", let subtitle = row.subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
                    .padding(.horizontal, 24)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(row.items) { series in
                        NavigationLink(value: series) {
                            LibraryShelfCoverView(series: series,
                                                  isReading: library.isReading(series),
                                                  width: coverWidth)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(series.title)
                    }
                }
                .padding(.horizontal, 24)
            }
        }
    }
}

/// Local, metadata-only curation. Unknown labels never imply a theme.
struct LibraryPlusCurator {
    // MARK: Lifecycle

    init(series: [LibrarySeries], metadata: [Int: LibraryPlusMetadata], readingIDs: Set<Int>,
         favouriteIDs: Set<Int>, recent: [LibrarySeries], day: Int,
         anchorHistory: [LibraryPlusAnchorRecord] = [],
         localMetadata: [UUID: LibraryPlusMetadata] = [:],
         localReadingIDs: Set<UUID> = [], localFavouriteIDs: Set<UUID> = [])
    {
        self.series = series
        self.metadata = metadata
        self.readingIDs = readingIDs
        self.favouriteIDs = favouriteIDs
        self.recent = recent
        self.day = day
        self.anchorHistory = anchorHistory
        self.localFavouriteIDs = localFavouriteIDs
        var ranks: [String: UInt64] = [:]
        var genres: [UUID: Set<String>] = [:]
        var tags: [UUID: Set<String>] = [:]
        for item in series {
            let key = Self.key(item)
            ranks[key] = SHA256.hash(data: Data("\(day)|\(key)".utf8)).prefix(8)
                .reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
            let value = item.isLocal ? localMetadata[item.id] : item.kavitaSeriesId.flatMap { metadata[$0] }
            genres[item.id] = Self.labels(value?.genres ?? [])
            tags[item.id] = Self.labels(value?.tags ?? [], kind: .tag)
        }
        ranksByID = ranks
        genresByID = genres
        tagsByID = tags
        unstarted = series.filter { item in
            !item.isRead && !localReadingIDs.contains(item.id) &&
                !(item.kavitaSeriesId.map(readingIDs.contains) ?? false)
        }.sorted {
            let left = Self.key($0), right = Self.key($1)
            let a = ranks[left] ?? 0, b = ranks[right] ?? 0
            return a == b ? left < right : a < b
        }
        let seedIDs = readingIDs.union(favouriteIDs)
        let localSeeds = localReadingIDs.union(localFavouriteIDs)
        seeds = series.filter { localSeeds.contains($0.id) || ($0.kavitaSeriesId.map(seedIDs.contains) ?? false) }
    }

    // MARK: Internal

    let series: [LibrarySeries]
    let metadata: [Int: LibraryPlusMetadata]
    let readingIDs: Set<Int>
    let favouriteIDs: Set<Int>
    let recent: [LibrarySeries]
    let day: Int
    let anchorHistory: [LibraryPlusAnchorRecord]

    var recommended: [LibrarySeries] { scored(using: seeds) }

    static func labels(_ values: [String], kind: MetadataCategoryKind = .genre) -> Set<String> {
        Set(values.filter { !MetadataCategoryRegistry.normalized($0).isEmpty }.map { value in
            let name = MetadataCategoryRegistry.matchingName(value, kind: kind)
            let thematicName = Self.aliases[Self.normalized(name)] ?? name
            return MetadataCategoryRegistry.identity(thematicName, kind: kind)
        })
    }

    func rank(_ key: String) -> UInt64 {
        if let rank = ranksByID[key] { return rank }
        return SHA256.hash(data: Data("\(day)|\(key)".utf8)).prefix(8)
            .reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
    }

    func daily(_ items: [LibrarySeries]) -> [LibrarySeries] {
        items.sorted {
            let left = Self.key($0)
            let right = Self.key($1)
            let a = rank(left), b = rank(right)
            return a == b ? left < right : a < b
        }
    }

    func rows(featured: [LibrarySeries], continuing: [LibrarySeries]) -> [LibraryPlusRow] {
        var result: [LibraryPlusRow] = []
        var memberships: [Set<UUID>] = []
        var appearances: [UUID: Int] = [:]
        for item in featured + continuing {
            appearances[item.id, default: 0] += 1
        }
        for (candidates, limit) in [(personalRows, 2), (themeRows, 5)] {
            var count = 0
            for candidate in candidates {
                guard count < limit else { break }
                let minimum = candidate.id == "favourites" ? 1 : 4
                var seen = Set<UUID>()
                let available = candidate.items.filter { item in
                    let id = item.id
                    return seen.insert(id).inserted && appearances[id, default: 0] < 2
                }
                guard available.count >= minimum else { continue }
                let items = Array(available.prefix(12))
                let membership = Set(items.map(\.id))
                guard !memberships.contains(where: {
                    Double($0.intersection(membership).count) / Double(min($0.count, membership.count)) >= 0.7
                }) else { continue }
                result.append(LibraryPlusRow(id: candidate.id, title: candidate.title,
                                             items: items, subtitle: candidate.subtitle,
                                             sourceSeriesId: candidate.sourceSeriesId))
                memberships.append(membership)
                for id in membership {
                    appearances[id, default: 0] += 1
                }
                count += 1
            }
        }
        return result
    }

    // MARK: Private

    private static let aliases: [String: String] = {
        let groups = [
            ["fantasy", "판타지"], ["adventure", "모험", "어드벤처"],
            ["isekai", "이세계"], [
                "overpowered protagonist",
                "overpowered main character",
                "overpowered",
                "먼치킨",
                "먼치킨 주인공",
                "압도적으로 강한 주인공",
            ],
            ["mind games", "심리전", "두뇌전"], ["strategy", "전략"], ["death game", "데스게임"],
            ["mystery", "미스터리", "미스테리"], ["detective", "탐정"], ["investigation", "수사"],
            ["survival", "서바이벌", "생존"], ["disaster", "재난"],
            ["post-apocalyptic", "포스트아포칼립스", "포스트 아포칼립스"],
            ["romance", "로맨스", "연애"], ["tragedy", "비극"], ["comedy", "코미디", "개그"],
            ["school", "학교", "학원", "학원물", "학원생활", "school life"],
            ["iyashikei", "치유물", "힐링", "힐링물"], ["slice of life", "일상", "일상물"],
            ["horror", "호러", "공포"], ["gore", "고어"], ["dark comedy", "black comedy", "블랙코미디"],
            ["sports", "sport", "스포츠"], ["sci-fi", "science fiction", "sf", "공상과학"],
            ["cyberpunk", "사이버펑크"], ["space", "우주"], ["robots", "robot", "로봇", "mecha", "메카"],
            ["ghost", "ghosts", "귀신", "유령"], ["ghost stories", "괴담"],
            ["cooking", "요리"], ["food", "음식", "gourmet", "미식"], ["action", "액션"],
            ["regression", "회귀", "시간 되돌리기", "time rewind"], ["time loop", "타임루프"],
            ["reincarnation", "환생"], ["revenge", "복수"], ["dungeon", "dungeons", "던전"],
            ["video games", "video game", "게임 세계", "게임세계", "게임 속 세계"],
            ["virtual world", "virtual reality", "가상현실", "가상현실 게임"],
            ["magic", "마법", "마술"], ["wuxia", "무협", "무림"],
            ["cultivation", "xianxia", "수선", "수선물"],
            ["swordplay", "swordsmanship", "검술", "검객"],
            ["historical", "history", "역사", "시대물"], ["workplace", "직장", "회사 생활", "회사생활"],
            ["music", "음악"], ["band", "bands", "밴드"], ["idol", "idols", "아이돌"],
            ["drawing", "painting", "그림", "회화"], ["manga making", "만화 제작", "만화제작"],
            ["writing", "글쓰기", "집필"], ["performing arts", "공연예술", "공연 예술"],
            ["family life", "가족생활", "가족 생활"], ["parenthood", "parenting", "부모와 자녀", "부모와자녀"],
            ["childcare", "child care", "육아"], ["animals", "animal", "동물"], ["pets", "pet", "반려동물"],
            ["travel", "travelling", "traveling", "여행"], ["wandering", "방랑"],
            ["rivalry", "rivals", "rival", "라이벌", "경쟁 관계", "경쟁관계"],
            ["team", "teams", "teamwork", "팀", "팀워크"], ["companions", "동료 중심", "동료중심"],
            ["coming of age", "성장", "성장물"],
            ["villain protagonist", "villainous protagonist", "악역 주인공", "악역주인공"],
            ["villainess", "악녀", "악역 영애", "악역영애"],
            ["politics", "political", "정치"], ["succession", "왕위 계승", "왕위계승"],
            ["power struggle", "권력 투쟁", "권력투쟁"],
            ["non-human protagonist", "nonhuman protagonist", "인간이 아닌 주인공", "인외 주인공", "인외주인공"],
            ["android protagonist", "안드로이드 주인공", "안드로이드주인공"],
            ["vampire protagonist", "흡혈귀 주인공", "흡혈귀주인공"],
        ]
        var result: [String: String] = [:]
        for group in groups {
            for alias in group {
                result[normalized(alias)] = group[0]
            }
        }
        return result
    }()

    private let localFavouriteIDs: Set<UUID>

    private let ranksByID: [String: UInt64]
    private let genresByID: [UUID: Set<String>]
    private let tagsByID: [UUID: Set<String>]
    private let unstarted: [LibrarySeries]
    private let seeds: [LibrarySeries]

    private var personalRows: [LibraryPlusRow] {
        let unread = unstarted
        let unreadIDs = Set(unread.map(\.id))
        let knownGenres = seeds.reduce(into: Set<String>()) { $0.formUnion(genres($1)) }
        var candidates = [
            LibraryPlusRow(id: "recommended", title: "취향에 맞는 작품", items: recommended),
            LibraryPlusRow(id: "recent", title: "새로 추가된 작품", items: recent.filter { unreadIDs.contains($0.id) }),
            LibraryPlusRow(id: "unstarted", title: "오늘 시작해 볼 작품", items: unread),
            LibraryPlusRow(id: "explore", title: "새로운 장르 탐색", items: unread.filter {
                !genres($0).isDisjoint(with: knownGenres) && !genres($0).subtracting(knownGenres).isEmpty
            }),
        ]
        // Choose a daily anchor that actually has enough related candidates.
        let anchors = LibraryPlusAnchorPolicy.candidates(series, history: anchorHistory, day: day) {
            rank(String($0))
        }
        let localAnchors = series.filter { $0.isLocal && (LibraryPlusAnchorPolicy.progress($0) ?? 0) >= 0.5 }
        let mixedAnchors = localAnchors.isEmpty ? anchors : daily(anchors + localAnchors)
        for seed in mixedAnchors {
            guard !genres(seed).isEmpty || !tags(seed).isEmpty else { continue }
            let related = scored(using: [seed])
            if related.count >= 4 {
                candidates.append(LibraryPlusRow(id: "similar", title: "이 작품이 마음에 들었다면",
                                                 items: related, subtitle: seed.title,
                                                 sourceSeriesId: seed.kavitaSeriesId))
                break
            }
        }
        candidates.sort { rank($0.id) < rank($1.id) }
        if let index = candidates.firstIndex(where: { $0.id == "similar" }) {
            let similar = candidates.remove(at: index)
            candidates.insert(similar, at: 0)
        }
        candidates.insert(LibraryPlusRow(id: "favourites", title: "찜한 작품",
                                         items: unread
                                             .filter {
                                                 localFavouriteIDs
                                                     .contains($0.id) ||
                                                     ($0.kavitaSeriesId.map(favouriteIDs.contains) ?? false)
                                             }),
                          at: 0)
        return candidates
    }

    private var themeRows: [LibraryPlusRow] {
        let definitions: [(String, String)] = [
            ("adventure", "다른 세계로 떠나는 모험"), ("overpowered", "먼치킨"),
            ("mind", "한 수 앞을 읽는 두뇌전"), ("mystery", "단서를 따라가는 미스터리"),
            ("survival", "긴장감 넘치는 생존 이야기"), ("romance", "설레는 로맨스"),
            ("romcom", "웃음과 설렘 사이"), ("school", "학교 이야기"),
            ("daily", "편안한 일상물"), ("comedy", "한바탕 웃고 싶을 때"),
            ("sports", "승부에 빠져드는 순간"), ("future", "미래와 기술을 상상하다"),
            ("horror", "서늘한 이야기"), ("food", "맛있는 만화"),
            ("regression", "회귀와 두 번째 기회"),
            ("reincarnation", "새로운 삶, 환생"),
            ("revenge", "복수의 시작"),
            ("dungeon", "던전과 공략"),
            ("gameworld", "게임 속 세계"),
            ("magic", "마법과 마술"),
            ("wuxia", "무림과 무협"),
            ("swords", "검과 검술"),
            ("history", "역사 속 이야기"),
            ("workplace", "직장 이야기"),
            ("music", "음악과 무대"),
            ("creation", "예술과 창작"),
            ("family", "가족 이야기"),
            ("animals", "동물과 함께"),
            ("travel", "여행과 방랑"),
            ("rivalry", "라이벌과 경쟁"),
            ("team", "팀으로 성장하는 이야기"),
            ("villain", "악역의 시선"),
            ("politics", "정치와 권력"),
            ("inhuman", "인간과 다른 존재들"),
        ]
        return definitions.map { id, title in
            LibraryPlusRow(id: id, title: title, items: unstarted.filter { matches(id, item: $0) })
        }.sorted { rank($0.id) < rank($1.id) }
    }

    private static func key(_ series: LibrarySeries) -> String {
        if !series.isLocal, let id = series.kavitaSeriesId { return String(id) }
        return series.id.uuidString
    }

    private static func normalized(_ value: String) -> String {
        value.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private func genres(_ item: LibrarySeries) -> Set<String> {
        genresByID[item.id] ?? []
    }

    private func tags(_ item: LibrarySeries) -> Set<String> {
        tagsByID[item.id] ?? []
    }

    private func scored(using seeds: [LibrarySeries]) -> [LibrarySeries] {
        let seedIDs = Set(seeds.map(\.id))
        var genreWeights: [String: Int] = [:]
        var tagWeights: [String: Int] = [:]
        for seed in seeds {
            for genre in genres(seed) {
                genreWeights[genre, default: 0] += 3
            }
            for tag in tags(seed) {
                tagWeights[tag, default: 0] += 1
            }
        }
        guard !genreWeights.isEmpty || !tagWeights.isEmpty else { return [] }
        return unstarted.filter { !seedIDs.contains($0.id) }.compactMap { item -> (LibrarySeries, Int)? in
            let score = genres(item).reduce(0) { $0 + (genreWeights[$1] ?? 0) }
                + tags(item).reduce(0) { $0 + (tagWeights[$1] ?? 0) }
            return score > 0 ? (item, score) : nil
        }.sorted { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
            return rank(Self.key(lhs.0)) < rank(Self.key(rhs.0))
        }.map { $0.0 }
    }

    private func matches(_ theme: String, item: LibrarySeries) -> Bool {
        let g = genres(item), t = tags(item)
        func genre(_ names: String...) -> Bool { !g.isDisjoint(with: Self.labels(names)) }
        func tag(_ names: String...) -> Bool { !t.isDisjoint(with: Self.labels(names, kind: .tag)) }
        switch theme {
        case "adventure": return (genre("fantasy") && genre("adventure")) || tag("isekai")
        case "overpowered": return tag("overpowered protagonist")
        case "mind": return tag("mind games", "strategy", "death game")
        case "mystery": return genre("mystery") || tag("detective", "investigation")
        case "survival": return tag("survival", "disaster", "post-apocalyptic")
        case "romance": return genre("romance") && !tag("tragedy")
        case "romcom": return genre("romance") && genre("comedy")
        case "school": return tag("school")
        case "daily": return (genre("slice of life") || tag("iyashikei")) && !genre("horror") && !tag("horror", "gore",
                                                                                                      "death game")
        case "comedy": return genre("comedy") && !tag("dark comedy", "gore")
        case "sports": return genre("sports")
        case "future": return genre("sci-fi") || tag("cyberpunk", "space", "robots")
        case "horror": return genre("horror") || tag("ghost", "ghost stories")
        case "food": return tag("cooking", "food")
        case "regression": return tag("regression", "time loop")
        case "reincarnation": return tag("reincarnation")
        case "revenge": return tag("revenge")
        case "dungeon": return tag("dungeon")
        case "gameworld": return tag("video games", "virtual world")
        case "magic": return tag("magic")
        case "wuxia": return tag("wuxia", "cultivation")
        case "swords": return tag("swordplay")
        case "history": return genre("historical") || tag("historical")
        case "workplace": return tag("workplace")
        case "music": return genre("music") || tag("music", "band", "idol")
        case "creation": return tag("drawing", "manga making", "writing", "performing arts")
        case "family": return tag("family life", "parenthood", "childcare")
        case "animals": return tag("animals", "pets")
        case "travel": return tag("travel", "wandering")
        case "rivalry": return tag("rivalry")
        case "team": return tag("team", "companions") && (genre("sports", "adventure") || tag("coming of age"))
        case "villain": return tag("villain protagonist", "villainess")
        case "politics": return tag("politics", "succession", "power struggle")
        case "inhuman": return tag("non-human protagonist", "android protagonist", "vampire protagonist")
        default: return false
        }
    }
}

/// Stable ordering and colors keep genre navigation recognizable across daily updates.
enum HomeGenre: String, CaseIterable, Identifiable {
    case fantasy, action, romance, comedy, sliceOfLife, mystery, adventure, sciFi, sports, horror, uncategorized

    // MARK: Internal

    var id: String { rawValue }
    var title: String { style.title }
    var color: Color { Color(hex: style.hex) ?? .gray }
    var symbol: String { style.symbol }

    func matches(_ genres: [String]) -> Bool {
        let labels = LibraryPlusCurator.labels(genres)
        if self == .uncategorized { return labels.isEmpty }
        return !labels.isDisjoint(with: LibraryPlusCurator.labels([style.label]))
    }

    // MARK: Private

    private var style: (title: String, label: String, hex: String, symbol: String) {
        switch self {
        case .fantasy: return ("판타지", "fantasy", "6042A6", "sparkles")
        case .action: return ("액션", "action", "B63832", "bolt.fill")
        case .romance: return ("로맨스", "romance", "A93669", "heart.fill")
        case .comedy: return ("코미디", "comedy", "946014", "face.smiling.fill")
        case .sliceOfLife: return ("일상", "slice of life", "37745D", "cup.and.saucer.fill")
        case .mystery: return ("미스터리", "mystery", "45477C", "magnifyingglass")
        case .adventure: return ("모험", "adventure", "A44F29", "map.fill")
        case .sciFi: return ("SF", "sci-fi", "246A91", "sparkle")
        case .sports: return ("스포츠", "sports", "31763E", "trophy.fill")
        case .horror: return ("공포", "horror", "653C59", "moon.fill")
        case .uncategorized: return ("장르 없음", "", "62666C", "books.vertical.fill")
        }
    }
}

struct HomeReadTagCarousel: View {
    let tags: [HomeReadTag]
    let isActive: Bool
    let canNavigate: () -> Bool
    var autoScroll = true

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @State private var cycleSize = CGSize.zero
    @State private var offset: CGFloat = 0
    @State private var dragOrigin: CGFloat?
    @State private var isVisible = false
    @State private var selectedTag: HomeReadTag?
    @State private var lastDragTime = Date.distantPast
    @GestureState private var isDragging = false

    private var usesLoop: Bool { autoScroll && tags.count > 1 && !reduceMotion && !voiceOverEnabled }
    private var shouldAnimate: Bool {
        usesLoop && isActive && isVisible && scenePhase == .active && !isDragging && cycleSize.width > 0
    }

    var body: some View {
        Group {
            if usesLoop {
                GeometryReader { geometry in
                    // Repeat enough complete cycles to fill even a wide iPad viewport.
                    let copies = cycleSize.width > 0 ? max(3, Int(ceil(geometry.size.width / cycleSize.width)) + 2) : 3
                    HStack(spacing: 0) {
                        ForEach(0 ..< copies, id: \.self) { copy in
                            capsules
                                .padding(.trailing, 10)
                                .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
                                    guard copy == 0, size.width > 0 else { return }
                                    cycleSize = size
                                    offset = wrapped(offset, width: size.width)
                                }
                                .accessibilityHidden(copy > 0)
                        }
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.vertical, 6)
                    .offset(x: -offset)
                }
                .frame(height: cycleSize.height > 0 ? cycleSize.height + 12 : 56)
                .contentShape(Rectangle())
                .clipped()
                .simultaneousGesture(
                    DragGesture(minimumDistance: 4)
                        .updating($isDragging) { _, state, _ in state = true }
                        .onChanged { value in
                            // Both vertical scrolling and horizontal dragging cancel category taps.
                            lastDragTime = Date()
                            guard abs(value.translation.width) > abs(value.translation.height) else { return }
                            if dragOrigin == nil { dragOrigin = offset }
                            offset = wrapped((dragOrigin ?? offset) - value.translation.width, width: cycleSize.width)
                        }
                        .onEnded { _ in
                            lastDragTime = Date()
                            dragOrigin = nil
                        }
                )
            } else {
                // Keep one accessible copy and native scrolling when motion is reduced.
                ScrollView(.horizontal, showsIndicators: false) {
                    capsules
                        .padding(.vertical, 6)
                }
                .onScrollPhaseChange { oldPhase, phase in
                    if oldPhase == .interacting || oldPhase == .decelerating ||
                        phase == .interacting || phase == .decelerating {
                        lastDragTime = Date()
                    }
                }
            }
        }
        .navigationDestination(item: $selectedTag) { tag in HomeTagDetailView(tag: tag) }
        .onChange(of: isDragging) { _, dragging in
            if !dragging {
                lastDragTime = Date()
                dragOrigin = nil
            }
        }
        .onScrollVisibilityChange(threshold: 0.01) { isVisible = $0 }
        .onChange(of: tags.map(\.id)) { _, _ in
            offset = 0
            dragOrigin = nil
        }
        .task(id: shouldAnimate) {
            guard shouldAnimate else { return }
            var previousTime = ProcessInfo.processInfo.systemUptime
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(16)) } catch { return }
                guard !Task.isCancelled else { return }
                let now = ProcessInfo.processInfo.systemUptime
                let elapsed = min(now - previousTime, 0.1)
                previousTime = now
                // Modulo swaps identical cycles without an animated jump at the seam.
                offset = wrapped(offset + CGFloat(elapsed) * 14, width: cycleSize.width)
            }
        }
    }

    private var capsules: some View {
        HStack(spacing: 10) {
            ForEach(tags) { tag in
                HomeTagCapsule(tag: tag) {
                    guard !isDragging, Date().timeIntervalSince(lastDragTime) > 0.25, canNavigate() else { return }
                    selectedTag = tag
                }
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func wrapped(_ value: CGFloat, width: CGFloat) -> CGFloat {
        guard width > 0 else { return 0 }
        let remainder = value.truncatingRemainder(dividingBy: width)
        return remainder < 0 ? remainder + width : remainder
    }
}

private struct HomeTagCapsule: View {
    let tag: HomeReadTag
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(MetadataLocalization.displayName(tag.name))
                .foregroundStyle(AppTheme.text)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .padding(.horizontal, 8)
                .frame(minHeight: 32)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.capsule)
        .accessibilityLabel(MetadataLocalization.displayName(tag.name))
    }
}

/// Keep a stable random preview while browsing; the full collection remains one tap away.
struct SearchTagBrowse: View {
    let tags: [HomeReadTag]
    let canNavigate: () -> Bool
    @State private var viewportWidth: CGFloat = 0
    @State private var widths: [String: CGFloat] = [:]
    @State private var previewTags: [HomeReadTag] = []
    @State private var showAllTags = false

    private var rows: [[HomeReadTag]] {
        HomeReadTag.previewRows(tags: previewTags)
    }

    private var fitsOneRow: Bool {
        previewTags.reduce(CGFloat(0)) { $0 + (widths[$1.id] ?? 120) + 10 } - 10 <= viewportWidth
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button {
                guard canNavigate() else { return }
                showAllTags = true
            } label: {
                HStack(spacing: 8) {
                    Text("태그 둘러보기")
                        .font(.title2.weight(.semibold))
                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.secondaryText)
                }
                .foregroundStyle(AppTheme.text)
                .frame(minHeight: 44, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            VStack(spacing: 4) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HomeReadTagCarousel(tags: row, isActive: true, canNavigate: canNavigate,
                                        autoScroll: !fitsOneRow)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { viewportWidth = $0 }
        .background(alignment: .topLeading) {
            HStack(spacing: 10) {
                ForEach(previewTags) { tag in
                    HomeTagCapsule(tag: tag, action: {})
                        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
                            if width > 0 { widths[tag.id] = width }
                        }
                }
            }
            .fixedSize()
            .hidden()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .onChange(of: tags.map(\.id), initial: true) { _, _ in
            previewTags = Array(tags.shuffled().prefix(45))
        }
        .navigationDestination(isPresented: $showAllTags) {
            AllTagsBrowseView(tags: tags)
        }
        .padding(.bottom, 32)
    }
}

/// Count each completed work once, using language-independent tag identities.
struct HomeReadTag: Identifiable, Hashable {
    let id: String
    let name: String
    let count: Int

    static func previewRows(tags: [HomeReadTag]) -> [[HomeReadTag]] {
        let preview = Array(tags.prefix(45))
        guard !preview.isEmpty else { return [] }
        let count = (preview.count + 14) / 15
        var rows = Array(repeating: [HomeReadTag](), count: count)
        for (index, tag) in preview.enumerated() { rows[index % count].append(tag) }
        return rows
    }

    static func ranked(catalog: [LibrarySeries], serverMetadata: [Int: LibraryPlusMetadata],
                       localMetadata: [UUID: LibraryPlusMetadata], completedOnly: Bool = true) -> [HomeReadTag]
    {
        var counts: [String: Int] = [:]
        var names: [String: String] = [:]
        var seenWorks = Set<String>()
        for series in catalog where !completedOnly || series.isRead {
            let workID = series.isLocal ? "local:\(series.id)" : series.kavitaSeriesId.map { "server:\($0)" } ?? series.id.uuidString
            guard seenWorks.insert(workID).inserted else { continue }
            let details = series.isLocal ? localMetadata[series.id] : series.kavitaSeriesId.flatMap { serverMetadata[$0] }
            for name in MetadataCategoryRegistry.cleaned(details?.tags ?? [], kind: .tag) {
                let id = MetadataCategoryRegistry.identity(name, kind: .tag)
                counts[id, default: 0] += 1
                if names[id] == nil { names[id] = MetadataCategoryRegistry.storageValue(name, kind: .tag) }
            }
        }
        return counts.map { HomeReadTag(id: $0.key, name: names[$0.key] ?? $0.key, count: $0.value) }
            .sorted { $0.count == $1.count ? $0.id < $1.id : $0.count > $1.count }
    }

}

private struct AllTagsBrowseView: View {
    let tags: [HomeReadTag]
    @State private var selectedTag: HomeReadTag?
    @State private var isScrolling = false
    @State private var lastScrollTime = Date.distantPast

    private var sortedTags: [HomeReadTag] {
        tags.sorted {
            let comparison = MetadataLocalization.displayName($0.name)
                .localizedStandardCompare(MetadataLocalization.displayName($1.name))
            return comparison == .orderedSame ? $0.id < $1.id : comparison == .orderedAscending
        }
    }

    var body: some View {
        ScrollView {
            TagCapsuleFlowLayout {
                ForEach(sortedTags) { tag in
                    HomeTagCapsule(tag: tag) {
                        guard !isScrolling, Date().timeIntervalSince(lastScrollTime) > 0.25 else { return }
                        selectedTag = tag
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 48)
        }
        .onScrollPhaseChange { _, phase in
            let wasScrolling = isScrolling
            isScrolling = phase == .interacting || phase == .decelerating || phase == .animating
            if isScrolling || wasScrolling { lastScrollTime = Date() }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 4)
                .onChanged { _ in lastScrollTime = Date() }
                .onEnded { _ in lastScrollTime = Date() }
        )
        .background(AppTheme.background)
        .navigationTitle("태그 둘러보기")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selectedTag) { tag in HomeTagDetailView(tag: tag) }
    }
}

/// Wrap capsules using their intrinsic widths, preserving their compact shape.
private struct TagCapsuleFlowLayout: Layout {
    private let spacing: CGFloat = 10

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrangement(width: proposal.width ?? 320, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let layout = arrangement(width: bounds.width, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            let frame = layout.frames[index]
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                          anchor: .topLeading, proposal: ProposedViewSize(frame.size))
        }
    }

    private func arrangement(width: CGFloat, subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        let availableWidth = max(1, width)
        for subview in subviews {
            let ideal = subview.sizeThatFits(.unspecified)
            let size = subview.sizeThatFits(ProposedViewSize(width: min(ideal.width, availableWidth), height: nil))
            if x > 0, x + size.width > availableWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return (CGSize(width: availableWidth, height: y + rowHeight), frames)
    }
}

private struct HomeTagDetailView: View {
    let tag: HomeReadTag
    @AppStorage(GeneralSettings.homeItemsPerRowKey) private var homeItemsPerRow = GeneralSettings.defaultItemsPerRow
    @EnvironmentObject private var library: LibraryViewModel
    @EnvironmentObject private var metadata: LibraryPlusViewModel

    private var series: [LibrarySeries] {
        let serverMetadata = metadata.dailyPresentation?.metadata ?? [:]
        return (library.sections.first { $0.title == "All Series" }?.series ?? []).filter { item in
            let details = item.isLocal ? metadata.localMetadata[item.id] : item.kavitaSeriesId.flatMap { serverMetadata[$0] }
            return (details?.tags ?? []).contains { MetadataCategoryRegistry.identity($0, kind: .tag) == tag.id }
        }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    var body: some View {
        ScrollView {
            if series.isEmpty {
                Text("표시할 작품이 없습니다.")
                    .foregroundStyle(AppTheme.secondaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 48)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16),
                                         count: GeneralSettings.itemsPerRow(homeItemsPerRow)), spacing: 20)
                {
                    ForEach(series) { item in
                        // Append above the presented tag destination rather than inserting
                        // a value into the root stack underneath that destination.
                        NavigationLink {
                            SeriesDetailView(series: item, initialWantToRead: library.isFavourite(item))
                        } label: {
                            LibraryGridCoverView(series: item, isReading: library.isReading(item))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(24)
            }
        }
        .background(AppTheme.background)
        .navigationTitle(MetadataLocalization.displayName(tag.name))
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct HomeGenreCard: View {
    let genre: HomeGenre

    private var isPhone: Bool { UIDevice.current.userInterfaceIdiom == .phone }

    var body: some View {
        HStack(alignment: .bottom) {
            Text(AppLocalization.text(genre.title))
                .font(.system(isPhone ? .headline : .title, design: .rounded, weight: .bold))
            Spacer(minLength: 12)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, isPhone ? 14 : 24)
        .padding(.top, isPhone ? 14 : 24)
        // Compensate for the title font's space below visible glyphs.
        .padding(.bottom, isPhone ? 12 : 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: isPhone ? 96 : 132, alignment: .bottomLeading)
        .background {
            ZStack(alignment: .topTrailing) {
                genre.color
                Image(systemName: genre.symbol)
                    .font(.system(size: isPhone ? 70 : 100, weight: .bold))
                    .rotationEffect(.degrees(-15))
                    .foregroundStyle(.white.opacity(0.12))
                    .offset(x: 12, y: -20)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct HomeGenreDetailView: View {
    // MARK: Internal

    let genre: HomeGenre

    var body: some View {
        ScrollView {
            if series.isEmpty {
                Text("표시할 작품이 없습니다.")
                    .foregroundStyle(AppTheme.secondaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 48)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16),
                                         count: GeneralSettings.itemsPerRow(homeItemsPerRow)),
                          spacing: 20)
                {
                    ForEach(series) { item in
                        NavigationLink(value: item) {
                            LibraryGridCoverView(series: item,
                                                 isReading: library.isReading(item))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(24)
            }
        }
        .background(AppTheme.background)
        .navigationTitle(AppLocalization.text(genre.title))
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Private

    @AppStorage(GeneralSettings.homeItemsPerRowKey) private var homeItemsPerRow = GeneralSettings.defaultItemsPerRow
    @EnvironmentObject private var library: LibraryViewModel
    @EnvironmentObject private var metadata: LibraryPlusViewModel

    private var series: [LibrarySeries] {
        metadata.series(in: genre, catalog: library.sections.first { $0.title == "All Series" }?.series ?? [])
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
}

#if DEBUG
private struct HomeGenreDiagnosticsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var library: LibraryViewModel
    @EnvironmentObject private var metadata: LibraryPlusViewModel

    private var catalog: [LibrarySeries] {
        library.sections.first { $0.title == "All Series" }?.series ?? []
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent(AppLocalization.text("전체 작품 수")) {
                        Text(verbatim: String(catalog.count)).monospacedDigit()
                    }
                }
                Section {
                    ForEach(HomeGenre.allCases) { genre in
                        let items = metadata.series(in: genre, catalog: catalog)
                        let localCount = items.filter(\.isLocal).count
                        HStack {
                            Label(AppLocalization.text(genre.title), systemImage: genre.symbol)
                            Spacer()
                            VStack(alignment: .trailing, spacing: 4) {
                                Text(AppLocalization.format("%d개 작품", items.count))
                                    .font(.headline)
                                    .monospacedDigit()
                                Text(AppLocalization.format("Kavita %d · 파일 %d", items.count - localCount, localCount))
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.secondaryText)
                            }
                        }
                    }
                } footer: {
                    Text(AppLocalization.text("현재 장르 상세 화면에 표시되는 작품 기준입니다. 권수가 아닌 작품 수이며, 여러 장르에 속한 작품은 각 장르에 중복 집계됩니다. 데이터 준비 중에는 수가 달라질 수 있습니다."))
                }
            }
            .navigationTitle(AppLocalization.text("개발용 장르 데이터"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    AppGlassActionButton(title: nil, systemImage: "xmark",
                                         size: CGSize(width: 44, height: 44),
                                         isEnabled: true, isHighlighted: false, variant: .standard,
                                         accessibilityLabel: AppLocalization.text("닫기"))
                    {
                        dismiss()
                    }
                    .frame(width: 44, height: 44)
                }
                .sharedBackgroundVisibility(.hidden)
            }
        }
    }
}
#endif
