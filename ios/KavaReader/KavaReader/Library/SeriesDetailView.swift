import SwiftUI
import Combine

struct SeriesDetailView: View {
    let series: LibrarySeries

    @AppStorage("server_base_url") private var serverBaseURL: String = ""
    @AppStorage("server_api_key") private var apiKey: String = ""

    @StateObject private var viewModel: SeriesDetailViewModel
    @State private var lastServiceKey: String = ""
    @State private var selectedChapter: SeriesChapter?
    @State private var showReader = false
    @State private var isNavigatingToReader = false
    @State private var hasContinuePoint = false
    @State private var isCheckingContinuePoint = false

    private let chapterGrid = [
        GridItem(.adaptive(minimum: 100), spacing: 12)
    ]

    init(series: LibrarySeries) {
        self.series = series
        _viewModel = StateObject(wrappedValue: SeriesDetailViewModel(service: LibraryServiceFactory(baseURLString: nil,
                                                                                                   apiKey: nil).makeService()))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Hero section with cover and info
                heroSection

                // Chapters section
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
        }
        .background(Color(.systemBackground))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadSeries(force: true)
        }
        .refreshable {
            await loadSeries(force: true)
        }
        .onChange(of: serverBaseURL) {
            Task { await loadSeries(force: true) }
        }
        .onChange(of: apiKey) {
            Task { await loadSeries(force: true) }
        }
        .navigationDestination(isPresented: $isNavigatingToReader) {
            if let selectedChapter = selectedChapter {
                ReaderView(series: series,
                          chapter: selectedChapter,
                          serviceFactory: currentFactory)
            }
        }
    }

    private var heroSection: some View {
        VStack(spacing: 24) {
            // Large cover image
            ZStack {
                if let url = series.coverURL {
                    CoverImageView(url: url, height: 320, cornerRadius: 16, gradientColors: gradientColors)
                } else {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(LinearGradient(colors: gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(height: 320)
                }
            }
            .frame(width: 220, height: 320)
            .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)

            // Title and author
            VStack(spacing: 8) {
                Text(series.title)
                    .font(.title.weight(.bold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)

                if !series.author.isEmpty {
                    Text(series.author)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }

            // Read button
            Button {
                Task {
                    await startReading()
                }
            } label: {
                HStack {
                    if isCheckingContinuePoint {
                        ProgressView()
                            .scaleEffect(0.8)
                            .foregroundStyle(.white)
                    } else {
                        Image(systemName: hasContinuePoint ? "play.circle.fill" : "play.fill")
                        Text(hasContinuePoint ? "계속 읽기" : "읽기 시작")
                            .font(.headline)
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 32)
                .padding(.vertical, 12)
                .background(
                    LinearGradient(colors: gradientColors, startPoint: .leading, endPoint: .trailing)
                )
                .clipShape(RoundedRectangle(cornerRadius: 25))
            }
            .disabled(viewModel.detail?.chapters.isEmpty ?? true || isCheckingContinuePoint)
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 40)
    }

    private func chaptersSection(chapters: [SeriesChapter]) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("챕터")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(chapters.count)화")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)

            LazyVGrid(columns: chapterGrid, spacing: 16) {
                ForEach(chapters) { chapter in
                    NavigationLink {
                        ReaderView(series: series,
                                   chapter: chapter,
                                   serviceFactory: currentFactory)
                    } label: {
                        ChapterCoverView(chapter: chapter, seriesCoverColors: gradientColors)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)
        }
        .padding(.bottom, 32)
    }

    @MainActor
    private var gradientColors: [Color] {
        let colors = series.coverColorHexes.compactMap(Color.init(hex:))
        return colors.isEmpty ? [.purple, .blue] : colors
    }

    private var currentFactory: LibraryServiceFactory {
        LibraryServiceFactory(baseURLString: serverBaseURL, apiKey: apiKey.isEmpty ? nil : apiKey)
    }

    private func loadSeries(force: Bool = false) async {
        updateService(force: force)
        if let kavitaSeriesId = series.kavitaSeriesId {
            await viewModel.load(kavitaSeriesId: kavitaSeriesId, force: force)
            await checkContinuePoint()
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

    private func checkContinuePoint() async {
        guard let kavitaSeriesId = series.kavitaSeriesId else {
            hasContinuePoint = false
            return
        }

        isCheckingContinuePoint = true

        if let kavitaService = currentFactory.makeService() as? KavitaLibraryService {
            do {
                if let continuePoint = try await kavitaService.getContinuePoint(seriesId: kavitaSeriesId) {
                    // pagesRead가 0보다 큰 경우에만 "계속 읽기"로 표시
                    hasContinuePoint = continuePoint.pagesRead > 0
                } else {
                    hasContinuePoint = false
                }
            } catch {
                hasContinuePoint = false
            }
        } else {
            hasContinuePoint = false
        }

        isCheckingContinuePoint = false
    }

    private func startReading() async {

        guard let kavitaSeriesId = series.kavitaSeriesId else {
            // Kavita ID가 없으면 첫 번째 챕터로
            if let firstChapter = viewModel.detail?.chapters.first {
                selectedChapter = firstChapter
                isNavigatingToReader = true
            } else {
            }
            return
        }


        // Continue Point API로 마지막 읽은 위치 확인
        if let kavitaService = currentFactory.makeService() as? KavitaLibraryService {
            do {
                if let continuePoint = try await kavitaService.getContinuePoint(seriesId: kavitaSeriesId) {

                    // 해당 챕터를 찾아서 이동
                    if let targetChapter = viewModel.detail?.chapters.first(where: { $0.kavitaChapterId == continuePoint.chapterId }) {
                        selectedChapter = targetChapter
                        isNavigatingToReader = true
                        return
                    } else {
                    }
                }
            } catch {
            }
        }

        // Continue Point를 찾지 못했거나 에러가 발생한 경우 첫 번째 챕터로
        if let firstChapter = viewModel.detail?.chapters.first {
            selectedChapter = firstChapter
            isNavigatingToReader = true
        } else {
        }
    }
}

private struct ChapterCoverView: View {
    let chapter: SeriesChapter
    let seriesCoverColors: [Color]

    var body: some View {
        VStack(alignment: .center, spacing: 8) {
            ZStack {
                if let coverURL = chapter.coverImageURL {
                    CoverImageView(url: coverURL, height: 130, cornerRadius: 8, gradientColors: seriesCoverColors)
                } else {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(LinearGradient(colors: seriesCoverColors, startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(height: 130)
                        .overlay(
                            VStack {
                                Image(systemName: "book.pages.fill")
                                    .font(.title2)
                                    .foregroundStyle(.white.opacity(0.8))
                                Text("Ch.\(Int(chapter.number))")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.white)
                            }
                        )
                }
            }
            .frame(height: 130)

            VStack(spacing: 4) {
                Text(chapter.title)
                    .font(.caption.weight(.medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)

                Text("\(chapter.pageCount)페이지")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
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
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("다시 시도") {
                retryAction()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 32)
    }
}

#Preview {
    NavigationStack {
        SeriesDetailView(series: LibrarySeries(
            kavitaSeriesId: 454,
            title: "그리스 로마 신화",
            author: "박시연",
            coverColorHexes: ["#FF5F6D", "#FFC371"]
        ))
    }
}