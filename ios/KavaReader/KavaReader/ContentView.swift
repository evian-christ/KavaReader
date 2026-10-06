import SwiftUI
import UIKit

struct SectionNavigation: Hashable {
    let title: String
}

struct ContentView: View {
    init(isSearchTab: Bool = false, navigationPath: Binding<NavigationPath>? = nil) {
        self.isSearchTab = isSearchTab
        externalNavigationPath = navigationPath
    }

    private let externalNavigationPath: Binding<NavigationPath>?
    @State private var localNavigationPath = NavigationPath()

    // MARK: Internal

    @ViewBuilder
    var body: some View {
        if isSearchTab {
            navigationContent
                .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always),
                            prompt: "제목 또는 작가 검색")
        } else {
            navigationContent
        }
    }

    // MARK: Private

    private var navigationContent: some View {
        NavigationStack(path: externalNavigationPath ?? $localNavigationPath) {
            activeList
            .navigationTitle(isSearchTab ? Text("검색") : Text("라이브러리"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !isSearchTab {
                    ToolbarItem(placement: .topBarLeading) {
                        libraryFilterMenu
                    }
                    .sharedBackgroundVisibility(.hidden)
                    ToolbarItem(placement: .topBarLeading) {
                        librarySortMenu
                    }
                    .sharedBackgroundVisibility(.hidden)
                    ToolbarItem(placement: .principal) {
                        libraryCollectionMenu
                    }
                    if collection == "Files" {
                        ToolbarItem(placement: .topBarTrailing) {
                            fileHelpButton
                        }
                        .sharedBackgroundVisibility(.hidden)
                        ToolbarItem(placement: .topBarTrailing) {
                            LibraryImportMenuButton(isEnabled: !importing, language: selectedAppLanguage) { folder in
                                importTarget = nil
                                pickerFolder = folder
                            }
                            .frame(width: 44, height: 44)
                        }
                        .sharedBackgroundVisibility(.hidden)
                    }
                }
            }
            .safeAreaInset(edge: .top) {
                if let message = viewModel.errorMessage {
                    Label(AppLocalization.text(message, language: selectedAppLanguage), systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(AppTheme.surface)
                }
            }
            .sheet(isPresented: Binding(get: { pickerFolder != nil }, set: { if !$0 { pickerFolder = nil } })) {
                LocalComicPicker(folder: pickerFolder ?? false) { urls in
                    pickerFolder = nil
                    if !urls.isEmpty { startImport(urls) }
                }
            }
            .sheet(item: $managing) { comic in
                LocalComicManagementView(comic: comic).environmentObject(viewModel)
            }
            .alert("가져오기 결과", isPresented: $showImportResult) {
                Button("확인", role: .cancel) {}
            } message: { Text(importFailures) }
            .onAppear { if collection == "All Series" { collection = "Kavita" } }
            .navigationDestination(for: LibrarySeries.self) { series in
                SeriesDetailView(series: series,
                                 initialWantToRead: viewModel.isFavourite(series))
            }
            .navigationDestination(for: SectionNavigation.self) { sectionNav in
                SectionDetailView(sectionTitle: sectionNav.title, viewModel: viewModel)
            }
            .navigationDestination(for: HomeGenre.self) { genre in
                HomeGenreDetailView(genre: genre)
            }
        }
    }

    private let isSearchTab: Bool
    @AppStorage(AppLanguage.storageKey) private var selectedLanguage = AppLanguage.korean.rawValue

    @EnvironmentObject private var viewModel: LibraryViewModel
    @EnvironmentObject private var metadata: LibraryPlusViewModel
    @State private var searchText: String = ""
    @State private var isSearchScrolling = false
    @State private var lastSearchScrollTime = Date.distantPast

    @ViewBuilder
    private var activeList: some View {
        if isSearchTab {
            searchResultsList
        } else {
            libraryList
        }
    }

    private var searchResults: [LibrarySeries] { viewModel.searchSeries(query: searchText) }

    private var browseTags: [HomeReadTag] {
        HomeReadTag.ranked(catalog: viewModel.sections.first { $0.title == "All Series" }?.series ?? [],
                           serverMetadata: metadata.dailyPresentation?.metadata ?? [:],
                           localMetadata: metadata.localMetadata, completedOnly: false)
            .sorted {
                let comparison = MetadataLocalization.displayName($0.name)
                    .localizedStandardCompare(MetadataLocalization.displayName($1.name))
                return comparison == .orderedSame ? $0.id < $1.id : comparison == .orderedAscending
            }
    }

    private var selectedAppLanguage: AppLanguage { AppLanguage(rawValue: selectedLanguage) ?? .korean }

    private var readingSeriesIds: Set<Int> {
        Set(viewModel.sections.first(where: { $0.title == "읽는 중" })?.items.compactMap(\.kavitaSeriesId) ?? [])
    }

    private var favouriteSeriesIds: Set<Int> {
        Set(viewModel.sections.first(where: { $0.title == "Favourite" })?.items.compactMap(\.kavitaSeriesId) ?? [])
    }

    private var searchResultsList: some View {
        ScrollView {
            if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                VStack(alignment: .leading, spacing: 30) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("장르 둘러보기")
                            .font(.title2.weight(.semibold))
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14),
                                                       count: UIDevice.current.userInterfaceIdiom == .phone ? 2 : 3), spacing: 14) {
                            ForEach(metadata.availableGenres) { genre in
                                NavigationLink(value: genre) {
                                    HomeGenreCard(genre: genre)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    let tags = browseTags
                    if !tags.isEmpty {
                        SearchTagBrowse(tags: tags, canNavigate: {
                            !isSearchScrolling && Date().timeIntervalSince(lastSearchScrollTime) > 0.25
                        })
                    }
                }
                .padding(.vertical, 32)
            } else if searchResults.isEmpty {
                LibraryEmptyView(query: searchText, hasSnapshot: viewModel.lastUpdatedAt != nil)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 48)
                    .padding(.horizontal, 20)
            } else {
                VStack(alignment: .leading, spacing: 20) {
                    Text("전체 결과")
                        .font(.title2.weight(.semibold))

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 16)], spacing: 24) {
                        ForEach(searchResults) { item in
                            NavigationLink(value: item) {
                                VStack(alignment: .leading, spacing: 8) {
                                    GeometryReader { geometry in
                                        LibraryShelfCoverView(series: item,
                                                         isReading: viewModel.isReading(item),
                                                         width: geometry.size.width)
                                    }
                                    .aspectRatio(2.0 / 3.0, contentMode: .fit)
                                    Text(item.title)
                                        .font(.subheadline.weight(.medium))
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Text(item.author)
                                        .font(.caption)
                                        .foregroundStyle(AppTheme.secondaryText)
                                        .lineLimit(1)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .frame(height: 16)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.top, 32)
                .padding(.horizontal, 20)
            }
        }
        .onScrollPhaseChange { _, phase in
            let wasScrolling = isSearchScrolling
            isSearchScrolling = phase == .interacting || phase == .decelerating || phase == .animating
            if isSearchScrolling || wasScrolling { lastSearchScrollTime = Date() }
        }
        .background(AppTheme.background)
    }

    @AppStorage(GeneralSettings.libraryItemsPerRowKey) private var libraryItemsPerRow = GeneralSettings.defaultItemsPerRow

    @AppStorage("library.collection") private var collection = "Favourite"
    @AppStorage("library.listPreferences") private var listPreferencesData = Data()
    @State private var libraryViewportHeight: CGFloat = 0
    @State private var sortRevision = UUID()
    @State private var showFileHelp = false
    @State private var pickerFolder: Bool?
    @State private var importTask: Task<Void, Never>?
    @State private var importMessage: String?
    @State private var importing = false
    @State private var importTarget: UUID?
    @State private var managing: LocalComic?
    @State private var showImportResult = false
    @State private var importFailures = ""
    @State private var importProgress = 0.0

    private var listPreferences: [String: LibraryListPreferences] {
        (try? JSONDecoder().decode([String: LibraryListPreferences].self, from: listPreferencesData)) ?? [:]
    }

    private var collectionPreferencesKey: String { collection == "All Series" ? "Kavita" : collection }
    private var currentPreferences: LibraryListPreferences {
        listPreferences[collectionPreferencesKey] ?? LibraryListPreferences()
    }

    private var readFilter: String { currentPreferences.readFilter }
    private var librarySort: LibrarySort { currentPreferences.sort }

    private func savePreferences(_ preferences: LibraryListPreferences) {
        var saved = listPreferences
        saved[collectionPreferencesKey] = preferences
        if let data = try? JSONEncoder().encode(saved) { listPreferencesData = data }
    }

    private func selectReadFilter(_ filter: String) {
        var preferences = currentPreferences
        preferences.readFilter = filter
        savePreferences(preferences)
    }

    private func retainRandomOrder() {
        var preferences = currentPreferences
        guard preferences.sort == .random else { return }
        let previousOrder = preferences.randomOrder
        preferences.appendMissingSeries(collectionSeries.map { sortKey(for: $0) })
        if preferences.randomOrder != previousOrder { savePreferences(preferences) }
    }

    private var collectionSeries: [LibrarySeries] {
        if collection == "Kavita" || collection == "All Series" {
            return viewModel.sections.first(where: { $0.title == "All Series" })?.series.filter { $0.kavitaSeriesId != nil } ?? []
        }
        return viewModel.sections.first(where: { $0.title == collection })?.series ?? []
    }

    private var visibleSeries: [LibrarySeries] {
        let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let preferences = currentPreferences
        let randomSeriesRanks = preferences.randomRanks
        let librarySort = preferences.sort
        let readFilter = preferences.readFilter
        return collectionSeries.filter { series in
            let matchesSearch = term.isEmpty || series.title.localizedCaseInsensitiveContains(term) ||
                series.author.localizedCaseInsensitiveContains(term)
            let reading = viewModel.isReading(series)
            let matchesStatus = readFilter == "all" ||
                (readFilter == "read" && series.isRead) ||
                (readFilter == "reading" && reading) ||
                (readFilter == "unread" && !series.isRead && !reading)
            return matchesSearch && matchesStatus
        }.sorted { lhs, rhs in
            if librarySort == .random {
                let leftRank = randomSeriesRanks[sortKey(for: lhs)] ?? Int.max
                let rightRank = randomSeriesRanks[sortKey(for: rhs)] ?? Int.max
                if leftRank != rightRank { return leftRank < rightRank }
            }
            let comparison = lhs.title.localizedStandardCompare(rhs.title)
            if comparison == .orderedSame {
                return sortKey(for: lhs) < sortKey(for: rhs)
            }
            return comparison == (librarySort == .titleDescending ? .orderedDescending : .orderedAscending)
        }
    }

    private func sortKey(for series: LibrarySeries) -> String {
        series.kavitaSeriesId.map { "kavita:\($0)" } ?? series.id.uuidString
    }

    private func selectSort(_ sort: LibrarySort) {
        var preferences = currentPreferences
        if sort == .random {
            // Selecting Random again deliberately reshuffles; opening the list never does.
            preferences.randomOrder = Set(collectionSeries.map { sortKey(for: $0) }).shuffled()
        }
        preferences.sort = sort
        savePreferences(preferences)
        sortRevision = UUID()
    }

    private var fileHelpButton: some View {
        AppGlassActionButton(title: nil, systemImage: "questionmark.circle",
                             size: CGSize(width: 44, height: 44), isEnabled: true,
                             isHighlighted: false, variant: .standard, preservesIconAppearance: true,
                             accessibilityLabel: AppLocalization.text("파일 도움말", language: selectedAppLanguage)) {
            showFileHelp.toggle()
        }
        .frame(width: 44, height: 44)
        .popover(isPresented: $showFileHelp, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 12) {
                Text(AppLocalization.text("파일 도움말", language: selectedAppLanguage))
                    .font(.headline)
                    .foregroundStyle(AppTheme.text)
                Text(AppLocalization.text("CBZ·ZIP 파일을 기기에 복사합니다. 폴더를 선택하면 하위 폴더도 가져옵니다.",
                                          language: selectedAppLanguage))
                Text(AppLocalization.format("기기에 보관: %@", ByteCountFormatter.string(fromByteCount: viewModel.localStorageBytes, countStyle: .file)))
                Text(AppLocalization.text("작품을 길게 눌러 관리할 수 있습니다.", language: selectedAppLanguage))
            }
            .font(.footnote)
            .foregroundStyle(AppTheme.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
            .frame(idealWidth: 280, maxWidth: 280, alignment: .leading)
            .padding(20)
            .presentationBackground(AppTheme.surface)
            .presentationCompactAdaptation(.popover)
        }
    }

    private var libraryList: some View {
        VStack(spacing: 0) {
            if collection == "Files", let importMessage {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(importMessage).font(.footnote)
                        Spacer()
                        if importing {
                            Button("중단") { importTask?.cancel() }.buttonStyle(.glass)
                        }
                    }
                    if importing { ProgressView(value: importProgress) }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
            }
            ScrollView {
                LazyVStack(spacing: 0) {
                    if visibleSeries.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: collection == "Favourite" ? "heart" : "books.vertical")
                                .font(.largeTitle)
                            Text(collectionSeries.isEmpty && collection == "Favourite"
                                 ? "작품에서 하트를 누르면 여기에 표시됩니다." : "표시할 작품이 없습니다.")
                        }
                        .foregroundStyle(AppTheme.secondaryText)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, minHeight: 280)
                        .padding(.horizontal, 24)
                        .padding(.top, 20 + min(160, max(24, libraryViewportHeight * 0.16)))
                    } else {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: GeneralSettings.itemsPerRow(libraryItemsPerRow)), spacing: 20) {
                            ForEach(visibleSeries) { series in
                                NavigationLink(value: series) {
                                    LibraryGridCoverView(series: series,
                                                         isReading: viewModel.isReading(series))
                                }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        if series.isLocal {
                                            Button(viewModel.isFavourite(series) ? "즐겨찾기에서 제거" : "즐겨찾기에 추가",
                                                   systemImage: "heart") {
                                                Task {
                                                    do { try await LocalComicStore.shared.edit(series.id, favourite: !viewModel.isFavourite(series)) }
                                                    catch { importFailures = error.localizedDescription; showImportResult = true }
                                                }
                                            }
                                            Button("권 추가", systemImage: "doc.badge.plus") { importTarget = series.id; pickerFolder = false }
                                                .disabled(importing)
                                            Button("파일 관리", systemImage: "pencil") {
                                                managing = viewModel.localComics.first { $0.id == series.id }
                                            }.disabled(importing)
                                        }
                                    }
                            }
                        }
                        .padding(24)
                    }
                    if collection == "Files" {
                        LibraryIndexingStatus(diagnostics: metadata.localDiagnostics)
                    }
                }
            }
            .onGeometryChange(for: CGFloat.self) { geometry in
                geometry.size.height
            } action: { height in
                libraryViewportHeight = height
            }
            .id(collection + readFilter + sortRevision.uuidString)
        }
        .background(AppTheme.background)
        .onChange(of: collection) { _, _ in
            showFileHelp = false
            retainRandomOrder()
        }
        .onChange(of: collectionSeries.map { sortKey(for: $0) }.sorted(), initial: true) { _, _ in
            retainRandomOrder()
        }
    }

    private func startImport(_ urls: [URL]) {
        importing = true
        importMessage = AppLocalization.text("파일 목록을 확인하는 중…")
        importProgress = 0
        let target = importTarget
        importTask = Task {
            let scoped = urls.filter { $0.startAccessingSecurityScopedResource() }
            defer {
                scoped.forEach { $0.stopAccessingSecurityScopedResource() }
                importing = false
                importTask = nil
            }
            var imported = 0
            var skipped = 0
            var failures: [String] = []
            do {
                let discovery = Task.detached { try LocalComicImport.files(in: urls) }
                let files = try await withTaskCancellationHandler(operation: { try await discovery.value },
                                                                 onCancel: { discovery.cancel() })
                for (index, file) in files.enumerated() {
                    try Task.checkCancellation()
                    importMessage = AppLocalization.format("%d / %d · %@", index + 1, files.count, file.url.lastPathComponent)
                    do {
                        if try await LocalComicStore.shared.importFile(file.url, group: file.group, target: target) { imported += 1 }
                        else { skipped += 1 }
                    } catch is CancellationError { throw CancellationError() }
                    catch { failures.append("\(file.url.lastPathComponent): \(error.localizedDescription)") }
                    importProgress = Double(index + 1) / Double(max(1, files.count))
                }
            } catch is CancellationError { failures.append(AppLocalization.text("가져오기를 중단했습니다. 완료된 파일은 유지됩니다.")) }
            catch { failures.append(error.localizedDescription) }
            await viewModel.reloadLocalComics()
            importMessage = AppLocalization.format("%d개 추가 · %d개 중복 건너뜀", imported, skipped)
            if !failures.isEmpty {
                importFailures = failures.joined(separator: "\n")
                showImportResult = true
            }
        }
    }

    private var libraryCollectionMenu: some View {
        Menu {
            Picker("라이브러리", selection: $collection) {
                Text(AppLocalization.text("Favourite", language: selectedAppLanguage)).tag("Favourite")
                Text("Kavita").tag("Kavita")
                Text(AppLocalization.text("파일", language: selectedAppLanguage)).tag("Files")
            }
        } label: {
            HStack(spacing: 6) {
                Text(AppLocalization.text(collection == "Files" ? "파일" : collection, language: selectedAppLanguage))
                    .font(.headline)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(AppTheme.text)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var librarySortMenu: some View {
        Menu {
            ForEach(LibrarySort.allCases) { sort in
                Button {
                    selectSort(sort)
                } label: {
                    if librarySort == sort {
                        Label(sort.title, systemImage: "checkmark")
                    } else {
                        Text(sort.title)
                    }
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(AppTheme.text)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .frame(width: 44, height: 44)
        .glassEffect(.regular.interactive(), in: .circle)
        .contentShape(Circle())
        .accessibilityLabel(Text("정렬"))
        .accessibilityValue(Text(librarySort.title))
    }

    private var libraryFilterMenu: some View {
        Menu {
            Picker("읽기 상태", selection: Binding(get: { readFilter }, set: selectReadFilter)) {
                Text("모든 상태").tag("all")
                Text("읽지 않음").tag("unread")
                Text("읽는 중").tag("reading")
                Text("완독").tag("read")
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(AppTheme.text)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .frame(width: 44, height: 44)
        .glassEffect(.regular.interactive(), in: .circle)
        .contentShape(Circle())
        .accessibilityLabel(Text("필터"))
    }

}

private struct LibraryImportMenuButton: UIViewRepresentable {
    let isEnabled: Bool
    let language: AppLanguage
    let importItems: (Bool) -> Void

    func makeUIView(context _: Context) -> UIButton {
        var configuration = AppGlassButtonConfiguration.make(systemImage: "plus")
        configuration.baseForegroundColor = UIColor(AppTheme.text)
        configuration.image = UIImage(systemName: "plus")?.withTintColor(UIColor(AppTheme.text), renderingMode: .alwaysOriginal)
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        let button = UIButton(configuration: configuration, primaryAction: nil)
        button.tintAdjustmentMode = .normal
        button.showsMenuAsPrimaryAction = true
        button.changesSelectionAsPrimaryAction = false
        button.preferredMenuElementOrder = .fixed
        return button
    }

    func updateUIView(_ button: UIButton, context: Context) {
        context.coordinator.importItems = importItems
        button.isEnabled = isEnabled
        button.accessibilityLabel = AppLocalization.text("만화 추가", language: language)
        var configuration = AppGlassButtonConfiguration.make(systemImage: "plus")
        configuration.baseForegroundColor = UIColor(AppTheme.text)
        configuration.image = UIImage(systemName: "plus")?.withTintColor(UIColor(AppTheme.text), renderingMode: .alwaysOriginal)
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        if context.coordinator.palette != AppTheme.palette {
            context.coordinator.palette = AppTheme.palette
            button.configuration = configuration
        }
        if button.menu == nil || context.coordinator.language != language {
            context.coordinator.language = language
            button.menu = UIMenu(children: [
                UIAction(title: AppLocalization.text("파일 가져오기", language: language),
                         image: UIImage(systemName: "doc.badge.plus")) { [weak coordinator = context.coordinator] _ in
                    coordinator?.importItems(false)
                },
                UIAction(title: AppLocalization.text("폴더 가져오기", language: language),
                         image: UIImage(systemName: "folder.badge.plus")) { [weak coordinator = context.coordinator] _ in
                    coordinator?.importItems(true)
                },
            ])
        }
    }

    func sizeThatFits(_: ProposedViewSize, uiView _: UIButton, context _: Context) -> CGSize? {
        CGSize(width: 44, height: 44)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var language: AppLanguage?
        var palette: ThemePalette?
        var importItems: (Bool) -> Void = { _ in }
    }
}

struct LibraryListPreferences: Codable {
    var readFilter = "all"
    var sort: LibrarySort = .titleAscending
    var randomOrder: [String] = []

    var randomRanks: [String: Int] {
        Dictionary(randomOrder.enumerated().map { ($0.element, $0.offset) },
                   uniquingKeysWith: { first, _ in first })
    }

    mutating func appendMissingSeries(_ keys: [String]) {
        // Retain absent entries too, so a temporary catalog reload cannot change their order.
        let missing = Set(keys).subtracting(randomOrder)
        randomOrder.append(contentsOf: missing.shuffled())
    }
}

enum LibrarySort: String, Codable, CaseIterable, Identifiable {
    case titleAscending
    case titleDescending
    case random

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .titleAscending: "이름순 오름차순"
        case .titleDescending: "이름순 내림차순"
        case .random: "랜덤"
        }
    }
}

struct LibraryGridCoverView: View {
    let series: LibrarySeries
    let isReading: Bool

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomLeading) {
                if let url = series.coverURL {
                    CoverImageView(url: url, height: geometry.size.height, cornerRadius: 0,
                                   gradientColors: AppTheme.coverGradient)
                } else {
                    Rectangle()
                        .fill(LinearGradient(colors: AppTheme.coverGradient,
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                }
                LinearGradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: Color(red: 0.02, green: 0.16, blue: 0.11).opacity(0.40), location: 0.4),
                    .init(color: Color(red: 0.01, green: 0.10, blue: 0.07).opacity(0.76), location: 1)
                ], startPoint: .top, endPoint: .bottom)
                .frame(height: geometry.size.height * 0.52)

                Text(series.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                    .padding(10)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            // Composite the cover and gradient before applying their shared rounded edge.
            .compositingGroup()
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(alignment: .topTrailing) {
                if series.isRead {
                    ReadCheckBadge()
                } else if isReading {
                    ReadingBookmarkBadge()
                }
            }
        }
        .aspectRatio(2.0 / 3.0, contentMode: .fit)
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(series.title)
    }

}

struct LibraryShelfCoverView: View {
    // MARK: Internal

    let series: LibrarySeries
    let isReading: Bool
    var width: CGFloat = 128

    private var coverHeight: CGFloat { width * 1.5 }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .bottomLeading) {
                if let url = series.coverURL {
                    CoverImageView(url: url, height: coverHeight, cornerRadius: 6, gradientColors: gradientColors)
                } else {
                    // Fallback view when no cover URL - show title and author
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(LinearGradient(colors: gradientColors, startPoint: .topLeading,
                                             endPoint: .bottomTrailing))
                        .frame(height: coverHeight)
                        .overlay(VStack(alignment: .leading, spacing: 4) {
                            Text(series.title)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.white)
                                .lineLimit(2)
                            if !series.author.isEmpty {
                                Text(series.author)
                                    .font(.caption2)
                                    .foregroundStyle(.white.opacity(0.8))
                            }
                        }
                        .padding(12),
                        alignment: .bottomLeading)
                }
            }
            .overlay(alignment: .topTrailing) {
                if isReading && !series.isRead { ReadingBookmarkBadge() }
            }
            .overlay(alignment: .topTrailing) {
                if series.isRead { ReadCheckBadge() }
            }
        }
        .frame(width: width)
    }

    // MARK: Private

    @MainActor
    private var gradientColors: [Color] {
        let colors = series.coverColorHexes.compactMap(Color.init(hex:))
        return colors.isEmpty ? AppTheme.coverGradient : colors
    }
}

