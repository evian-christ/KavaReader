import SwiftUI

struct ContentView: View {
    // MARK: Internal

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView("라이브러리를 불러오는 중")
                        .progressViewStyle(.circular)
                } else if let message = viewModel.errorMessage {
                    LibraryErrorView(message: message) {
                        Task {
                            await refreshLibrary(force: true)
                        }
                    }
                } else if filteredSections.isEmpty {
                    LibraryEmptyView(query: searchText)
                } else {
                    libraryList
                }
            }
            .navigationTitle("라이브러리")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "작가, 제목, 태그 검색")
            .task {
                await refreshLibrary(force: true)
            }
            .refreshable {
                await refreshLibrary(force: true)
            }
        }
        .navigationDestination(for: LibrarySeries.self) { series in
            Text("\(series.title) 상세 보기")
                .font(.title)
                .padding()
        }
        .onChange(of: serverBaseURL) { _ in
            Task { await refreshLibrary(force: true) }
        }
        .onChange(of: serverAPIKey) { _ in
            Task { await refreshLibrary(force: true) }
        }
    }

    // MARK: Private

    @AppStorage("server_base_url") private var serverBaseURL: String = ""
    @AppStorage("server_api_key") private var serverAPIKey: String = ""

    @StateObject private var viewModel =
        LibraryViewModel(service: LibraryServiceFactory(baseURLString: nil, apiKey: nil).makeService())
    @State private var searchText: String = ""
    @State private var lastServiceKey: String = ""

    private let grid = [GridItem(.adaptive(minimum: 140), spacing: 24)]

    private var filteredSections: [LibrarySection] {
        viewModel.filteredSections(query: searchText)
    }

    private var libraryList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 32) {
                ForEach(filteredSections) { section in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(section.title)
                                .font(.title2.weight(.semibold))
                            Spacer()
                            Button("모두 보기") {}
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        LazyVGrid(columns: grid, spacing: 24) {
                            ForEach(section.items) { item in
                                NavigationLink(value: item) {
                                    LibraryCoverView(series: item)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 32)
        }
        .background(Color(.systemBackground))
    }

    private func refreshLibrary(force: Bool = false) async {
        let key = serviceSignature()
        if force || key != lastServiceKey {
            let factory = LibraryServiceFactory(baseURLString: serverBaseURL, apiKey: serverAPIKey)
            viewModel.updateService(factory.makeService())
            lastServiceKey = key
        }
        await viewModel.load()
    }

    private func serviceSignature() -> String {
        "\(serverBaseURL)|\(serverAPIKey)"
    }
}

private struct LibraryCoverView: View {
    // MARK: Internal

    let series: LibrarySeries

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(LinearGradient(colors: gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(height: 200)
                VStack(alignment: .leading, spacing: 4) {
                    Text(series.title)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    Text(series.author)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                }
                .padding(16)
            }
        }
    }

    // MARK: Private

    private var gradientColors: [Color] {
        let colors = series.coverColorHexes.compactMap(Color.init(hex:))
        return colors.isEmpty ? [.purple, .blue] : colors
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

private struct LibraryEmptyView: View {
    let query: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(query.isEmpty ? "표시할 만화가 없습니다." : "검색 결과가 없습니다.")
                .foregroundStyle(.secondary)
        }
        .padding(32)
    }
}

#Preview {
    ContentView()
}
