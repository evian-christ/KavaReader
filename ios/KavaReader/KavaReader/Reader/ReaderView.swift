import SwiftUI
import UIKit

extension Notification.Name {
    static let readerDidClose = Notification.Name("readerDidClose")
    static let readerDidRead = Notification.Name("readerDidRead")
    static let seriesReadStateDidChange = Notification.Name("seriesReadStateDidChange")
}

// Refresh the system status bar after SwiftUI applies its visibility preference.
// This bridge must not change the navigation controller's theme or background.
private struct ReaderStatusBarRefresh: UIViewControllerRepresentable {
    let isHidden: Bool

    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()
        controller.view = UIView()
        controller.view.backgroundColor = .clear
        controller.view.isOpaque = false
        controller.view.isUserInteractionEnabled = false
        return controller
    }

    func updateUIViewController(_ controller: UIViewController, context: Context) {
        guard context.coordinator.lastHidden != isHidden else { return }
        context.coordinator.lastHidden = isHidden
        let coordinator = context.coordinator

        DispatchQueue.main.async { [weak controller] in
            guard coordinator.isActive, let controller else { return }
            var current: UIViewController? = controller
            while let viewController = current {
                viewController.setNeedsStatusBarAppearanceUpdate()
                current = viewController.parent
            }
            controller.view.window?.rootViewController?.setNeedsStatusBarAppearanceUpdate()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    static func dismantleUIViewController(_ controller: UIViewController, coordinator: Coordinator) {
        coordinator.isActive = false
    }

    final class Coordinator {
        var isActive = true
        var lastHidden: Bool?
    }
}

// MARK: - Page Visibility Tracking

struct PageVisibility: Equatable {
    let pageNumber: Int
    let frame: CGRect
}

struct PageVisibilityPreferenceKey: PreferenceKey {
    static var defaultValue: [PageVisibility] = []

    static func reduce(value: inout [PageVisibility], nextValue: () -> [PageVisibility]) {
        value.append(contentsOf: nextValue())
    }
}

private struct ReaderTransitionPage: View {
    let image: UIImage
    let edgeColors: PageEdgeColors

    var body: some View {
        GeometryReader { geometry in
            let imageHeight = geometry.size.width * image.size.height / max(image.size.width, 1)

            ZStack {
                LinearGradient(stops: [
                    .init(color: Color(edgeColors.top), location: 0),
                    .init(color: Color(edgeColors.top), location: 0.5),
                    .init(color: Color(edgeColors.bottom), location: 0.5),
                    .init(color: Color(edgeColors.bottom), location: 1),
                ], startPoint: .top, endPoint: .bottom)

                Image(uiImage: image)
                    .resizable()
                    .frame(width: geometry.size.width, height: imageHeight)
                    .frame(width: geometry.size.width, height: geometry.size.height,
                           alignment: imageHeight > geometry.size.height ? .top : .center)
                    .clipped()
            }
        }
        .allowsHitTesting(false)
    }
}

struct ReaderView: View {
    init(series: LibrarySeries,
         chapter: SeriesChapter,
         serviceFactory: LibraryServiceFactory,
         chapters: [SeriesChapter] = [],
         libraryId: Int? = nil,
         initialPage: Int? = nil,
         preparedImage: UIImage? = nil,
         isContinuePointVerified: Bool = true)
    {
        self.series = series
        self.serviceFactory = serviceFactory
        self.libraryId = libraryId
        self.isContinuePointVerified = isContinuePointVerified
        _currentChapter = State(initialValue: chapter)
        _availableChapters = State(initialValue: chapters)
        _entryPage = State(initialValue: initialPage)
        _entryImage = State(initialValue: preparedImage)
    }

    let series: LibrarySeries
    let serviceFactory: LibraryServiceFactory
    let libraryId: Int?
    let isContinuePointVerified: Bool

    @ViewBuilder
    var body: some View {
        if currentChapter.isEpub {
            EpubReaderView(series: series, volumeID: currentChapter.id)
        } else {
            imageReader
        }
    }

    private var imageReader: some View {
        ReaderChapterView(series: series,
                          chapter: currentChapter,
                          serviceFactory: serviceFactory,
                          libraryId: libraryId,
                          showUI: $showUI,
                          initialPage: entryPage,
                          preparedImage: entryImage,
                          isContinuePointVerified: isContinuePointVerified,
                          previousChapter: adjacentChapter(offset: -1),
                          nextChapter: adjacentChapter(offset: 1)) { chapter, page in
            showUI = true
            entryPage = page
            entryImage = nil
            currentChapter = chapter
        }
        .id(currentChapter.id)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.background.ignoresSafeArea())
        .task {
            guard availableChapters.isEmpty, let seriesId = series.kavitaSeriesId else { return }
            let baseURLString = serviceFactory.baseURLString ?? ""
            let apiKey = serviceFactory.apiKey ?? ""
            let identity = "\(baseURLString)|\(apiKey)"
            if let cached = await ChapterCatalogStore.shared.load(identity: identity, seriesId: seriesId,
                                                                  baseURL: URL(string: baseURLString), apiKey: apiKey)
            {
                availableChapters = cached.chapters
                return
            }
            let generation = await ChapterCatalogStore.shared.currentGeneration()
            guard let detail = try? await serviceFactory.makeService().fetchSeriesDetail(kavitaSeriesId: seriesId)
            else { return }
            availableChapters = detail.chapters
            try? await ChapterCatalogStore.shared.save(detail, identity: identity, seriesId: seriesId,
                                                       generation: generation)
        }
        .statusBarHidden(!showUI)
        .toolbarBackground(.hidden, for: .navigationBar)
        .background(ReaderStatusBarRefresh(isHidden: !showUI)
            .frame(width: 0, height: 0))
    }

    @State private var currentChapter: SeriesChapter
    @State private var availableChapters: [SeriesChapter]
    @State private var entryPage: Int?
    @State private var entryImage: UIImage?
    @State private var showUI = true

    private func adjacentChapter(offset: Int) -> SeriesChapter? {
        let readableChapters = availableChapters.filter { $0.pageCount > 0 }
        guard let index = readableChapters.firstIndex(where: { candidate in
            if let chapterId = currentChapter.kavitaChapterId {
                return candidate.kavitaChapterId == chapterId
            }
            return candidate.id == currentChapter.id
        }) else { return nil }
        var target = index + offset
        if let volumeId = currentChapter.kavitaVolumeId {
            while readableChapters.indices.contains(target),
                  readableChapters[target].kavitaVolumeId == volumeId
            {
                target += offset
            }
        }
        guard readableChapters.indices.contains(target) else { return nil }
        return readableChapters[target]
    }
}

