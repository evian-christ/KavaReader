import SwiftUI

struct ReaderView: View {
    let series: LibrarySeries
    let chapter: SeriesChapter
    let serviceFactory: LibraryServiceFactory

    @State private var selection: Int = 1

    var body: some View {
        VStack {
            if chapter.pageCount == 0 {
                ReaderEmptyStateView()
            } else {
                TabView(selection: $selection) {
                    ForEach(1 ... chapter.pageCount, id: \.self) { page in
                        ReaderPageView(series: series,
                                       chapter: chapter,
                                       pageNumber: page,
                                       serviceFactory: serviceFactory)
                            .tag(page)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
            }
        }
        .navigationTitle(chapter.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 8) {
                    Text(chapter.title)
                        .font(.headline)
                    Text("\(selection)/\(max(chapter.pageCount, 1))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .background(Color.black.ignoresSafeArea())
    }
}

private struct ReaderEmptyStateView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "nosign")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("표시할 페이지가 없습니다.")
                .foregroundStyle(.secondary)
        }
        .padding(32)
    }
}

private struct ReaderPageView: View {
    let series: LibrarySeries
    let chapter: SeriesChapter
    let pageNumber: Int
    let serviceFactory: LibraryServiceFactory

    @StateObject private var viewModel: ReaderPageViewModel

    init(series: LibrarySeries,
         chapter: SeriesChapter,
         pageNumber: Int,
         serviceFactory: LibraryServiceFactory)
    {
        self.series = series
        self.chapter = chapter
        self.pageNumber = pageNumber
        self.serviceFactory = serviceFactory
        _viewModel = StateObject(wrappedValue: ReaderPageViewModel(seriesID: series.id,
                                                                   chapterID: chapter.id,
                                                                   pageNumber: pageNumber,
                                                                   serviceFactory: serviceFactory))
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                switch viewModel.phase {
                case .idle, .loading:
                    ProgressView("페이지 \(pageNumber)을 불러오는 중")
                        .progressViewStyle(.circular)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black)
                case let .success(image):
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .background(Color.black)
                        .transition(.opacity)
                case let .failure(message):
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundStyle(.orange)
                        Text(message)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                        Button("다시 시도") {
                            Task { await viewModel.load() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .background(Color.black)
                }
            }
        }
        .task {
            await viewModel.load()
        }
    }
}
