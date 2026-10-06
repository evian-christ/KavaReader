import Combine
import SwiftUI
import UIKit

struct SeriesDetailView: View {
    // MARK: Lifecycle

    init(series: LibrarySeries, initialWantToRead: Bool? = nil) {
        self.series = series
        _isWantToRead = State(initialValue: initialWantToRead ?? false)
        _hasWantToReadStatus = State(initialValue: initialWantToRead != nil)
        _viewModel = StateObject(wrappedValue: SeriesDetailViewModel(service: LibraryServiceFactory(baseURLString: nil,
                                                                                                    apiKey: nil)
                .makeService()))
    }

    // MARK: Internal

    let series: LibrarySeries

    var body: some View {
        GeometryReader { geometry in
            if viewModel.isUnavailable {
                ScrollView {
                    unavailableContent
                }
            } else if UIDevice.current.userInterfaceIdiom == .pad,
                      geometry.size.width >= 800,
                      geometry.size.width > geometry.size.height
            {
                HStack(alignment: .top, spacing: 0) {
                    // This pane stays in place while the chapter list scrolls.
                    // Its own scroll view keeps long titles and larger text accessible.
                    ScrollView {
                        heroSection(coverHeight: min(270, max(150, geometry.size.height - 250)),
                                    compact: true)
                    }
                    .frame(width: min(380, max(340, geometry.size.width * 0.3)))

                    Divider()

                    detailScrollView(includesHero: false)
                }
            } else {
                detailScrollView(includesHero: true, availableWidth: geometry.size.width)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                AppLoadingStatus(message: loadingStatusMessage)
            }
            ToolbarItem(placement: .topBarTrailing) {
                AppGlassActionButton(title: nil, systemImage: "info.circle",
                                     size: CGSize(width: 38, height: 38),
                                     isEnabled: true, isHighlighted: false, variant: .standard,
                                     accessibilityLabel: AppLocalization.text("작품 정보"))
                {
                    showInformation = true
                }
                .frame(width: 38, height: 38)
            }
        }
        .sheet(isPresented: $showInformation) {
            SeriesInformationSheet(series: series, identity: "\(serverBaseURL)|\(apiKey)",
                                   service: currentFactory.makeService() as? KavitaLibraryService)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(20)
        }
        .task(id: "\(serverBaseURL)|\(apiKey)") {
            await loadSeries()
        }
        .task(id: "\(serverBaseURL)|\(apiKey)|\(series.kavitaSeriesId ?? -1)") {
            await loadWantToReadStatus()
        }
        .onAppear { restoreReadingStatus() }
        .onReceive(NotificationCenter.default.publisher(for: .localComicsDidChange)) { _ in
            if series.isLocal {
                Task { await viewModel.loadLocal(id: series.id); await loadWantToReadStatus() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .seriesReadingPauseDidChange)) { notification in
            guard notification.object as? String == "\(serverBaseURL)|\(apiKey)" else { return }
            restoreReadingStatus()
        }
        .alert(AppLocalization.text(readingConflict == nil ? "읽기 위치 확인" : "읽기 위치가 다릅니다"),
               isPresented: $showReadAlert)
        {
            if let conflict = readingConflict {
                Button("서버 위치로 열기") {
                    guard conflict.identity == "\(serverBaseURL)|\(apiKey)" else {
                        readingConflict = nil
                        return
                    }
                    ReadingStatusStore.saveServerPoint(conflict.serverPoint,
                                                       identity: conflict.identity,
                                                       seriesId: conflict.seriesId)
                    restoreReadingStatus()
                    Task {
                        await prepareAndOpenReader(chapter: conflict.serverChapter,
                                                   page: conflict.serverPoint?.pagesRead,
                                                   verified: true)
                    }
                    readingConflict = nil
                }
                Button("기기 위치로 열기") {
                    guard conflict.identity == "\(serverBaseURL)|\(apiKey)" else {
                        readingConflict = nil
                        return
                    }
                    Task {
                        await prepareAndOpenReader(chapter: conflict.localChapter,
                                                   page: conflict.localPage,
                                                   verified: false)
                    }
                    readingConflict = nil
                }
            } else if fallbackChapter != nil {
                Button("저장된 위치로 열기") {
                    guard fallbackIdentity == "\(serverBaseURL)|\(apiKey)" else {
                        fallbackChapter = nil
                        fallbackPage = nil
                        fallbackIdentity = nil
                        return
                    }
                    if let fallbackChapter {
                        let page = fallbackPage
                        Task {
                            await prepareAndOpenReader(chapter: fallbackChapter, page: page, verified: false)
                        }
                    }
                    fallbackChapter = nil
                    fallbackPage = nil
                    fallbackIdentity = nil
                }
            }
            Button(AppLocalization.text(readingConflict == nil && fallbackChapter == nil ? "확인" : "취소"),
                   role: .cancel)
            {
                fallbackChapter = nil
                fallbackPage = nil
                fallbackIdentity = nil
                readingConflict = nil
            }
        } message: {
            Text(AppLocalization.text(readAlertMessage))
        }
        .alert("읽기 기록을 초기화할까요?",
               isPresented: $showMarkUnreadConfirmation)
        {
            Button("취소", role: .cancel) {}
            Button("읽기 기록 초기화", role: .destructive) {
                Task { await markReadState(read: false) }
            }
        } message: {
            Text("이 작품의 모든 권과 챕터의 읽기 진행률 및 저장된 읽기 위치가 초기화됩니다.")
        }
        .alert("읽기 상태 변경 실패", isPresented: $showReadStateError) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(AppLocalization.text(readStateErrorMessage))
        }
        .alert("즐겨찾기 변경 실패", isPresented: $showWantToReadError) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(AppLocalization.text(wantToReadErrorMessage))
        }
        .navigationDestination(isPresented: $isNavigatingToReader) {
            if let selectedChapter = selectedChapter {
                ReaderView(series: series,
                           chapter: selectedChapter,
                           serviceFactory: currentFactory,
                           chapters: viewModel.detail?.chapters ?? [],
                           libraryId: viewModel.detail?.libraryId,
                           initialPage: readerInitialPage,
                           preparedImage: readerPreparedImage,
                           isContinuePointVerified: isContinuePointVerified)
            }
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppLanguage.storageKey) private var selectedLanguage = AppLanguage.korean.rawValue
    @AppStorage(GeneralSettings.detailItemsPerRowKey) private var detailItemsPerRow = GeneralSettings.defaultItemsPerRow
    @AppStorage("server_base_url") private var serverBaseURL: String = ""
    @AppStorage(KavitaCredentials.revisionKey) private var credentialRevision = 0
    private var apiKey: String {
        _ = credentialRevision
        return KavitaCredentials.read(server: serverBaseURL, field: "apiKey")
    }