private struct MoreButtonView: View {
    var body: some View {
        VStack(alignment: .center, spacing: 12) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(AppTheme.surface)
                .frame(width: 130, height: 195)
                .overlay {
                    VStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title)
                            .foregroundStyle(AppTheme.secondaryText)
                        Text("더 보기")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                }
        }
        .frame(width: 130)
    }
}

struct ContinueReadingItemView: View {
    // MARK: Internal

    let item: ContinueReadingItem
    let isReading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomLeading) {
                // 배경 커버 이미지
                if let url = item.series.coverURL {
                    CoverImageView(url: url, height: 195, cornerRadius: 6, gradientColors: gradientColors)
                } else {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(LinearGradient(colors: gradientColors, startPoint: .topLeading,
                                             endPoint: .bottomTrailing))
                        .frame(height: 195)
                }

                // 진행률 오버레이
                VStack(alignment: .leading, spacing: 4) {
                    Spacer()

                    // 진행률 바
                    ProgressView(value: item.progressPercentage)
                        .progressViewStyle(LinearProgressViewStyle(tint: .white))
                        .scaleEffect(x: 1, y: 0.8, anchor: .center)

                    // 진행률 텍스트
                    Text(AppLocalization.text(item.progressText))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.3), radius: 1, x: 0, y: 1)
                }
                .padding(12)
            }
            .overlay(alignment: .topTrailing) {
                if isReading && !item.series.isRead { ReadingBookmarkBadge() }
            }
            .overlay(alignment: .topTrailing) {
                if item.series.isRead { ReadCheckBadge() }
            }

            // 제목 정보
            VStack(alignment: .leading, spacing: 2) {
                Text(item.series.title)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .foregroundStyle(AppTheme.text)

                Text(item.lastReadChapter.title)
                    .font(.caption2)
                    .lineLimit(1)
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
        .frame(width: 130)
    }

    // MARK: Private

    @MainActor
    private var gradientColors: [Color] {
        let colors = item.series.coverColorHexes.compactMap(Color.init(hex:))
        return colors.isEmpty ? AppTheme.coverGradient : colors
    }
}

private struct LibraryErrorView: View {
    let message: String
    let retryAction: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text(AppLocalization.text(message))
                .multilineTextAlignment(.center)
                .foregroundStyle(AppTheme.secondaryText)
            Button("다시 시도") {
                retryAction()
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.accentFill)
        }
        .padding(32)
    }
}

private struct LibraryEmptyView: View {
    let query: String
    let hasSnapshot: Bool

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.largeTitle)
                .foregroundStyle(AppTheme.secondaryText)
            Text(AppLocalization.text(query.isEmpty
                ? (hasSnapshot ? "서버에 표시할 작품이 없습니다." : "저장된 작품 목록이 없습니다. 설정의 서버 설정에서 라이브러리를 업데이트해 주세요.")
                : "검색 결과가 없습니다."))
                .foregroundStyle(AppTheme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(32)
    }
}

#Preview {
    ContentView()
        .environmentObject(LibraryViewModel(service: LibraryServiceFactory(baseURLString: nil, apiKey: nil)
                .makeService()))
}