private struct ChapterTransition: Identifiable {
    let chapter: SeriesChapter
    let isNext: Bool

    var id: UUID { chapter.id }
}

private enum ReaderSwipeAxis: Equatable {
    case horizontal
    case vertical
}

private enum ReaderBoundary {
    case previous
    case next
    case both
}

private struct ReaderSpread: Identifiable {
    let firstPage: Int
    let lastPage: Int

    var id: Int { firstPage }
    var pages: [Int] { Array(firstPage ... lastPage) }
}

private struct ReaderChapterView: View {
    // MARK: Lifecycle

    init(series: LibrarySeries,
         chapter: SeriesChapter,
         serviceFactory: LibraryServiceFactory,
         libraryId: Int?,
         showUI: Binding<Bool>,
         initialPage: Int?,
         preparedImage: UIImage?,
         isContinuePointVerified: Bool,
         previousChapter: SeriesChapter?,
         nextChapter: SeriesChapter?,
         onChangeChapter: @escaping (SeriesChapter, Int) -> Void)
    {
        self.series = series
        self.chapter = chapter
        self.serviceFactory = serviceFactory
        self.libraryId = libraryId
        self.previousChapter = previousChapter
        self.nextChapter = nextChapter
        self.onChangeChapter = onChangeChapter
        _showUI = showUI
        let identity = "\(serviceFactory.baseURLString ?? "")|\(serviceFactory.apiKey ?? "")"
        _seriesSettings = StateObject(wrappedValue: SeriesReaderSettings(identity: identity,
                                                                         series: series,
                                                                         global: ReaderSettings.shared))
        _viewModel = StateObject(wrappedValue: ReaderViewModel(series: series,
                                                               chapter: chapter,
                                                               service: serviceFactory.makeService(),
                                                               initialPage: initialPage,
                                                               preparedImage: preparedImage,
                                                               readingIdentity: identity,
                                                               isContinuePointVerified: isContinuePointVerified))
    }

    // MARK: Internal

    let series: LibrarySeries
    let chapter: SeriesChapter
    let serviceFactory: LibraryServiceFactory
    let libraryId: Int?
    let previousChapter: SeriesChapter?
    let nextChapter: SeriesChapter?
    let onChangeChapter: (SeriesChapter, Int) -> Void