    @StateObject private var viewModel: SeriesDetailViewModel
    @State private var lastServiceKey: String = ""
    @State private var selectedChapter: SeriesChapter?
    @State private var isNavigatingToReader = false
    @State private var readingStatus: ReadingStatus?
    @State private var isOpeningReader = false
    @State private var isUpdatingReadState = false
    @State private var isWantToRead = false
    @State private var hasWantToReadStatus = false
    @State private var isUpdatingWantToRead = false
    @State private var showWantToReadError = false
    @State private var wantToReadErrorMessage = ""
    @State private var wantToReadStatusError: String?
    @State private var wantToReadKey: String?
    @State private var wantToReadRequestID = UUID()
    @State private var showMarkUnreadConfirmation = false
    @State private var isReadingPaused = false
    @State private var showReadStateError = false
    @State private var readStateErrorMessage = ""
    @State private var isContinuePointVerified = true
    @State private var fallbackChapter: SeriesChapter?
    @State private var fallbackPage: Int?
    @State private var fallbackIdentity: String?
    @State private var readerInitialPage: Int?
    @State private var readerPreparedImage: UIImage?
    @State private var readingConflict: ReadingConflict?
    @State private var showReadAlert = false
    @State private var readAlertMessage = ""
    @State private var showInformation = false

