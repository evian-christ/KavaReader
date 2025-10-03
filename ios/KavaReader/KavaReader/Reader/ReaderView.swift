import SwiftUI

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

struct ReaderView: View {
    // MARK: Lifecycle

    init(series: LibrarySeries, chapter: SeriesChapter, serviceFactory: LibraryServiceFactory) {
        self.series = series
        self.chapter = chapter
        self.serviceFactory = serviceFactory
        _viewModel = StateObject(wrappedValue: ReaderViewModel(series: series,
                                                               chapter: chapter,
                                                               service: serviceFactory.makeService()))
    }

    // MARK: Internal

    let series: LibrarySeries
    let chapter: SeriesChapter
    let serviceFactory: LibraryServiceFactory

    var body: some View {
        GeometryReader { geometry in
            let safeAreaInsets = geometry.safeAreaInsets
            let shouldRemoveTopInset = readerSettings.scrollDirection == .horizontal

            ZStack {
                Color.black
                    .ignoresSafeArea(.all)

                Group {
                    if readerSettings.scrollDirection == .horizontal {
                        TabView(selection: $viewModel.currentPage) {
                            ForEach(1 ... viewModel.totalPages, id: \.self) { pageNumber in
                                ZoomableImageView(pageNumber: pageNumber,
                                                  viewModel: viewModel,
                                                  isActive: viewModel.currentPage == pageNumber,
                                                  pageFitMode: readerSettings.pageFitMode,
                                                  onTap: handleTap,
                                                  onPageChange: { newPage in
                                                      Task {
                                                          await viewModel.goToPage(newPage)
                                                      }
                                                  },
                                                  onInteractionChange: { _ in })
                                    .tag(pageNumber)
                                    .background(FullScreenBackground())
                            }
                        }
                        .tabViewStyle(.page(indexDisplayMode: .never))
                    } else {
                        GeometryReader { geo in
                            ScrollViewReader { scrollProxy in
                                ScrollView(.vertical, showsIndicators: false) {
                                    LazyVStack(spacing: 0) {
                                        ForEach(1 ... viewModel.totalPages, id: \.self) { pageNumber in
                                            ZoomableImageView(pageNumber: pageNumber,
                                                              viewModel: viewModel,
                                                              isActive: true,
                                                              pageFitMode: readerSettings.pageFitMode,
                                                              onTap: handleTap,
                                                              onPageChange: { _ in },
                                                              onInteractionChange: { _ in })
                                                .frame(width: geo.size.width)
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
                                .onPreferenceChange(PageVisibilityPreferenceKey.self) { pages in
                                    updateCurrentPageFromScroll(pages: pages, scrollViewHeight: geo.size.height)
                                }
                                .onChange(of: scrollTarget) { _, newTarget in
                                    if let target = newTarget {
                                        scrollProxy.scrollTo(target, anchor: .top)
                                        scrollTarget = nil
                                    }
                                }
                                .onChange(of: viewModel.currentPage) { oldPage, newPage in
                                    // 초기 로드 시에만 스크롤 (oldPage가 1이고 처음 변경될 때)
                                    if !hasScrolledToInitialPage && newPage > 1 {
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                            scrollProxy.scrollTo(newPage, anchor: .top)
                                            hasScrolledToInitialPage = true
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.top, -safeAreaInsets.top)
                .padding(.bottom, -safeAreaInsets.bottom)
                .padding(.leading, -safeAreaInsets.leading)
                .padding(.trailing, -safeAreaInsets.trailing)
                .ignoresSafeArea(.all)

                if let errorMessage = viewModel.errorMessage {
                    VStack {
                        Spacer()

                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)

                            Text(errorMessage)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white)
                                .multilineTextAlignment(.leading)

                            Spacer()

                            Button("닫기") {
                                viewModel.clearError()
                            }
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.blue)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 12)
                            .fill(.black.opacity(0.8))
                            .overlay(RoundedRectangle(cornerRadius: 12)
                                .stroke(.white.opacity(0.2), lineWidth: 1)))
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
                        .padding(.top, max(safeAreaInsets.top - 24, 0))

                        Spacer()

                        HStack {
                            Spacer()

                            PageStripView(currentPage: $viewModel.currentPage,
                                          totalPages: viewModel.totalPages,
                                          onPageChange: { newPage in
                                              if readerSettings.scrollDirection == .vertical {
                                                  scrollTarget = newPage
                                              }
                                              Task {
                                                  await viewModel.goToPage(newPage)
                                              }
                                          })

                            Spacer()
                        }
                        .padding(.bottom, 8)

                        Rectangle()
                            .fill(Color.clear)
                            .frame(height: safeAreaInsets.bottom)
                    }
                    .background(VStack(spacing: 0) {
                        LinearGradient(colors: [
                            .black.opacity(0.8),
                            .black.opacity(0.4),
                            .clear,
                        ],
                        startPoint: .top,
                        endPoint: .bottom)
                            .frame(height: 120 + safeAreaInsets.top)

                        Spacer()

                        LinearGradient(colors: [
                            .clear,
                            .black.opacity(0.4),
                            .black.opacity(0.8),
                        ],
                        startPoint: .top,
                        endPoint: .bottom)
                            .frame(height: 180 + safeAreaInsets.bottom)
                    }
                    .ignoresSafeArea(.all))
                    .transition(.opacity)
                }
            }
        }
        .navigationBarHidden(true)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .statusBarHidden(showUI ? false : true)
        .onAppear {
            showUI = true
        }
        .task {
            await viewModel.loadChapter()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            // 앱이 백그라운드로 갈 때 진행률 저장
            Task {
                await viewModel.saveProgressNow()
            }
        }
        .onDisappear {
            // 리더 화면을 떠날 때 진행률 저장
            Task {
                await viewModel.saveProgressNow()
            }
            showUI = true
        }
    }

    // MARK: Private

    @StateObject private var viewModel: ReaderViewModel
    @StateObject private var readerSettings = ReaderSettings.shared
    @State private var showUI = true
    @State private var lastTapTime = Date()
    @State private var scrollTarget: Int?
    @State private var hasScrolledToInitialPage = false
    @Environment(\.dismiss) private var dismiss

    private func handleTap() {
        withAnimation(.easeInOut(duration: 0.3)) {
            showUI.toggle()
        }
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