    var body: some View {
        ZStack {
            ReaderCanvasHost {
                readerCanvas
            }
            .ignoresSafeArea(.container)

            GeometryReader { geometry in
                let safeAreaInsets = geometry.safeAreaInsets
                let isPhone = UIDevice.current.userInterfaceIdiom == .phone
                let cornerButtonEdgeGap: CGFloat = isPhone ? 24 : safeAreaInsets.bottom + 12
                // Measure the phone controls from the screen edges, including the safe area.
                let leadingControlInset = isPhone
                    ? cornerButtonEdgeGap - safeAreaInsets.leading
                    : max(0, cornerButtonEdgeGap - safeAreaInsets.leading)
                let trailingControlInset = isPhone
                    ? cornerButtonEdgeGap - safeAreaInsets.trailing
                    : max(0, cornerButtonEdgeGap - safeAreaInsets.trailing)
                let bottomControlInset = isPhone ? cornerButtonEdgeGap - safeAreaInsets.bottom : 12

                ZStack {
                    if let errorMessage = viewModel.errorMessage {
                        VStack {
                            Spacer()

                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)

                                Text(AppLocalization.text(errorMessage))
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(AppTheme.text)
                                    .multilineTextAlignment(.leading)

                                Spacer()

                                Button("닫기") {
                                    viewModel.clearError()
                                }
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(AppTheme.accent)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(RoundedRectangle(cornerRadius: 12)
                                .fill(AppTheme.surface.opacity(0.95))
                                .overlay(RoundedRectangle(cornerRadius: 12)
                                    .stroke(AppTheme.text.opacity(0.2), lineWidth: 1)))
                            .padding(.horizontal, 20)
                            .padding(.bottom, max(24, safeAreaInsets.bottom + 60))
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .animation(.easeInOut(duration: 0.3), value: viewModel.errorMessage)
                    }

                    if showUI {
                        VStack(spacing: 0) {
                            HStack(spacing: 0) {
                                Button(action: {
                                    dismiss()
                                }) {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundStyle(.white)
                                        .frame(width: 44, height: 44)
                                }

                                VStack(spacing: 2) {
                                    Text(series.title)
                                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                                        .foregroundStyle(.white)
                                        .lineLimit(1)
                                    Text(chapter.title)
                                        .font(.system(size: 14, weight: .medium, design: .rounded))
                                        .foregroundStyle(.white.opacity(0.8))
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity)

                                Spacer()
                                    .frame(width: 44, height: 44)
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                            .padding(.top, isPhone ? 0 : max(safeAreaInsets.top - 24, 0))

                            Spacer()

                            if viewModel.totalPages > 0 && (isInitialPagePositioned || transitionImage != nil) {
                                ZStack(alignment: .bottom) {
                                    PageStripView(currentPage: $viewModel.currentPage,
                                                  totalPages: viewModel.totalPages,
                                                  isRightToLeft: effectiveScrollDirection.isRightToLeft,
                                                  expandedControlLeadingInset: isPhone
                                                      ? cornerButtonEdgeGap + 44 + 24
                                                      : leadingControlInset + 44 + 40 - 20,
                                                  expandedControlTrailingInset: isPhone
                                                      ? cornerButtonEdgeGap + 44 + 24
                                                      : trailingControlInset + 44 + 40 - 20,
                                                  loadPreview: viewModel.pagePreview,
                                                  onPageChange: selectPage)
                                        .frame(maxWidth: .infinity)
                                        .padding(.leading, isPhone ? -safeAreaInsets.leading : 20)
                                        .padding(.trailing, isPhone ? -safeAreaInsets.trailing : 20)

                                    HStack {
                                        settingsButton
                                        Spacer()
                                        directionButton
                                    }
                                    .padding(.leading, leadingControlInset)
                                    .padding(.trailing, trailingControlInset)
                                }
                                .padding(.bottom, bottomControlInset)
                            }
                        }
                        .background(alignment: .top) {
                            // 상태바 상단부터 기존 UI 배경의 하단까지 그라데이션을 그립니다.
                            LinearGradient(colors: [
                                .black.opacity(0.8),
                                .black.opacity(0.4),
                                .clear,
                            ],
                            startPoint: .top,
                            endPoint: .bottom)
                                .frame(height: 120 + safeAreaInsets.top)
                                .clipped()
                                .offset(y: -safeAreaInsets.top)
                                .allowsHitTesting(false)
                        }
                        .transition(.opacity)
                    }

                    if isSettingsPresented {
                        Color.black.opacity(0.45)
                            .ignoresSafeArea()
                            .contentShape(Rectangle())
                            .onTapGesture(perform: closeReaderSettings)

                        readerSettingsPanel(availableSize: geometry.size)
                            .transition(.scale(scale: 0.94).combined(with: .opacity))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.background.ignoresSafeArea())
        .navigationBarHidden(true)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .alert(item: $pendingTransition) { transition in
            Alert(title: Text(AppLocalization.text(transition.isNext ? "다음 권으로 이동할까요?" : "이전 권으로 이동할까요?")),
                  message: Text(transition.chapter.title),
                  primaryButton: .default(Text("이동")) {
                      viewModel.enqueueProgressSaveNow()
                      viewModel.deactivate()
                      isChangingChapter = true
                      onChangeChapter(transition.chapter,
                                      transition.isNext ? 1 : max(1, transition.chapter.pageCount))
                  },
                  secondaryButton: .cancel(Text("취소")))
        }
        .task {
            viewModel.configureLibraryId(libraryId)
            updatePreloadingLayout()
            await viewModel.loadChapter()
            if effectiveScrollDirection == .vertical && viewModel.currentPage > 1 {
                initialPageToScroll = viewModel.currentPage
            } else {
                isInitialPagePositioned = true
            }
        }
        .onChange(of: effectiveScrollDirection) { _, _ in updatePreloadingLayout() }
        .onChange(of: effectiveHorizontalDisplayMode) { _, _ in updatePreloadingLayout() }
        .onChange(of: effectiveFirstPageAlone) { _, _ in updatePreloadingLayout() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            viewModel.enqueueProgressSaveNow()
        }
        .onDisappear {
            if !isChangingChapter {
                viewModel.enqueueProgressSaveNow()
                if let seriesId = series.kavitaSeriesId {
                    let identity = "\(serviceFactory.baseURLString ?? "")|\(serviceFactory.apiKey ?? "")"
                    Task {
                        await ReaderProgressSaveQueue.shared.wait(identity: identity, seriesId: seriesId)
                        NotificationCenter.default.post(name: .readerDidClose, object: identity)
                    }
                }
            }
            viewModel.deactivate()
        }
    }

    // MARK: Private

    @StateObject private var viewModel: ReaderViewModel
    @StateObject private var readerSettings = ReaderSettings.shared
    @StateObject private var seriesSettings: SeriesReaderSettings
    @Binding private var showUI: Bool
    @State private var lastTapTime = Date()
    @State private var initialPageToScroll: Int?
    @State private var selectedPageToScroll: Int?
    @State private var isInitialPagePositioned = false
    @State private var transitionImage: UIImage?
    @State private var transitionEdgeColors = PageEdgeColors.fallback
    @State private var transitionID = UUID()
    @State private var isAtFirstPageTop = false
    @State private var isAtLastPageBottom = false
    @State private var zoomedPages: Set<Int> = []
    @State private var hasCapturedSwipeStart = false
    @State private var boundarySwipeStart: ReaderBoundary?
    @State private var pendingTransition: ChapterTransition?
    @State private var isChangingChapter = false
    @State private var isSettingsPresented = false
    @Environment(\.dismiss) private var dismiss

    // Status-bar visibility changes only the controls' safe area. The canvas
    // always uses the full container, without applying changing inset offsets.
    private var readerCanvas: some View {
        GeometryReader { readerGeometry in
            ZStack {
                AppTheme.background

                Group {
                    if effectiveScrollDirection.isHorizontal {
                        ReaderHorizontalPager(size: readerGeometry.size,
                                              pageIDs: horizontalSpreads.map(\.id),
                                              selection: horizontalSpreadSelection,
                                              isZoomed: currentHorizontalSpread?.pages.contains(where: zoomedPages.contains) ?? false,
                                              isDoublePage: effectiveHorizontalDisplayMode == .doublePage,
                                              pageCurlEnabled: effectivePageCurlEnabled) { pageID, side in
                            if let spread = horizontalSpreads.first(where: { $0.id == pageID }) {
                                Group {
                                    if !effectivePageCurlEnabled && effectiveHorizontalDisplayMode == .doublePage {
                                        HStack(spacing: 0) {
                                            horizontalSpreadView(spread, size: readerGeometry.size, side: 0)
                                            horizontalSpreadView(spread, size: readerGeometry.size, side: 1)
                                        }
                                    } else {
                                        horizontalSpreadView(spread, size: readerGeometry.size, side: side)
                                    }
                                }
                                .background(FullScreenBackground())
                            }
                        }
                        .id("\(effectiveScrollDirection.rawValue)|\(effectiveHorizontalDisplayMode.rawValue)|\(effectiveFirstPageAlone)|\(effectivePageCurlEnabled)")
                        .simultaneousGesture(boundarySwipeGesture(axis: .horizontal))
                    } else {
                        ScrollViewReader { scrollProxy in
                            ScrollView(.vertical, showsIndicators: false) {
                                LazyVStack(spacing: 0) {
                                    ForEach(1 ... viewModel.totalPages, id: \.self) { pageNumber in
                                        ZoomableImageView(pageNumber: pageNumber,
                                                          viewModel: viewModel,
                                                          isActive: true,
                                                          isReaderUIVisible: showUI,
                                                          scrollDirection: effectiveScrollDirection,
                                                          extendPageEdges: effectiveExtendPageEdges,
                                                          tapEdgesToTurnPages: effectiveTapEdgesToTurnPages,
                                                          turnsPageFromLeftEdge: true,
                                                          turnsPageFromRightEdge: true,
                                                          horizontalImageAlignment: .center,
                                                          minimumViewportHeight: readerGeometry.size.height,
                                                          onTap: handleTap,
                                                          onPageChange: { _ in },
                                                          onFirstPageBack: handleTap,
                                                          onLastPageForward: handleTap,
                                                          onInteractionChange: { isZoomed in
                                                              updateZoomState(pageNumber: pageNumber,
                                                                              isZoomed: isZoomed)
                                                          })
                                            .frame(width: readerGeometry.size.width)
                                            .background(
                                                GeometryReader { itemGeo in
                                                    Color.clear
                                                        .preference(
                                                            key: PageVisibilityPreferenceKey.self,
                                                            value: [
                                                                PageVisibility(
                                                                    pageNumber: pageNumber,
                                                                    frame: itemGeo.frame(in: .named("scroll"))
                                                                )
                                                            ]
                                                        )
                                                }
                                            )
                                            .background(FullScreenBackground())
                                            .id(pageNumber)
                                    }
                                }
                            }
                            .coordinateSpace(name: "scroll")
                            .simultaneousGesture(boundarySwipeGesture(axis: .vertical))
                            .onAppear {
                                if let target = initialPageToScroll {
                                    positionInitialPage(target, using: scrollProxy)
                                }
                            }
                            .onPreferenceChange(PageVisibilityPreferenceKey.self) { pages in
                                updateVerticalBoundaries(pages: pages,
                                                         scrollViewHeight: readerGeometry.size.height)
                                guard isInitialPagePositioned else { return }
                                updateCurrentPageFromScroll(pages: pages,
                                                            scrollViewHeight: readerGeometry.size.height)
                            }
                            .onChange(of: initialPageToScroll) { _, target in
                                guard let target else { return }
                                positionInitialPage(target, using: scrollProxy)
                            }
                            .onChange(of: selectedPageToScroll) { _, target in
                                guard let target else { return }
                                scrollProxy.scrollTo(target, anchor: .top)
                                selectedPageToScroll = nil
                            }
                        }
                    }
                }
                .opacity(isInitialPagePositioned ? 1 : 0)

                if let transitionImage {
                    ReaderTransitionPage(image: transitionImage, edgeColors: transitionEdgeColors)
                }
            }
        }
        .ignoresSafeArea(.container)
    }

    private func updatePreloadingLayout() {
        viewModel.configurePreloadingLayout(
            displayMode: effectiveScrollDirection.isHorizontal ? effectiveHorizontalDisplayMode : .singlePage,
            firstPageAlone: effectiveFirstPageAlone
        )
    }

    private var horizontalSpreads: [ReaderSpread] {
        guard viewModel.totalPages > 0 else { return [] }
        let pageCount = effectiveHorizontalDisplayMode.pageCount
        let startPage = showsFirstPageAlone ? 2 : 1
        var spreads = showsFirstPageAlone ? [ReaderSpread(firstPage: 1, lastPage: 1)] : []
        spreads += stride(from: startPage, through: viewModel.totalPages, by: pageCount).map { firstPage in
            ReaderSpread(firstPage: firstPage,
                         lastPage: min(firstPage + pageCount - 1, viewModel.totalPages))
        }
        return effectiveScrollDirection.isRightToLeft ? Array(spreads.reversed()) : spreads
    }

    private var effectiveScrollDirection: ScrollDirection {
        seriesSettings.usesGlobalSettings ? readerSettings.scrollDirection : seriesSettings.scrollDirection
    }

    private var effectiveHorizontalDisplayMode: HorizontalDisplayMode {
        seriesSettings.usesGlobalSettings ? readerSettings.horizontalDisplayMode : seriesSettings.horizontalDisplayMode
    }

    private var effectiveFirstPageAlone: Bool {
        seriesSettings.usesGlobalSettings ? readerSettings.firstPageAlone : seriesSettings.firstPageAlone
    }

    private var showsFirstPageAlone: Bool {
        effectiveHorizontalDisplayMode == .doublePage && effectiveFirstPageAlone
    }

    private var horizontalSpreadSelection: Binding<Int?> {
        Binding(get: { horizontalSpreadStart(for: viewModel.currentPage) }, set: { firstPage in
            guard let firstPage,
                  firstPage != horizontalSpreadStart(for: viewModel.currentPage) else { return }
            selectPage(firstPage)
        })
    }

    private var currentHorizontalSpread: ReaderSpread? {
        guard viewModel.totalPages > 0 else { return nil }
        let firstPage = horizontalSpreadStart(for: viewModel.currentPage)
        return ReaderSpread(firstPage: firstPage,
                            lastPage: showsFirstPageAlone && firstPage == 1
                                ? 1
                                : min(firstPage + effectiveHorizontalDisplayMode.pageCount - 1,
                                      viewModel.totalPages))
    }

    private func horizontalSpreadStart(for page: Int) -> Int {
        let pageCount = effectiveHorizontalDisplayMode.pageCount
        if showsFirstPageAlone && page <= 1 { return 1 }
        let startPage = showsFirstPageAlone ? 2 : 1
        return (max(page, startPage) - startPage) / pageCount * pageCount + startPage
    }

    private var effectivePageCurlEnabled: Bool {
        seriesSettings.usesGlobalSettings ? readerSettings.pageCurlEnabled : seriesSettings.pageCurlEnabled
    }

    private var effectiveExtendPageEdges: Bool {
        seriesSettings.usesGlobalSettings ? readerSettings.extendPageEdges : seriesSettings.extendPageEdges
    }

    private var effectiveTapEdgesToTurnPages: Bool {
        seriesSettings.usesGlobalSettings ? readerSettings.tapEdgesToTurnPages : seriesSettings.tapEdgesToTurnPages
    }

    private var directionButton: some View {
        readerCornerButton(systemName: effectiveScrollDirection.directionSymbol,
                           accessibilityLabel: AppLocalization.format(
                               "읽기 방향: %@", effectiveScrollDirection.displayName))
        {
            cycleReadingDirection()
        }
    }

    private var settingsButton: some View {
        readerCornerButton(systemName: "gearshape",
                           accessibilityLabel: AppLocalization.text("읽기 설정"))
        {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                isSettingsPresented = true
            }
        }
    }

    private func readerCornerButton(systemName: String, accessibilityLabel: String,
                                    action: @escaping () -> Void) -> some View
    {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .modifier(ReaderGlassLabelAppearance())
                .frame(width: 44, height: 44)
        }
        .modifier(ReaderGlassButtonAppearance())
        .buttonBorderShape(.circle)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private func horizontalSpreadView(_ spread: ReaderSpread, size: CGSize, side: Int?) -> some View {
        let orderedPages = effectiveScrollDirection.isRightToLeft
            ? Array(spread.pages.reversed()) : spread.pages

        if let side {
            // Give UIKit one image per face, with the spine at the center.
            // The cover occupies the outer half; an unpaired final page keeps
            // its normal reading-side position. Empty faces are real blanks.
            let singlePageSide = showsFirstPageAlone && spread.firstPage == 1 ? 1 : 0
            let occupiedSide = effectiveScrollDirection.isRightToLeft ? 1 - singlePageSide : singlePageSide
            if orderedPages.count == 2 {
                horizontalPageView(orderedPages[side], in: spread, viewportHeight: size.height,
                                   isBookFace: true)
                    .frame(width: size.width / 2, height: size.height)
            } else if side == occupiedSide {
                horizontalPageView(spread.firstPage, in: spread, viewportHeight: size.height,
                                   isBookFace: true)
                    .frame(width: size.width / 2, height: size.height)
            } else {
                AppTheme.background
                    .frame(width: size.width / 2, height: size.height)
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        let width = size.width / 2
                        let edgeWidth = min(100, width * 0.25)
                        let isOuterEdge = side == 0 ? location.x < edgeWidth : location.x > width - edgeWidth
                        let isZoomed = spread.pages.contains(where: zoomedPages.contains)
                        if effectiveTapEdgesToTurnPages && isOuterEdge && !isZoomed {
                            turnHorizontalSpread(spread, forward: effectiveScrollDirection.isRightToLeft ? side == 0 : side == 1)
                        } else {
                            handleTap()
                        }
                    }
            }
        } else {
            horizontalPageView(spread.firstPage, in: spread, viewportHeight: size.height)
                .frame(width: size.width, height: size.height)
        }
    }

    private func horizontalPageView(_ pageNumber: Int, in spread: ReaderSpread,
                                    viewportHeight: CGFloat, isBookFace: Bool = false) -> some View
    {
        let isSinglePage = !isBookFace && spread.firstPage == spread.lastPage
        let isLeftPage: Bool = if isBookFace && spread.firstPage == spread.lastPage {
            (showsFirstPageAlone && spread.firstPage == 1) == effectiveScrollDirection.isRightToLeft
        } else {
            effectiveScrollDirection.isRightToLeft
                ? pageNumber == spread.lastPage : pageNumber == spread.firstPage
        }

        return ZoomableImageView(pageNumber: pageNumber,
                                 viewModel: viewModel,
                                 isActive: currentHorizontalSpread?.id == spread.id,
                                 isReaderUIVisible: showUI,
                                 scrollDirection: effectiveScrollDirection,
                                 extendPageEdges: effectiveExtendPageEdges,
                                 tapEdgesToTurnPages: effectiveTapEdgesToTurnPages,
                                 turnsPageFromLeftEdge: isSinglePage || isLeftPage,
                                 turnsPageFromRightEdge: isSinglePage || !isLeftPage,
                                 horizontalImageAlignment: isSinglePage ? .center : (isLeftPage ? .trailing : .leading),
                                 minimumViewportHeight: viewportHeight,
                                 onTap: handleTap,
                                 onPageChange: { nextPage in
                                     turnHorizontalSpread(spread, forward: nextPage > pageNumber)
                                 },
                                 onFirstPageBack: {
                                     turnHorizontalSpread(spread, forward: false)
                                 },
                                 onLastPageForward: {
                                     turnHorizontalSpread(spread, forward: true)
                                 },
                                 onInteractionChange: { isZoomed in
                                     updateZoomState(pageNumber: pageNumber, isZoomed: isZoomed)
                                 })
    }

    private func turnHorizontalSpread(_ spread: ReaderSpread, forward: Bool) {
        guard currentHorizontalSpread?.id == spread.id else { return }
        let target = forward ? spread.lastPage + 1 : spread.firstPage - 1
        if (1 ... viewModel.totalPages).contains(target) {
            selectPage(horizontalSpreadStart(for: target))
        } else {
            requestTransition(isNext: forward)
        }
    }

    private func readerSettingsPanel(availableSize: CGSize) -> some View {
        let panelWidth = min(max(availableSize.width - 24, 0), 460)
        let contentWidth = max(panelWidth - 64, 0)

        return VStack(spacing: 0) {
            HStack {
                Text("읽기 설정")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button(action: closeReaderSettings) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(AppTheme.text)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(Text("닫기"))
            }
            .frame(height: 44)

            Picker("설정 범위", selection: usesGlobalSettingsBinding) {
                Text("글로벌").tag(true)
                Text("이 만화").tag(false)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.vertical, 14)

            Divider()
            ScrollView {
                VStack(spacing: 0) {
                    HStack {
                        readerSettingsLabel("읽기 방향", systemImage: "arrow.left.and.right")
                        Spacer()
                        Picker("읽기 방향", selection: readingDirectionBinding) {
                            ForEach(ScrollDirection.allCases) { direction in
                                Text(direction.displayName).tag(direction)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                    .frame(height: 56)

                    if effectiveScrollDirection.isHorizontal {
                        Divider()

                        readerSettingsToggle("페이지 넘김 효과",
                                             systemImage: "book.pages",
                                             isOn: pageCurlEnabledBinding,
                                             rowWidth: contentWidth)

                        Divider()

                        HStack {
                            readerSettingsLabel("표시 방식", systemImage: "rectangle.on.rectangle")
                            Spacer()
                            Picker("표시 방식", selection: horizontalDisplayModeBinding) {
                                ForEach(HorizontalDisplayMode.allCases) { mode in
                                    Text(mode.displayName).tag(mode)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }
                        .frame(height: 56)

                        if effectiveHorizontalDisplayMode == .doublePage {
                            Divider()

                            readerSettingsToggle("첫 페이지 단독 표시",
                                                 systemImage: "doc",
                                                 isOn: firstPageAloneBinding,
                                                 rowWidth: contentWidth)
                        }
                    }

                    Divider()

                    readerSettingsToggle("페이지 색으로 여백 채우기",
                                         systemImage: "paintpalette",
                                         isOn: extendPageEdgesBinding,
                                         rowWidth: contentWidth)

                    Divider()

                    readerSettingsToggle("가장자리 탭으로 페이지 넘기기",
                                         systemImage: "hand.tap",
                                         isOn: tapEdgesToTurnPagesBinding,
                                         rowWidth: contentWidth)
                }
                .frame(width: contentWidth)
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
            .frame(width: contentWidth)
        }
        .frame(width: contentWidth)
        .padding(.horizontal, 32)
        .padding(.vertical, 16)
        .frame(width: panelWidth,
               height: min(max(availableSize.height - 40, 0), effectiveScrollDirection.isHorizontal
                   ? (effectiveHorizontalDisplayMode == .doublePage ? 478 : 421) : 307))
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
    }

    private func readerSettingsLabel(_ title: LocalizedStringKey, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(AppTheme.accent)
                .frame(width: 24)
            Text(title)
                .font(.subheadline)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func readerSettingsToggle(_ title: LocalizedStringKey, systemImage: String,
                                      isOn: Binding<Bool>, rowWidth: CGFloat) -> some View
    {
        let switchWidth: CGFloat = 72
        let spacing: CGFloat = 12

        return HStack(spacing: spacing) {
            readerSettingsLabel(title, systemImage: systemImage)
                .frame(width: max(rowWidth - switchWidth - spacing, 0), alignment: .leading)

            Toggle(title, isOn: isOn)
                .labelsHidden()
                .fixedSize()
                .frame(width: switchWidth, alignment: .trailing)
                .accessibilityLabel(title)
        }
        .frame(width: rowWidth)
        .frame(minHeight: 56)
    }

    private var readingDirectionBinding: Binding<ScrollDirection> {
        Binding(get: { effectiveScrollDirection },
                set: { changeReadingDirection(to: $0) })
    }

    private var horizontalDisplayModeBinding: Binding<HorizontalDisplayMode> {
        Binding(get: { effectiveHorizontalDisplayMode }, set: { mode in
            guard mode != effectiveHorizontalDisplayMode else { return }
            zoomedPages.removeAll()
            if seriesSettings.usesGlobalSettings {
                readerSettings.horizontalDisplayMode = mode
            } else {
                seriesSettings.horizontalDisplayMode = mode
            }
        })
    }

    private var firstPageAloneBinding: Binding<Bool> {
        Binding(get: { effectiveFirstPageAlone }, set: { value in
            guard value != effectiveFirstPageAlone else { return }
            zoomedPages.removeAll()
            if seriesSettings.usesGlobalSettings {
                readerSettings.firstPageAlone = value
            } else {
                seriesSettings.firstPageAlone = value
            }
        })
    }

    private var usesGlobalSettingsBinding: Binding<Bool> {
        Binding(get: { seriesSettings.usesGlobalSettings },
                set: { changeSettingsScope(useGlobal: $0) })
    }

    private var pageCurlEnabledBinding: Binding<Bool> {
        Binding(get: { effectivePageCurlEnabled }, set: { value in
            guard value != effectivePageCurlEnabled else { return }
            zoomedPages.removeAll()
            if seriesSettings.usesGlobalSettings {
                readerSettings.pageCurlEnabled = value
            } else {
                seriesSettings.pageCurlEnabled = value
            }
        })
    }

    private var extendPageEdgesBinding: Binding<Bool> {
        Binding(get: { effectiveExtendPageEdges }, set: { value in
            if seriesSettings.usesGlobalSettings {
                readerSettings.extendPageEdges = value
            } else {
                seriesSettings.extendPageEdges = value
            }
        })
    }

    private var tapEdgesToTurnPagesBinding: Binding<Bool> {
        Binding(get: { effectiveTapEdgesToTurnPages }, set: { value in
            if seriesSettings.usesGlobalSettings {
                readerSettings.tapEdgesToTurnPages = value
            } else {
                seriesSettings.tapEdgesToTurnPages = value
            }
        })
    }

    private func closeReaderSettings() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            isSettingsPresented = false
        }
    }

    private func handleTap() {
        showUI.toggle()
    }

    private func cycleReadingDirection() {
        changeReadingDirection(to: effectiveScrollDirection.nextDirection)
    }

    private func changeReadingDirection(to nextDirection: ScrollDirection) {
        applyDirectionChange(to: nextDirection) {
            if seriesSettings.usesGlobalSettings {
                readerSettings.scrollDirection = nextDirection
            } else {
                seriesSettings.scrollDirection = nextDirection
            }
        }
    }

    private func changeSettingsScope(useGlobal: Bool) {
        guard seriesSettings.usesGlobalSettings != useGlobal else { return }
        zoomedPages.removeAll()
        let nextDirection = useGlobal
            ? readerSettings.scrollDirection
            : seriesSettings.localDirection(or: readerSettings)
        applyDirectionChange(to: nextDirection) {
            seriesSettings.setUsesGlobalSettings(useGlobal, global: readerSettings)
        }
    }

    private func applyDirectionChange(to nextDirection: ScrollDirection, update: () -> Void) {
        guard nextDirection != effectiveScrollDirection else {
            update()
            return
        }
        zoomedPages.removeAll()
        initialPageToScroll = nil
        selectedPageToScroll = nil
        transitionID = UUID()
        transitionImage = nil

        if nextDirection == .vertical && viewModel.currentPage > 1 {
            isInitialPagePositioned = false
            let page = viewModel.currentPage
            transitionImage = viewModel.getPreloadedImage(for: page)
            if let transitionImage {
                transitionEdgeColors = effectiveExtendPageEdges ? PageEdgeColors(image: transitionImage) : .fallback
            }
            update()
            let expectedTransition = transitionID
            DispatchQueue.main.async {
                guard transitionID == expectedTransition,
                      effectiveScrollDirection == .vertical else { return }
                initialPageToScroll = page
            }
        } else {
            isInitialPagePositioned = true
            update()
        }
    }

    private func positionInitialPage(_ page: Int, using scrollProxy: ScrollViewProxy) {
        let expectedTransition = transitionID
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            guard transitionID == expectedTransition, initialPageToScroll == page else { return }
            scrollProxy.scrollTo(page, anchor: .top)
            initialPageToScroll = nil
            isInitialPagePositioned = true
            if transitionImage != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                    guard transitionID == expectedTransition,
                          effectiveScrollDirection == .vertical else { return }
                    withAnimation(.easeOut(duration: 0.12)) {
                        transitionImage = nil
                    }
                }
            }
        }
    }

    private func selectPage(_ page: Int) {
        guard (1 ... viewModel.totalPages).contains(page) else { return }
        if effectiveScrollDirection == .vertical {
            selectedPageToScroll = page
            Task {
                await viewModel.goToPage(page)
            }
        } else {
            viewModel.currentPage = page
        }
    }

    private func updateZoomState(pageNumber: Int, isZoomed: Bool) {
        if isZoomed {
            zoomedPages.insert(pageNumber)
        } else {
            zoomedPages.remove(pageNumber)
        }
    }

    private func updateVerticalBoundaries(pages: [PageVisibility], scrollViewHeight: CGFloat) {
        if let firstPage = pages.first(where: { $0.pageNumber == 1 }) {
            isAtFirstPageTop = firstPage.frame.minY >= -2
        } else {
            isAtFirstPageTop = false
        }
        if let lastPage = pages.first(where: { $0.pageNumber == viewModel.totalPages }) {
            isAtLastPageBottom = lastPage.frame.maxY <= scrollViewHeight + 2
        } else {
            isAtLastPageBottom = false
        }
    }

    private func boundarySwipeGesture(axis: ReaderSwipeAxis) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { _ in
                guard !hasCapturedSwipeStart else { return }
                hasCapturedSwipeStart = true
                let isCurrentPageZoomed = axis == .horizontal
                    ? (currentHorizontalSpread?.pages.contains(where: zoomedPages.contains) ?? false)
                    : zoomedPages.contains(viewModel.currentPage)
                guard pendingTransition == nil,
                      !isCurrentPageZoomed
                else { return }

                switch axis {
                case .horizontal:
                    boundarySwipeStart = availableBoundary(previous: currentHorizontalSpread?.firstPage == 1,
                                                           next: currentHorizontalSpread?.lastPage == viewModel.totalPages)
                case .vertical:
                    boundarySwipeStart = availableBoundary(previous: isAtFirstPageTop,
                                                           next: isAtLastPageBottom)
                }
            }
            .onEnded { value in
                defer {
                    hasCapturedSwipeStart = false
                    boundarySwipeStart = nil
                }
                guard let boundary = boundarySwipeStart, pendingTransition == nil else { return }
                let travel = axis == .horizontal ? value.translation.width : value.translation.height
                let crossTravel = axis == .horizontal ? value.translation.height : value.translation.width
                guard abs(travel) >= 70, abs(travel) > abs(crossTravel) * 1.5 else { return }

                let movesForward = axis == .horizontal && effectiveScrollDirection.isRightToLeft
                    ? travel > 0
                    : travel < 0

                switch (boundary, movesForward) {
                case (.previous, false), (.both, false):
                    requestTransition(isNext: false)
                case (.next, true), (.both, true):
                    requestTransition(isNext: true)
                default:
                    break
                }
            }
    }

    private func availableBoundary(previous: Bool, next: Bool) -> ReaderBoundary? {
        let canGoBack = previous && previousChapter != nil
        let canGoForward = next && nextChapter != nil
        if canGoBack && canGoForward { return .both }
        if canGoBack { return .previous }
        if canGoForward { return .next }
        return nil
    }

    private func requestTransition(isNext: Bool) {
        guard pendingTransition == nil,
              let target = isNext ? nextChapter : previousChapter
        else { return }
        pendingTransition = ChapterTransition(chapter: target, isNext: isNext)
    }

    private func updateCurrentPageFromScroll(pages: [PageVisibility], scrollViewHeight: CGFloat) {
        // 화면 중앙에 가장 가까운 페이지를 찾음
        let scrollCenter = scrollViewHeight / 2

        let visiblePage = pages
            .filter { page in
                // 화면에 보이는 페이지만 고려
                let pageTop = page.frame.minY
                let pageBottom = page.frame.maxY
                return pageBottom > 0 && pageTop < scrollViewHeight
            }
            .min { page1, page2 in
                // 화면 중앙에 더 가까운 페이지 선택
                let distance1 = abs(page1.frame.midY - scrollCenter)
                let distance2 = abs(page2.frame.midY - scrollCenter)
                return distance1 < distance2
            }

        if let page = visiblePage, page.pageNumber != viewModel.currentPage {
            Task {
                await viewModel.updateCurrentPage(page.pageNumber)
            }
        }
    }
}

#Preview {
    NavigationStack {
        ReaderView(series: LibrarySeries(kavitaSeriesId: 454,
                                         title: "그리스 로마 신화",
                                         author: "박시연",
                                         coverColorHexes: ["#FF5F6D", "#FFC371"]),
                   chapter: SeriesChapter(id: UUID(),
                                          title: "Volume 1",
                                          number: 1.0,
                                          pageCount: 188,
                                          kavitaVolumeId: 7413),
                   serviceFactory: LibraryServiceFactory(baseURLString: nil, apiKey: nil))
    }
}