    private var chapterGrid: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 12),
              count: GeneralSettings.itemsPerRow(detailItemsPerRow))
    }

    @MainActor
    private var gradientColors: [Color] {
        let colors = series.coverColorHexes.compactMap(Color.init(hex:))
        return colors.isEmpty ? AppTheme.coverGradient : colors
    }

    private var currentFactory: LibraryServiceFactory {
        LibraryServiceFactory(baseURLString: serverBaseURL, apiKey: apiKey.isEmpty ? nil : apiKey)
    }

    private var loadingStatusMessage: String? {
        if isUpdatingWantToRead { return AppLocalization.text("즐겨찾기 변경 중") }
        if isUpdatingReadState { return AppLocalization.text("읽기 상태 변경 중") }
        if isOpeningReader { return AppLocalization.text("읽기 화면 여는 중") }
        return nil
    }

    private var unavailableContent: some View {
        VStack(spacing: 16) {
            Image(systemName: "books.vertical")
                .font(.largeTitle)
                .foregroundStyle(AppTheme.secondaryText)
            Text(AppLocalization.text(viewModel.errorMessage ?? "이 작품을 열 수 없습니다."))
                .multilineTextAlignment(.center)
            Button("목록으로 돌아가기") { dismiss() }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accentFill)
        }
        .frame(maxWidth: .infinity)
        .padding(32)
    }

    private func detailScrollView(includesHero: Bool, availableWidth: CGFloat = 0) -> some View {
        let isPhone = UIDevice.current.userInterfaceIdiom == .phone
        let columns = GeneralSettings.itemsPerRow(detailItemsPerRow)
        // Match the chapter grid's horizontal padding, spacing, and cover aspect ratio.
        let chapterCoverWidth = max(1, (availableWidth - 48 - CGFloat(columns - 1) * 12) / CGFloat(columns))

        return ScrollView {
            VStack(spacing: 0) {
                if includesHero {
                    heroSection(coverHeight: isPhone ? min(330, chapterCoverWidth * 1.5) : 330,
                                phoneLayout: isPhone)
                }

                if let detail = viewModel.detail, !detail.chapters.isEmpty {
                    chaptersSection(chapters: detail.chapters)
                }

                if viewModel.isLoading {
                    ProgressView("시리즈 정보를 불러오는 중")
                        .progressViewStyle(.circular)
                        .padding(.top, 40)
                }

                if let error = viewModel.errorMessage {
                    ErrorView(message: error) {
                        Task { await loadSeries(force: true) }
                    }
                    .padding(.top, 40)
                }
            }
            .padding(.top, includesHero ? 0 : 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .refreshable {
            await loadSeries(force: true)
            await loadWantToReadStatus()
        }
    }

    private func heroSection(coverHeight: CGFloat = 330, compact: Bool = false,
                             phoneLayout: Bool = false) -> some View
    {
        VStack(spacing: phoneLayout ? 14 : (compact ? 20 : 24)) {
            // Series cover
            ZStack {
                if let url = series.coverURL {
                    CoverImageView(url: url, height: coverHeight, cornerRadius: 8, gradientColors: gradientColors)
                } else {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(LinearGradient(colors: gradientColors, startPoint: .topLeading,
                                             endPoint: .bottomTrailing))
                        .frame(height: coverHeight)
                }
            }
            .frame(width: coverHeight * 2 / 3, height: coverHeight)
            .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)

            // Title and author
            VStack(spacing: phoneLayout ? 6 : 8) {
                Text(series.title)
                    .font((phoneLayout ? Font.title2 : Font.title).weight(.bold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(AppTheme.text)

                if !series.author.isEmpty {
                    Text(series.author)
                        .font(phoneLayout ? .subheadline : .title3)
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }

            // Read button and series actions
            HStack(spacing: 12) {
                AppGlassActionButton(title: nil,
                                     systemImage: isWantToRead ? "heart.fill" : "heart",
                                     size: CGSize(width: 46, height: 46),
                                     isEnabled: hasWantToReadStatus &&
                                         !isUpdatingWantToRead && !isOpeningReader && !isUpdatingReadState,
                                     isHighlighted: isWantToRead,
                                     variant: .standard,
                                     accessibilityLabel: AppLocalization.text(isWantToRead ? "즐겨찾기에서 제거" : "즐겨찾기에 추가"))
                {
                    Task { await toggleWantToRead() }
                }
                .frame(width: 46, height: 46)

                AppGlassActionButton(title: readButtonTitle,
                                     systemImage: readingStatus?.hasProgress == true ? "play.circle.fill" : "play.fill",
                                     size: CGSize(width: 160, height: 46),
                                     isEnabled: !(viewModel.detail?.chapters.isEmpty ?? true) && !isOpeningReader &&
                                         !isUpdatingReadState && !isUpdatingWantToRead,
                                     isHighlighted: false,
                                     variant: .primary,
                                     accessibilityLabel: readButtonTitle)
                {
                    Task { await startReading() }
                }
                .frame(width: 160, height: 46)

                SeriesReadOptionsButton(isEnabled: series.kavitaSeriesId != nil,
                                        canChangeReadState: !isOpeningReader && !isUpdatingReadState,
                                        isReadingPaused: isReadingPaused,
                                        language: selectedLanguage)
                {
                    Task { await markReadState(read: true) }
                } stopReading: {
                    Task { await stopReading() }
                } confirmMarkUnread: {
                    Task { @MainActor in
                        await Task.yield()
                        showMarkUnreadConfirmation = true
                    }
                }
                .frame(width: 46, height: 46)
            }

            if let wantToReadStatusError {
                Button {
                    Task { await loadWantToReadStatus() }
                } label: {
                    Label(AppLocalization.text(wantToReadStatusError), systemImage: "arrow.clockwise")
                        .font(.footnote)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, phoneLayout ? 12 : 20)
        .padding(.bottom, compact || phoneLayout ? 24 : 40)
        .frame(maxWidth: .infinity)
    }

    private func chaptersSection(chapters: [SeriesChapter]) -> some View {
        let regularChapters = chapters.filter { !$0.isSpecial }
        let specials = chapters.filter(\.isSpecial)

        return VStack(alignment: .leading, spacing: 20) {
            if !regularChapters.isEmpty {
                chapterGroup(title: series.kavitaSeriesId == nil ? "권 목록" : "챕터",
                             countFormat: series.kavitaSeriesId == nil ? "%d권" : "%d화", chapters: regularChapters,
                             allChapters: chapters)
            }
            if !regularChapters.isEmpty && !specials.isEmpty {
                Divider()
                    .padding(.horizontal, 24)
            }
            if !specials.isEmpty {
                chapterGroup(title: "Specials", countFormat: "%d편", chapters: specials,
                             allChapters: chapters)
            }
        }
        .padding(.bottom, 32)
    }

    private func chapterGroup(title: String, countFormat: String,
                              chapters: [SeriesChapter], allChapters: [SeriesChapter]) -> some View
    {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text(AppLocalization.text(title))
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(AppTheme.text)
                Spacer()
                Text(AppLocalization.format(countFormat, chapters.count))
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
            }
            .padding(.horizontal, 24)

            LazyVGrid(columns: chapterGrid, spacing: 16) {
                ForEach(chapters) { chapter in
                    NavigationLink {
                        ReaderView(series: series,
                                   chapter: chapter,
                                   serviceFactory: currentFactory,
                                   chapters: allChapters,
                                   libraryId: viewModel.detail?.libraryId)
                    } label: {
                        ChapterCoverView(chapter: chapter, seriesCoverColors: gradientColors)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)
        }
    }

    private func loadSeries(force: Bool = false) async {
        restoreReadingStatus()
        updateService(force: force)
        if let kavitaSeriesId = series.kavitaSeriesId {
            await viewModel.load(kavitaSeriesId: kavitaSeriesId,
                                 identity: "\(serverBaseURL)|\(apiKey)",
                                 baseURL: URL(string: serverBaseURL), apiKey: apiKey,
                                 force: force)
        } else if series.isLocal {
            await viewModel.loadLocal(id: series.id)
        } else {
            viewModel.setError("시리즈 ID를 찾을 수 없습니다")
        }
    }

    private func updateService(force: Bool) {
        let key = "\(serverBaseURL)|\(apiKey)"
        if force || key != lastServiceKey {
            viewModel.updateService(currentFactory.makeService())
            lastServiceKey = key
        }
    }

    private var readButtonTitle: String {
        if series.isLocal {
            return AppLocalization.text(viewModel.detail?.chapters.contains { ($0.lastReadPage ?? 0) > 0 } == true ? "계속 읽기" : "읽기")
        }
        guard let readingStatus else { return AppLocalization.text("읽기") }
        return AppLocalization.text(readingStatus.hasProgress ? "계속 읽기" : "읽기 시작")
    }

    private func restoreReadingStatus() {
        guard let seriesId = series.kavitaSeriesId else {
            readingStatus = nil
            return
        }
        isReadingPaused = ReadingPauseStore.pausedSeriesIDs(identity: "\(serverBaseURL)|\(apiKey)").contains(seriesId)
        readingStatus = ReadingStatusStore.load(identity: "\(serverBaseURL)|\(apiKey)", seriesId: seriesId)
    }

    private func loadWantToReadStatus() async {
        if series.isLocal {
            isWantToRead = (try? await LocalComicStore.shared.all().first { $0.id == series.id }?.favourite) ?? false
            hasWantToReadStatus = true
            return
        }
        guard let seriesId = series.kavitaSeriesId else { return }
        let requestID = UUID()
        wantToReadRequestID = requestID
        let identity = "\(serverBaseURL)|\(apiKey)"
        let key = "\(identity)|\(seriesId)"
        if let wantToReadKey, wantToReadKey != key {
            hasWantToReadStatus = false
            isWantToRead = false
        }
        wantToReadKey = key
        wantToReadStatusError = nil
        guard let service = currentFactory.makeService() as? KavitaLibraryService else {
            if !hasWantToReadStatus { wantToReadStatusError = "즐겨찾기 상태를 확인하지 못했습니다. 다시 시도" }
            return
        }
        do {
            let current = try await service.isSeriesInWantToRead(seriesId: seriesId)
            guard wantToReadRequestID == requestID, identity == "\(serverBaseURL)|\(apiKey)" else { return }
            let changed = hasWantToReadStatus && isWantToRead != current
            isWantToRead = current
            hasWantToReadStatus = true
            if changed { notifyWantToReadChange(identity: identity, isWanted: current) }
        } catch {
            if wantToReadRequestID == requestID, !hasWantToReadStatus {
                wantToReadStatusError = "즐겨찾기 상태를 확인하지 못했습니다. 다시 시도"
            }
        }
    }

    private func toggleWantToRead() async {
        if series.isLocal {
            do {
                try await LocalComicStore.shared.edit(series.id, favourite: !isWantToRead)
                isWantToRead.toggle()
            } catch { wantToReadErrorMessage = error.localizedDescription; showWantToReadError = true }
            return
        }
        guard !isUpdatingWantToRead, let seriesId = series.kavitaSeriesId else { return }
        guard let service = currentFactory.makeService() as? KavitaLibraryService else {
            wantToReadErrorMessage = LibraryServiceError.invalidBaseURL.errorDescription ?? "서버 설정을 확인해 주세요."
            showWantToReadError = true
            return
        }
        isUpdatingWantToRead = true
        wantToReadRequestID = UUID()
        defer { isUpdatingWantToRead = false }
        let identity = "\(serverBaseURL)|\(apiKey)"
        let target = !isWantToRead
        do {
            try await service.setWantToRead(seriesId: seriesId, isWanted: target)
            guard identity == "\(serverBaseURL)|\(apiKey)" else { return }
            isWantToRead = target
            hasWantToReadStatus = true
            notifyWantToReadChange(identity: identity, isWanted: target)
        } catch {
            guard identity == "\(serverBaseURL)|\(apiKey)" else { return }
            wantToReadErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            showWantToReadError = true
        }
    }

    private func notifyWantToReadChange(identity: String, isWanted: Bool) {
        NotificationCenter.default.post(name: .seriesWantToReadDidChange, object: identity,
                                        userInfo: ["series": series, "isWanted": isWanted])
    }

    private func stopReading() async {
        guard !isUpdatingReadState, !isOpeningReader, let seriesId = series.kavitaSeriesId else { return }
        guard let service = currentFactory.makeService() as? KavitaLibraryService else {
            readStateErrorMessage = LibraryServiceError.invalidBaseURL.errorDescription ?? "서버 설정을 확인해 주세요."
            showReadStateError = true
            return
        }
        isUpdatingReadState = true
        defer { isUpdatingReadState = false }
        let identity = "\(serverBaseURL)|\(apiKey)"
        await ReaderProgressSaveQueue.shared.wait(identity: identity, seriesId: seriesId)
        guard identity == "\(serverBaseURL)|\(apiKey)" else { return }
        do {
            try await service.stopReading(seriesId: seriesId)
            guard identity == "\(serverBaseURL)|\(apiKey)" else { return }
            ReadingPauseStore.setPaused(true, identity: identity, seriesId: seriesId)
            restoreReadingStatus()
        } catch {
            guard identity == "\(serverBaseURL)|\(apiKey)" else { return }
            readStateErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            showReadStateError = true
        }
    }

    private func markReadState(read: Bool) async {
        if series.isLocal {
            do { try await LocalComicStore.shared.edit(series.id, read: read); await loadSeries(force: true) }
            catch { readStateErrorMessage = error.localizedDescription; showReadStateError = true }
            return
        }
        guard !isUpdatingReadState, !isOpeningReader, let seriesId = series.kavitaSeriesId else { return }
        guard let service = currentFactory.makeService() as? KavitaLibraryService else {
            readStateErrorMessage = LibraryServiceError.invalidBaseURL.errorDescription ?? "서버 설정을 확인해 주세요."
            showReadStateError = true
            return
        }
        isUpdatingReadState = true
        defer { isUpdatingReadState = false }
        let identity = "\(serverBaseURL)|\(apiKey)"
        await ReaderProgressSaveQueue.shared.wait(identity: identity, seriesId: seriesId)
        guard identity == "\(serverBaseURL)|\(apiKey)" else { return }

        do {
            try await service.markSeriesReadState(seriesId: seriesId, read: read)
            guard identity == "\(serverBaseURL)|\(apiKey)" else { return }
            ReadingPauseStore.setPaused(false, identity: identity, seriesId: seriesId, notify: false)
            ReadingStatusStore.clear(identity: identity, seriesId: seriesId)
            for chapter in viewModel.detail?.chapters ?? [] {
                UserDefaults.standard.removeObject(forKey: "chapter_progress_\(chapter.id.uuidString)")
            }
            restoreReadingStatus()
            NotificationCenter.default.post(name: .seriesReadStateDidChange, object: identity,
                                            userInfo: ["seriesId": seriesId, "read": read])
            await loadSeries(force: true)
            await loadWantToReadStatus()
        } catch {
            guard identity == "\(serverBaseURL)|\(apiKey)" else { return }
            readStateErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            showReadStateError = true
        }
    }

    private func startReading() async {
        guard !isOpeningReader else { return }
        guard let kavitaSeriesId = series.kavitaSeriesId else {
            await viewModel.loadLocal(id: series.id)
            let local = try? await LocalComicStore.shared.all().first { $0.id == series.id }
            let chapters = viewModel.detail?.chapters ?? []
            let last = chapters.first(where: { $0.id == local?.lastChapterID })
            let chapter = last.flatMap { saved in
                (saved.lastReadPage ?? 0) < saved.pageCount ? saved :
                    (chapters.first { ($0.lastReadPage ?? 0) < $0.pageCount } ?? saved)
            } ?? chapters.first
            if let chapter {
                await prepareAndOpenReader(chapter: chapter, page: max(1, chapter.lastReadPage ?? 1), verified: true)
            }
            return
        }

        isOpeningReader = true
        defer { isOpeningReader = false }
        let identity = "\(serverBaseURL)|\(apiKey)"
        guard let kavitaService = currentFactory.makeService() as? KavitaLibraryService else {
            readAlertMessage = "서버 설정을 확인한 뒤 다시 시도해 주세요."
            showReadAlert = true
            return
        }
        await ReaderProgressSaveQueue.shared.wait(identity: identity, seriesId: kavitaSeriesId)
        guard identity == "\(serverBaseURL)|\(apiKey)" else { return }
        let saved = ReadingStatusStore.load(identity: identity, seriesId: kavitaSeriesId)
        let chapters = viewModel.detail?.chapters ?? []
        let hintedChapter = saved?.hasProgress == true
            ? chapters.first(where: { $0.kavitaChapterId == saved?.chapterId })
            : chapters.first
        let imagePrefetch = hintedChapter.map { chapter in
            let hintedPage = saved?.hasProgress == true ? (saved?.page ?? 1) : 1
            let page = max(1, min(chapter.pageCount, hintedPage))
            return ReaderImagePrefetch(chapterID: chapter.id, page: page,
                                       task: Task { await fetchReaderImage(chapter: chapter, page: page) })
        }
        defer { imagePrefetch?.task.cancel() }

        do {
            let continuePoint = try await kavitaService.getContinuePoint(seriesId: kavitaSeriesId)
            guard identity == "\(serverBaseURL)|\(apiKey)" else { return }
            let serverChapter: SeriesChapter
            if let continuePoint, continuePoint.pagesRead > 0 {
                if viewModel.detail?.chapters.first(where: { $0.kavitaChapterId == continuePoint.chapterId }) == nil {
                    await loadSeries(force: true)
                }
                guard identity == "\(serverBaseURL)|\(apiKey)" else { return }
                guard let chapter = viewModel.detail?.chapters
                    .first(where: { $0.kavitaChapterId == continuePoint.chapterId })
                else {
                    readAlertMessage = "서버의 읽기 위치에 해당하는 챕터를 목록에서 찾지 못했습니다. 챕터 목록을 새로고침해 주세요."
                    showReadAlert = true
                    return
                }
                serverChapter = chapter
            } else {
                guard let firstChapter = viewModel.detail?.chapters.first else { return }
                serverChapter = firstChapter
            }

            if let saved, saved.hasProgress,
               saved.chapterId != continuePoint?.chapterId || saved.page != (continuePoint?.pagesRead ?? 0),
               let chapterId = saved.chapterId,
               let localChapter = viewModel.detail?.chapters.first(where: { $0.kavitaChapterId == chapterId })
            {
                let progress = try? await kavitaService.getProgress(chapterId: chapterId)
                guard identity == "\(serverBaseURL)|\(apiKey)" else { return }
                if progress?.chapterId == chapterId, progress?.seriesId == kavitaSeriesId,
                   progress?.pageNum == saved.page
                {
                    await prepareAndOpenReader(chapter: localChapter, page: saved.page,
                                               verified: true, prefetch: imagePrefetch)
                    return
                }
                readingConflict = ReadingConflict(identity: identity, seriesId: kavitaSeriesId,
                                                  serverPoint: continuePoint, serverChapter: serverChapter,
                                                  localChapter: localChapter, localPage: saved.page)
                readAlertMessage = "서버와 이 기기에 저장된 읽기 위치가 다릅니다. 기기 위치로 열면 이번 읽기의 진행률은 서버에 자동 전송되지 않습니다."
                showReadAlert = true
                return
            }

            ReadingStatusStore.saveServerPoint(continuePoint, identity: identity, seriesId: kavitaSeriesId)
            restoreReadingStatus()
            await prepareAndOpenReader(chapter: serverChapter,
                                       page: continuePoint?.pagesRead, verified: true,
                                       prefetch: imagePrefetch)
        } catch {
            guard identity == "\(serverBaseURL)|\(apiKey)" else { return }
            let saved = ReadingStatusStore.load(identity: identity, seriesId: kavitaSeriesId)
            fallbackIdentity = identity
            if let saved {
                fallbackChapter = saved.hasProgress
                    ? viewModel.detail?.chapters.first(where: { $0.kavitaChapterId == saved.chapterId })
                    : viewModel.detail?.chapters.first
                fallbackPage = saved.hasProgress ? saved.page : nil
            } else {
                fallbackChapter = nil
                fallbackPage = nil
            }
            readAlertMessage = fallbackChapter == nil
                ? "서버에서 읽기 위치를 확인할 수 없습니다. 연결 상태를 확인한 뒤 다시 시도해 주세요."
                : "서버에서 읽기 위치를 확인할 수 없습니다. 저장된 위치로 열면 이번 읽기의 진행률은 서버에 자동 전송되지 않습니다."
            showReadAlert = true
        }
    }

    private func prepareAndOpenReader(chapter: SeriesChapter, page: Int?, verified: Bool,
                                      prefetch: ReaderImagePrefetch? = nil) async
    {
        let ownsLoadingState = !isOpeningReader
        isOpeningReader = true
        defer {
            if ownsLoadingState { isOpeningReader = false }
        }

        let identity = "\(serverBaseURL)|\(apiKey)"
        let targetPage = max(1, min(chapter.pageCount, page ?? 1))
        let preparedImage: UIImage?
        if let prefetch, prefetch.chapterID == chapter.id, prefetch.page == targetPage {
            preparedImage = await prefetch.task.value
        } else {
            prefetch?.task.cancel()
            preparedImage = await fetchReaderImage(chapter: chapter, page: targetPage)
        }
        guard identity == "\(serverBaseURL)|\(apiKey)" else { return }

        selectedChapter = chapter
        readerInitialPage = targetPage
        readerPreparedImage = preparedImage
        isContinuePointVerified = verified
        isNavigatingToReader = true
    }

    private func fetchReaderImage(chapter: SeriesChapter, page: Int) async -> UIImage? {
        if chapter.isEpub { return nil }
        if series.isLocal {
            guard let data = try? await LocalComicStore.shared.pageData(chapterID: chapter.id, page: page) else { return nil }
            return UIImage(data: data)
        }
        let service = currentFactory.makeService()
        let url: URL
        do {
            if let kavitaService = service as? KavitaLibraryService,
               let chapterId = chapter.kavitaChapterId
            {
                url = try kavitaService.pageImageURL(kavitaChapterId: chapterId, pageNumber: page)
            } else {
                url = try service.pageImageURL(seriesID: series.id, chapterID: chapter.id, pageNumber: page)
            }
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200 ..< 300).contains(httpResponse.statusCode)
            else { return nil }
            return UIImage(data: data)
        } catch {
            return nil
        }
    }
}

private struct SeriesInformationSheet: View {
    let series: LibrarySeries
    let identity: String
    let service: KavitaLibraryService?

    @AppStorage(AppLanguage.storageKey) private var selectedLanguage = AppLanguage.korean.rawValue
    @EnvironmentObject private var metadataModel: LibraryPlusViewModel
    @State private var primary: LibraryPlusMetadata?
    @State private var external: ExternalSeriesMetadata?
    @State private var manualConnection: ManualSeriesMetadataRecord?
    @State private var showConnectionSearch = false
    @State private var isChangingConnection = false
    @State private var connectionError: String?
    @State private var isLoading = true
    @State private var loadFailed = false
    @State private var customCategories = LibraryPlusMetadata(summary: "", genres: [], tags: [])
    @State private var showCategoryInput = false
    @State private var isAddingGenre = true
    @State private var newCategory = ""
    @State private var customCategoryError: String?
    @State private var categoryChoices: [MetadataCategoryRegistry.Entry] = []
    @State private var showCategoryChoices = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    Text(series.title)
                        .font(.headline)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let id = series.kavitaSeriesId {
                        Text("\(AppLocalization.text("작품 ID")) · \(id)")
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                            .fixedSize(horizontal: true, vertical: false)
                            .textSelection(.enabled)
                    }
                }

                if series.isLocal || series.kavitaSeriesId != nil {
                    Divider()
                    connectionSection
                }

                if let categories = displayedCategories {
                    if !categories.genres.isEmpty {
                        Divider()
                        categoryRow("장르", categories: categories.genres, custom: customContributions.genres)
                    }
                    if !categories.tags.isEmpty {
                        Divider()
                        categoryRow("태그", categories: categories.tags, custom: customContributions.tags)
                    }
                    Text(AppLocalization.format("출처: %@", categories.source))
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }

                if let summary = primary?.summary,
                   !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                {
                    Divider()
                    informationRow("줄거리", value: summary)
                }

                if isLoading && primary == nil {
                    Divider()
                    ProgressView(AppLocalization.text(series.isLocal ? "파일 정보 확인 중" : "카비타 정보 확인 중"))
                } else if loadFailed {
                    Divider()
                    Text(AppLocalization.text(series.isLocal ? "파일 정보를 읽지 못해 저장된 정보만 표시합니다." : "카비타 연결에 실패해 저장된 정보만 표시합니다."))
                        .font(.footnote)
                        .foregroundStyle(AppTheme.secondaryText)
                } else if primary == nil {
                    Divider()
                    Text(AppLocalization.text(series.isLocal ? "파일에 내장된 메타데이터가 없습니다." : "카비타 메타데이터를 확인하지 못했습니다."))
                        .font(.footnote)
                        .foregroundStyle(AppTheme.secondaryText)
                }
                Divider()
                customCategorySection
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .alert(AppLocalization.text(isAddingGenre ? "장르 추가" : "태그 추가"),
               isPresented: $showCategoryInput)
        {
            TextField(AppLocalization.text(isAddingGenre ? "장르" : "태그"), text: $newCategory)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button(AppLocalization.text("취소"), role: .cancel) { newCategory = "" }
            Button(AppLocalization.text("추가")) { addCustomCategory() }
                .disabled(!canAddCustomCategory)
        } message: {
            Text(AppLocalization.text("이 기기에 저장됩니다. 이미 있는 장르·태그는 같은 분류에 중복 추가할 수 없습니다."))
        }
        .task(id: "\(identity)|\(series.id)") { await load() }
        .onChange(of: metadataModel.localMetadataRevision) { _, _ in
            if series.isLocal { Task { await loadConnection() } }
        }
        .sheet(isPresented: $showCategoryChoices) {
            NavigationStack {
                List(categoryChoices) { entry in
                    Button {
                        showCategoryChoices = false
                        saveCustomCategory(entry.storageID(kind: customCategoryKind))
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.name(language: AppLanguage(rawValue: selectedLanguage) ?? .korean))
                            Text(entry.englishName).font(.caption).foregroundStyle(AppTheme.secondaryText)
                        }
                    }
                    .disabled(categoryAlreadyExists(entry.storageID(kind: customCategoryKind)))
                }
                .navigationTitle(AppLocalization.text("분류 선택"))
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        AppGlassActionButton(title: nil, systemImage: "xmark", size: CGSize(width: 44, height: 44),
                                             isEnabled: true, isHighlighted: false, variant: .standard,
                                             accessibilityLabel: AppLocalization.text("닫기"))
                        { showCategoryChoices = false }
                        .frame(width: 44, height: 44)
                    }
                    .sharedBackgroundVisibility(.hidden)
                }
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showConnectionSearch) {
            AniListConnectionSheet(series: series, identity: identity) {
                Task { await loadConnection() }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    private var connectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(AppLocalization.text("외부 메타데이터"))
                .font(.caption).foregroundStyle(AppTheme.secondaryText)
            if let external {
                Text(external.sourceTitle).font(.headline)
                Text(AppLocalization.text(manualConnection != nil ? "사용자가 연결한 작품" : "자동으로 연결된 작품"))
                    .font(.footnote).foregroundStyle(AppTheme.secondaryText)
                Link(AppLocalization.text("AniList에서 보기"), destination: external.sourceURL)
                if manualConnection?.metadata != nil {
                    Text(AppLocalization.text("분류는 직접 연결한 AniList 정보를 우선 사용합니다."))
                        .font(.footnote).foregroundStyle(AppTheme.secondaryText)
                } else if primary?.hasCategories == true {
                    Text(AppLocalization.text(series.isLocal ? "분류는 파일 내장 정보를 우선 사용합니다." : "분류는 Kavita 정보를 우선 사용합니다."))
                        .font(.footnote).foregroundStyle(AppTheme.secondaryText)
                }
            } else {
                Text(AppLocalization.text(manualConnection != nil
                        ? "이 작품의 자동 연결이 중지되었습니다."
                        : "연결된 AniList 작품이 없습니다."))
                    .font(.footnote).foregroundStyle(AppTheme.secondaryText)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { connectionActions }
                VStack(alignment: .leading, spacing: 12) { connectionActions }
            }
            if manualConnection?.metadata != nil {
                connectionButton("연결 정보 새로고침", icon: "arrow.clockwise") {
                    Task { await refreshConnection() }
                }
            }
            if let connectionError {
                Text(connectionError).font(.footnote).foregroundStyle(AppTheme.secondaryText)
            }
            if isChangingConnection { ProgressView() }
        }
    }

    @ViewBuilder
    private var connectionActions: some View {
        connectionButton(external == nil ? "작품 연결" : "연결 변경", icon: "link") {
            showConnectionSearch = true
        }
        if external != nil {
            connectionButton("연결 해제", icon: "xmark.circle") {
                Task { await setConnection(ManualSeriesMetadataRecord(metadata: nil, updatedAt: Date())) }
            }
        } else if manualConnection != nil {
            connectionButton("자동 연결 사용", icon: "arrow.uturn.backward") {
                Task { await setConnection(nil) }
            }
        }
    }

    private func connectionButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        AppGlassActionButton(title: AppLocalization.text(title), systemImage: icon,
                             size: CGSize(width: 120, height: 44), isEnabled: !isLoading && !isChangingConnection,
                             isHighlighted: false, variant: .standard, expandsToFitTitle: true,
                             accessibilityLabel: AppLocalization.text(title), action: action)
            .frame(height: 44)
    }

    private func loadConnection() async {
        if series.isLocal {
            let saved = await LocalSeriesMetadataStore.shared.information(id: series.id, title: series.title)
            guard !Task.isCancelled else { return }
            external = saved.external
            manualConnection = saved.manual
            return
        }
        guard let id = series.kavitaSeriesId else { return }
        let saved = await SeriesInformationCache.load(identity: identity, seriesID: id, title: series.title)
        guard !Task.isCancelled else { return }
        external = saved.external
        manualConnection = saved.manual
    }

    private func setConnection(_ record: ManualSeriesMetadataRecord?) async {
        guard !isChangingConnection else { return }
        isChangingConnection = true
        connectionError = nil
        do {
            try await saveConnection(record)
            await loadConnection()
            if !series.isLocal { NotificationCenter.default.post(name: .seriesMetadataConnectionDidChange, object: identity) }
        } catch {
            connectionError = AppLocalization.text("연결을 저장하지 못했습니다. 다시 시도해 주세요.")
        }
        isChangingConnection = false
    }

    private func refreshConnection() async {
        guard !isChangingConnection,
              let linked = manualConnection?.metadata else { return }
        isChangingConnection = true
        connectionError = nil
        do {
            let refreshed = try await AniListMetadataService(includeNovels: series.isLocal).metadata(id: linked.aniListID)
            try await saveConnection(ManualSeriesMetadataRecord(metadata: refreshed, updatedAt: Date()))
            await loadConnection()
            if !series.isLocal { NotificationCenter.default.post(name: .seriesMetadataConnectionDidChange, object: identity) }
        } catch ExternalLookupError.rateLimited {
            connectionError = AppLocalization.text("AniList 요청 제한에 도달했습니다. 잠시 후 다시 검색해 주세요.")
        } catch {
            connectionError = AppLocalization.text("연결 정보를 갱신하지 못했습니다. 저장된 연결은 유지됩니다.")
        }
        isChangingConnection = false
    }

    private func saveConnection(_ record: ManualSeriesMetadataRecord?) async throws {
        if series.isLocal {
            try await LocalSeriesMetadataStore.shared.set(record, id: series.id)
        } else if let id = series.kavitaSeriesId {
            try await ManualSeriesMetadataStore.shared.set(record, identity: identity, seriesID: id)
        } else { throw LibraryServiceError.noData }
    }

    private var sourceCategories: LibraryPlusMetadata {
        LibraryPlusMetadata.resolved(primary: primary ?? LibraryPlusMetadata(summary: "", genres: [], tags: []),
                                     external: external, manual: manualConnection)
    }

    private var customContributions: LibraryPlusMetadata {
        let source = sourceCategories
        return LibraryPlusMetadata(summary: "",
                                   genres: customCategories.genres.filter {
                                       !MetadataCategoryRegistry.contains(source.genres, value: $0, kind: .genre)
                                   },
                                   tags: customCategories.tags.filter {
                                       !MetadataCategoryRegistry.contains(source.tags, value: $0, kind: .tag)
                                   })
    }

    private var displayedCategories: (genres: [String], tags: [String], source: String)? {
        let primary = primary ?? LibraryPlusMetadata(summary: "", genres: [], tags: [])
        var resolved = sourceCategories
        let additions = customContributions
        var source = manualConnection?.metadata != nil || !primary.hasCategories
            ? "AniList" : (series.isLocal ? AppLocalization.text("파일 내장 정보") : "Kavita")
        if additions.hasCategories {
            source = resolved.hasCategories ? source + " · " + AppLocalization.text("커스텀")
                : AppLocalization.text("커스텀")
            resolved = LibraryPlusMetadata(summary: resolved.summary,
                                           genres: resolved.genres + additions.genres,
                                           tags: resolved.tags + additions.tags)
        }
        guard resolved.hasCategories else { return nil }
        return (resolved.genres, resolved.tags, source)
    }

    private var customCategoryKey: String {
        CustomSeriesCategoryStore.key(identity: identity,
                                      seriesID: series.isLocal ? series.id.uuidString
                                          : (series.kavitaSeriesId.map { String($0) } ?? series.id.uuidString),
                                      isLocal: series.isLocal)
    }

    private var customCategoryColor: Color {
        AppTheme.palette.colorScheme == .light
            ? Color(red: 0.65, green: 0.29, blue: 0.02)
            : Color(red: 1, green: 0.72, blue: 0.38)
    }

    private var customCategorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    customCategoryButton(isGenre: true)
                    customCategoryButton(isGenre: false)
                }
                VStack(alignment: .leading, spacing: 12) {
                    customCategoryButton(isGenre: true)
                    customCategoryButton(isGenre: false)
                }
            }
            if customCategories.hasCategories {
                AppGlassActionButton(title: AppLocalization.text("커스텀 장르·태그 전체 삭제"),
                                     systemImage: "trash", size: CGSize(width: 180, height: 44),
                                     isEnabled: true, isHighlighted: false, variant: .standard,
                                     expandsToFitTitle: true,
                                     accessibilityLabel: AppLocalization.text("커스텀 장르·태그 전체 삭제"))
                {
                    CustomSeriesCategoryStore.reset(key: customCategoryKey)
                    customCategories = LibraryPlusMetadata(summary: "", genres: [], tags: [])
                    customCategoryError = nil
                    notifyCustomCategoriesChanged()
                }
                .frame(height: 44)
            }
            if let customCategoryError {
                Text(customCategoryError).font(.footnote).foregroundStyle(AppTheme.secondaryText)
            }
        }
    }

    private func customCategoryButton(isGenre: Bool) -> some View {
        let title = AppLocalization.text(isGenre ? "장르 추가" : "태그 추가")
        return AppGlassActionButton(title: title, systemImage: "plus", size: CGSize(width: 140, height: 44),
                                   isEnabled: true, isHighlighted: false, variant: .standard,
                                   expandsToFitTitle: true, accessibilityLabel: title)
        {
            isAddingGenre = isGenre
            newCategory = ""
            customCategoryError = nil
            showCategoryInput = true
        }
        .frame(height: 44)
    }

    private var customCategoryKind: MetadataCategoryKind { isAddingGenre ? .genre : .tag }

    private func categoryAlreadyExists(_ value: String) -> Bool {
        let existing = (isAddingGenre ? displayedCategories?.genres : displayedCategories?.tags) ?? []
        return MetadataCategoryRegistry.contains(existing, value: value, kind: customCategoryKind)
    }

    private var canAddCustomCategory: Bool {
        let value = newCategory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return false }
        let matches = MetadataCategoryRegistry.candidates(value, kind: customCategoryKind)
        if matches.isEmpty { return !categoryAlreadyExists(value) }
        return matches.contains { !categoryAlreadyExists($0.storageID(kind: customCategoryKind)) }
    }

    private func addCustomCategory() {
        guard canAddCustomCategory else { return }
        let matches = MetadataCategoryRegistry.candidates(newCategory, kind: customCategoryKind)
        if matches.count > 1 {
            categoryChoices = matches
            showCategoryChoices = true
            return
        }
        saveCustomCategory(MetadataCategoryRegistry.storageValue(newCategory, kind: customCategoryKind))
    }

    private func saveCustomCategory(_ value: String) {
        guard !value.isEmpty, !categoryAlreadyExists(value) else { return }
        let updated = LibraryPlusMetadata(summary: "",
                                          genres: customCategories.genres + (isAddingGenre ? [value] : []),
                                          tags: customCategories.tags + (isAddingGenre ? [] : [value]))
        do {
            try CustomSeriesCategoryStore.save(updated, key: customCategoryKey)
            customCategories = updated
            newCategory = ""
            customCategoryError = nil
            notifyCustomCategoriesChanged()
        } catch {
            customCategoryError = AppLocalization.text("장르·태그를 저장하지 못했습니다. 다시 시도해 주세요.")
        }
    }

    private func notifyCustomCategoriesChanged() {
        NotificationCenter.default.post(name: CustomSeriesCategoryStore.didChange,
                                        object: series.isLocal ? LocalSeriesMetadataStore.notificationIdentity : identity)
    }

    private func informationRow(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(AppLocalization.text(label))
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)
            Text(value)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private func categoryRow(_ label: String, categories: [String], custom: [String]) -> some View {
        let values = categories.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if !values.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                Text(AppLocalization.text(label))
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                categoryText(values, custom: custom, kind: label == "장르" ? .genre : .tag)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 3)
        }
    }

    private func categoryText(_ values: [String], custom: [String], kind: MetadataCategoryKind) -> Text {
        values.enumerated().reduce(Text("")) { result, item in
            let isCustom = MetadataCategoryRegistry.contains(custom, value: item.element, kind: kind)
            let name = MetadataLocalization.displayName(item.element,
                                                       language: AppLanguage(rawValue: selectedLanguage) ?? .korean)
            let separator = item.offset == 0 ? Text("") : Text(" · ").foregroundColor(AppTheme.secondaryText)
            let value = Text(name).foregroundColor(isCustom ? customCategoryColor : AppTheme.text)
            return result + separator + value
        }
    }

    private func load() async {
        isLoading = true
        loadFailed = false
        customCategories = CustomSeriesCategoryStore.load(key: customCategoryKey)
        if series.isLocal {
            do {
                let comic = try await LocalComicStore.shared.metadataCatalog().first { $0.id == series.id }
                guard !Task.isCancelled else { return }
                primary = comic?.embeddedMetadata
                await loadConnection()
            } catch { loadFailed = true }
            isLoading = false
            return
        }
        guard let id = series.kavitaSeriesId else {
            isLoading = false
            return
        }
        isLoading = true
        let saved = await SeriesInformationCache.load(identity: identity, seriesID: id, title: series.title)
        primary = saved.kavita
        external = saved.external
        manualConnection = saved.manual
        guard !Task.isCancelled, let service else {
            isLoading = false
            return
        }
        do {
            let fetched = try await service.fetchSeriesMetadata(kavitaSeriesId: id)
            guard !Task.isCancelled else { return }
            primary = fetched
        } catch {
            guard !Task.isCancelled else { return }
            loadFailed = true
        }
        isLoading = false
    }
}

