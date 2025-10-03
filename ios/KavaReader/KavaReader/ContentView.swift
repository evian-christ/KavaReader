import SwiftUI

struct SectionNavigation: Hashable {
    let title: String
}

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
                await refreshLibrary(force: false) // Only load if not already loaded
            }
            .refreshable {
                await refreshLibrary(force: true) // Force refresh on pull-to-refresh
            }
            .navigationDestination(for: LibrarySeries.self) { series in
                SeriesDetailView(series: series)
            }
            .navigationDestination(for: SectionNavigation.self) { sectionNav in
                SectionDetailView(sectionTitle: sectionNav.title)
            }
        }
        .onChange(of: serverBaseURL) {
            Task { await refreshLibrary(force: true) }
        }
    }

    // MARK: Private

    @AppStorage("server_base_url") private var serverBaseURL: String = ""
    @AppStorage("server_api_key") private var apiKey: String = ""

    @StateObject private var viewModel =
        LibraryViewModel(service: LibraryServiceFactory(baseURLString: nil, apiKey: nil).makeService())
    @State private var searchText: String = ""
    @State private var lastServiceKey: String = ""

    // Removed grid layout for horizontal scroll

    private var filteredSections: [LibrarySection] {
        viewModel.filteredSections(query: searchText)
    }

    private var libraryList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 32) {
                // 이어서 읽기 섹션
                if !viewModel.continueReadingItems.isEmpty {
                    continueReadingSection
                }

                // 기존 라이브러리 섹션들
                ForEach(filteredSections) { section in
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text(section.title)
                                .font(.title2.weight(.semibold))
                            Spacer()
                        }
                        .padding(.horizontal, 28)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 16) {
                                // Show up to 8 series items
                                ForEach(section.series) { item in
                                    NavigationLink(value: item) {
                                        LibraryCoverView(series: item)
                                    }
                                    .buttonStyle(.plain)
                                }

                                // Add "More" button as 9th item
                                NavigationLink(value: SectionNavigation(title: section.title)) {
                                    MoreButtonView()
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 28)
                        }
                    }
                }
            }
            .padding(.top, 32)
        }
        .background(Color(.systemBackground))
    }

    private var continueReadingSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("이어서 읽기")
                    .font(.title2.weight(.semibold))
                Spacer()
            }
            .padding(.horizontal, 28)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(viewModel.continueReadingItems) { item in
                        NavigationLink(destination: ReaderView(series: item.series,
                                                               chapter: item.lastReadChapter,
                                                               serviceFactory: LibraryServiceFactory(baseURLString: serverBaseURL,
                                                                                                     apiKey: apiKey
                                                                                                         .isEmpty ?
                                                                                                         nil :
                                                                                                         apiKey)))
                        {
                            ContinueReadingItemView(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 28)
            }
        }
    }

    private func refreshLibrary(force: Bool = false) async {
        let key = serviceSignature()
        if force || key != lastServiceKey {
            let factory = LibraryServiceFactory(baseURLString: serverBaseURL, apiKey: apiKey.isEmpty ? nil : apiKey)
            viewModel.updateService(factory.makeService())
            lastServiceKey = key
        }
        await viewModel.load(force: force)
    }

    private func serviceSignature() -> String {
        return "\(serverBaseURL)|\(apiKey)"
    }
}

private struct LibraryCoverView: View {
    // MARK: Internal

    let series: LibrarySeries

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .bottomLeading) {
                if let url = series.coverURL {
                    CoverImageView(url: url, height: 180, cornerRadius: 12, gradientColors: gradientColors)
                } else {
                    // Fallback view when no cover URL - show title and author
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(LinearGradient(colors: gradientColors, startPoint: .topLeading,
                                             endPoint: .bottomTrailing))
                        .frame(height: 180)
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
        }
        .frame(width: 130)
    }

    // MARK: Private

    @MainActor
    private var gradientColors: [Color] {
        let colors = series.coverColorHexes.compactMap(Color.init(hex:))
        return colors.isEmpty ? [.purple, .blue] : colors
    }
}

private struct MoreButtonView: View {
    var body: some View {
        VStack(alignment: .center, spacing: 12) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
                .frame(width: 130, height: 180)
                .overlay {
                    VStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title)
                            .foregroundStyle(.secondary)
                        Text("더 보기")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
        }
        .frame(width: 130)
    }
}

private struct ContinueReadingItemView: View {
    // MARK: Internal

    let item: ContinueReadingItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomLeading) {
                // 배경 커버 이미지
                if let url = item.series.coverURL {
                    CoverImageView(url: url, height: 180, cornerRadius: 12, gradientColors: gradientColors)
                } else {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(LinearGradient(colors: gradientColors, startPoint: .topLeading,
                                             endPoint: .bottomTrailing))
                        .frame(height: 180)
                }

                // 진행률 오버레이
                VStack(alignment: .leading, spacing: 4) {
                    Spacer()

                    // 진행률 바
                    ProgressView(value: item.progressPercentage)
                        .progressViewStyle(LinearProgressViewStyle(tint: .white))
                        .scaleEffect(x: 1, y: 0.8, anchor: .center)

                    // 진행률 텍스트
                    Text(item.progressText)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.3), radius: 1, x: 0, y: 1)
                }
                .padding(12)
            }

            // 제목 정보
            VStack(alignment: .leading, spacing: 2) {
                Text(item.series.title)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .foregroundStyle(.primary)

                Text(item.lastReadChapter.title)
                    .font(.caption2)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 130)
    }

    // MARK: Private

    @MainActor
    private var gradientColors: [Color] {
        let colors = item.series.coverColorHexes.compactMap(Color.init(hex:))
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
