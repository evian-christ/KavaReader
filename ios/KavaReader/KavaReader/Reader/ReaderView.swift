import SwiftUI

struct ReaderView: View {
    let series: LibrarySeries
    let chapter: SeriesChapter
    let serviceFactory: LibraryServiceFactory

    @StateObject private var viewModel: ReaderViewModel
    @StateObject private var readerSettings = ReaderSettings.shared
    @State private var showUI = true
    @State private var lastTapTime = Date()
    @Environment(\.dismiss) private var dismiss

    init(series: LibrarySeries, chapter: SeriesChapter, serviceFactory: LibraryServiceFactory) {
        self.series = series
        self.chapter = chapter
        self.serviceFactory = serviceFactory
        _viewModel = StateObject(wrappedValue: ReaderViewModel(
            series: series,
            chapter: chapter,
            service: serviceFactory.makeService()
        ))
    }

    var body: some View {
        GeometryReader { geometry in
            let safeAreaInsets = geometry.safeAreaInsets

            ZStack {
                Color.black
                    .ignoresSafeArea(.all)

                Group {
                    if readerSettings.scrollDirection == .horizontal {
                        TabView(selection: $viewModel.currentPage) {
                            ForEach(1...viewModel.totalPages, id: \.self) { pageNumber in
                                ZoomableImageView(
                                    pageNumber: pageNumber,
                                    viewModel: viewModel,
                                    isActive: viewModel.currentPage == pageNumber,
                                    pageFitMode: readerSettings.pageFitMode,
                                    onTap: handleTap,
                                    onPageChange: { newPage in
                                        Task {
                                            await viewModel.goToPage(newPage)
                                        }
                                    },
                                    onInteractionChange: { _ in }
                                )
                                .tag(pageNumber)
                                .background(FullScreenBackground())
                            }
                        }
                        .tabViewStyle(.page(indexDisplayMode: .never))
                    } else {
                        ScrollView(.vertical, showsIndicators: false) {
                            LazyVStack(spacing: 0) {
                                ForEach(1...viewModel.totalPages, id: \.self) { pageNumber in
                                    ZoomableImageView(
                                        pageNumber: pageNumber,
                                        viewModel: viewModel,
                                        isActive: true,
                                        pageFitMode: readerSettings.pageFitMode,
                                        onTap: handleTap,
                                        onPageChange: { _ in },
                                        onInteractionChange: { _ in }
                                    )
                                    .background(FullScreenBackground())
                                }
                            }
                        }
                    }
                }
                .padding(.top, -safeAreaInsets.top)
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
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.black.opacity(0.8))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(.white.opacity(0.2), lineWidth: 1)
                                )
                        )
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

                            PageStripView(
                                currentPage: $viewModel.currentPage,
                                totalPages: viewModel.totalPages,
                                onPageChange: { newPage in
                                    Task {
                                        await viewModel.goToPage(newPage)
                                    }
                                }
                            )

                            Spacer()
                        }
                        .padding(.bottom, 8)

                        Rectangle()
                            .fill(Color.clear)
                            .frame(height: safeAreaInsets.bottom)
                    }
                    .background(
                        VStack(spacing: 0) {
                            LinearGradient(
                                colors: [
                                    .black.opacity(0.8),
                                    .black.opacity(0.4),
                                    .clear
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: 120 + safeAreaInsets.top)

                            Spacer()

                            LinearGradient(
                                colors: [
                                    .clear,
                                    .black.opacity(0.4),
                                    .black.opacity(0.8)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: 180 + safeAreaInsets.bottom)
                        }
                        .ignoresSafeArea(.all)
                    )
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

    private func handleTap() {
        withAnimation(.easeInOut(duration: 0.3)) {
            showUI.toggle()
        }
    }
}


#Preview {
    NavigationStack {
        ReaderView(
            series: LibrarySeries(
                kavitaSeriesId: 454,
                title: "그리스 로마 신화",
                author: "박시연",
                coverColorHexes: ["#FF5F6D", "#FFC371"]
            ),
            chapter: SeriesChapter(
                id: UUID(),
                title: "Volume 1",
                number: 1.0,
                pageCount: 188,
                kavitaVolumeId: 7413
            ),
            serviceFactory: LibraryServiceFactory(baseURLString: nil, apiKey: nil)
        )
    }
}