private struct SeriesReadOptionsButton: UIViewRepresentable {
    let isEnabled: Bool
    let canChangeReadState: Bool
    let isReadingPaused: Bool
    let language: String
    let markRead: () -> Void
    let stopReading: () -> Void
    let confirmMarkUnread: () -> Void

    func makeUIView(context _: Context) -> UIButton {
        let configuration = AppGlassButtonConfiguration.make(systemImage: "ellipsis")
        let button = UIButton(configuration: configuration, primaryAction: nil)
        button.showsMenuAsPrimaryAction = true
        button.changesSelectionAsPrimaryAction = false
        button.preferredMenuElementOrder = .fixed
        button.accessibilityLabel = AppLocalization.text("작품 읽기 옵션")
        return button
    }

    func updateUIView(_ button: UIButton, context: Context) {
        context.coordinator.markRead = markRead
        context.coordinator.stopReading = stopReading
        context.coordinator.confirmMarkUnread = confirmMarkUnread
        button.isEnabled = isEnabled
        button.accessibilityLabel = AppLocalization.text("작품 읽기 옵션")
        if button.menu == nil || context.coordinator.canChangeReadState != canChangeReadState ||
            context.coordinator.language != language || context.coordinator.isReadingPaused != isReadingPaused
        {
            context.coordinator.canChangeReadState = canChangeReadState
            context.coordinator.language = language
            context.coordinator.isReadingPaused = isReadingPaused
            button.menu = context.coordinator.makeMenu()
        }
    }

