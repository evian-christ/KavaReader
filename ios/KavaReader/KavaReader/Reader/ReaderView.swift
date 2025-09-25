import SwiftUI

struct ReaderView: View {
    let series: LibrarySeries
    let chapter: SeriesChapter
    let serviceFactory: LibraryServiceFactory

    @StateObject private var viewModel: ReaderViewModel
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
        ZStack {
            Color.black
                .ignoresSafeArea(.all)

            // Horizontal scrolling page view
            TabView(selection: $viewModel.currentPage) {
                ForEach(1...viewModel.totalPages, id: \.self) { pageNumber in
                    GeometryReader { geometry in
                        AsyncImage(url: viewModel.pageImageURL(for: pageNumber)) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .clipped()
                        } placeholder: {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        handleTap()
                    }
                    .tag(pageNumber)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            // UI Overlay
            if showUI {
                VStack {
                    // Top bar - Black gradient background
                    HStack(spacing: 0) {
                        // Back button
                        Button(action: {
                            dismiss()
                        }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                        }

                        // Title section
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

                        // Spacer for balance (same width as back button)
                        Spacer()
                            .frame(width: 44, height: 44)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)

                    Spacer()

                    // Bottom bar
                    HStack {
                        // Page indicator
                        Text("\(viewModel.currentPage) / \(viewModel.totalPages)")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(
                                ZStack {
                                    Capsule()
                                        .fill(.ultraThinMaterial)
                                        .opacity(0.8)
                                    Capsule()
                                        .stroke(.white.opacity(0.3), lineWidth: 0.5)
                                    Capsule()
                                        .fill(
                                            LinearGradient(
                                                colors: [.white.opacity(0.2), .clear],
                                                startPoint: .top,
                                                endPoint: .bottom
                                            )
                                        )
                                }
                            )
                            .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)

                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                }
                .background(
                    // Enhanced gradient backgrounds with liquid glass effect
                    VStack(spacing: 0) {
                        ZStack {
                            LinearGradient(
                                colors: [
                                    .black.opacity(0.8),
                                    .black.opacity(0.4),
                                    .clear
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: 120)

                            LinearGradient(
                                colors: [
                                    .white.opacity(0.08),
                                    .clear
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: 60)
                        }

                        Spacer()

                        ZStack {
                            LinearGradient(
                                colors: [
                                    .clear,
                                    .black.opacity(0.4),
                                    .black.opacity(0.8)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: 120)

                            LinearGradient(
                                colors: [
                                    .clear,
                                    .white.opacity(0.08)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: 60)
                        }
                    }
                    .ignoresSafeArea()
                )
                .transition(.opacity)
            }
        }
        .navigationBarHidden(true)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .statusBarHidden(showUI ? false : true)
        .task {
            await viewModel.loadChapter()
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