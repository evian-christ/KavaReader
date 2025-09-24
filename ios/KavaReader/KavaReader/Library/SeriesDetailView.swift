import SwiftUI

struct SeriesDetailView: View {
    let series: LibrarySeries

    @AppStorage("server_base_url") private var serverBaseURL: String = ""
    @AppStorage("server_api_key") private var serverAPIKey: String = ""

    @StateObject private var viewModel: SeriesDetailViewModel
    @State private var lastServiceKey: String = ""

    init(series: LibrarySeries) {
        self.series = series
        _viewModel = StateObject(wrappedValue: SeriesDetailViewModel(service: LibraryServiceFactory(baseURLString: nil,
                                                                                                   apiKey: nil).makeService()))
    }

    var body: some View {
        Group {
            if let detail = viewModel.detail {
                List {
                    SeriesHeaderView(series: detail)
                        .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 8, trailing: 16))
                        .listRowSeparator(.hidden)

                    Section(header: Text("챕터")) {
                        ForEach(detail.chapters) { chapter in
                            NavigationLink {
                                ReaderView(series: series,
                                           chapter: chapter,
                                           serviceFactory: currentFactory)
                            } label: {
                                ChapterRowView(chapter: chapter)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            } else if viewModel.isLoading {
                ProgressView("시리즈 정보를 불러오는 중")
                    .progressViewStyle(.circular)
            } else if let error = viewModel.errorMessage {
                DetailErrorView(message: error) {
                    Task { await loadSeries(force: true) }
                }
            } else {
                DetailErrorView(message: "시리즈 정보를 찾을 수 없습니다.") {
                    Task { await loadSeries(force: true) }
                }
            }
        }
        .navigationTitle(series.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadSeries(force: true)
        }
        .refreshable {
            await loadSeries(force: true)
        }
        .onChange(of: serverBaseURL) { _ in
            Task { await loadSeries(force: true) }
        }
        .onChange(of: serverAPIKey) { _ in
            Task { await loadSeries(force: true) }
        }
    }

    private var currentFactory: LibraryServiceFactory {
        LibraryServiceFactory(baseURLString: serverBaseURL, apiKey: serverAPIKey)
    }

    private func loadSeries(force: Bool) async {
        updateService(force: force)
        await viewModel.load(seriesID: series.id, force: force)
    }

    private func updateService(force: Bool) {
        let key = "\(serverBaseURL)|\(serverAPIKey)"
        if force || key != lastServiceKey {
            viewModel.updateService(currentFactory.makeService())
            lastServiceKey = key
        }
    }
}

private struct SeriesHeaderView: View {
    let series: SeriesDetail

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(series.title)
                .font(.title2.weight(.semibold))
            Text(series.author)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if !series.summary.isEmpty {
                Text(series.summary)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(.secondarySystemBackground)))
    }
}

private struct ChapterRowView: View {
    let chapter: SeriesChapter

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(chapter.title)
                    .font(.headline)
                Text("\(chapter.pageCount)페이지")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 8)
    }
}

private struct DetailErrorView: View {
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
        .padding(32)
    }
}