    func sizeThatFits(_: ProposedViewSize, uiView _: UIButton, context _: Context) -> CGSize? {
        CGSize(width: 46, height: 46)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var canChangeReadState = true
        var isReadingPaused = false
        var language = ""
        var markRead: () -> Void = {}
        var stopReading: () -> Void = {}
        var confirmMarkUnread: () -> Void = {}

        func makeMenu() -> UIMenu {
            let readAction = UIAction(title: AppLocalization.text("읽음으로 표시"),
                                      image: UIImage(systemName: "checkmark.circle"))
            {
                [weak self] _ in self?.markRead()
            }
            readAction.attributes = canChangeReadState ? [] : .disabled

            let stopAction = UIAction(title: AppLocalization.text("읽기 중단"),
                                      image: UIImage(systemName: "pause.circle"))
            {
                [weak self] _ in self?.stopReading()
            }
            stopAction.attributes = canChangeReadState && !isReadingPaused ? [] : .disabled

            let unreadAction = UIAction(title: AppLocalization.text("읽기 기록 초기화"),
                                        image: UIImage(systemName: "arrow.uturn.backward.circle"))
            {
                [weak self] _ in self?.confirmMarkUnread()
            }
            unreadAction.attributes = canChangeReadState ? .destructive : [.destructive, .disabled]

            return UIMenu(children: [readAction, stopAction, unreadAction])
        }
    }
}

private struct ReadingConflict {
    let identity: String
    let seriesId: Int
    let serverPoint: ContinuePointDto?
    let serverChapter: SeriesChapter
    let localChapter: SeriesChapter
    let localPage: Int
}

private struct ReaderImagePrefetch {
    let chapterID: UUID
    let page: Int
    let task: Task<UIImage?, Never>
}

private struct ChapterCoverView: View {
    let chapter: SeriesChapter
    let seriesCoverColors: [Color]

    var body: some View {
        VStack(alignment: .center, spacing: 8) {
            GeometryReader { geometry in
                ZStack {
                    if let coverURL = chapter.coverImageURL {
                        CoverImageView(url: coverURL, height: geometry.size.height, cornerRadius: 5,
                                       gradientColors: seriesCoverColors)
                    } else {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(LinearGradient(colors: seriesCoverColors, startPoint: .topLeading,
                                                 endPoint: .bottomTrailing))
                            .overlay(VStack {
                                Image(systemName: "book.pages.fill")
                                    .font(.title2)
                                    .foregroundStyle(.white.opacity(0.8))
                                Text("Ch.\(Int(chapter.number))")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.white)
                            })
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
            .aspectRatio(2.0 / 3.0, contentMode: .fit)

            VStack(spacing: 4) {
                Text(chapter.title)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(AppTheme.text)

                Text(chapter.isEpub ? "EPUB" : AppLocalization.format("%d페이지", chapter.pageCount))
                    .font(.caption2)
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
    }
}

private struct ErrorView: View {
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
        .padding(.horizontal, 32)
    }
}

#Preview {
    NavigationStack {
        SeriesDetailView(series: LibrarySeries(kavitaSeriesId: 454,
                                               title: "그리스 로마 신화",
                                               author: "박시연",
                                               coverColorHexes: ["#FF5F6D", "#FFC371"]))
    }
}
