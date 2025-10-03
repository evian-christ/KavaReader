import Combine
import SwiftUI

struct SectionDetailView: View {
    // MARK: Internal

    let sectionTitle: String

    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView("만화 목록을 불러오는 중")
                    .progressViewStyle(.circular)
            } else if let error = viewModel.errorMessage {
                SectionErrorView(message: error) {
                    Task { await loadSection(force: true) }
                }
            } else if viewModel.series.isEmpty {
                SectionEmptyView()
            } else {
                sectionContent
            }
        }
        .navigationTitle(sectionTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadSection()
        }
        .refreshable {
            await loadSection(force: true)
        }
        .onChange(of: serverBaseURL) {
            Task { await loadSection(force: true) }
        }
    }

    // MARK: Private

    @AppStorage("server_base_url") private var serverBaseURL: String = ""
    @AppStorage("server_api_key") private var apiKey: String = ""

    @StateObject private var viewModel = SectionDetailViewModel()
    @State private var lastServiceKey: String = ""

    private let grid = [GridItem(.adaptive(minimum: 140), spacing: 24)]

    private var currentFactory: LibraryServiceFactory {
        LibraryServiceFactory(baseURLString: serverBaseURL, apiKey: apiKey.isEmpty ? nil : apiKey)
    }

    private var sectionContent: some View {
        ScrollView {
            LazyVGrid(columns: grid, spacing: 24) {
                ForEach(viewModel.series) { series in
                    NavigationLink(value: series) {
                        LibraryCoverView(series: series)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 32)
        }
        .background(Color(.systemBackground))
    }

    private func loadSection(force: Bool = false) async {
        updateService(force: force)
        await viewModel.loadSection(sectionTitle: sectionTitle, force: force)
    }

    private func updateService(force: Bool) {
        let key = "\(serverBaseURL)|\(apiKey)"
        if force || key != lastServiceKey {
            viewModel.updateService(currentFactory.makeService())
            lastServiceKey = key
        }
    }
}

private struct LibraryCoverView: View {
    // MARK: Internal

    let series: LibrarySeries

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .bottomLeading) {
                if let url = series.coverURL {
                    CoverImageView(url: url, height: 200, cornerRadius: 16, gradientColors: gradientColors)
                } else {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(LinearGradient(colors: gradientColors, startPoint: .topLeading,
                                             endPoint: .bottomTrailing))
                        .frame(height: 200)
                }
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

    @MainActor
    private var gradientColors: [Color] {
        let colors = series.coverColorHexes.compactMap(Color.init(hex:))
        return colors.isEmpty ? [.purple, .blue] : colors
    }
}

private struct SectionErrorView: View {
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

private struct SectionEmptyView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("표시할 만화가 없습니다.")
                .foregroundStyle(.secondary)
        }
        .padding(32)
    }
}

@MainActor
final class SectionDetailViewModel: ObservableObject {
    // MARK: Internal

    @Published var series: [LibrarySeries] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    func updateService(_ service: LibraryServicing) {
        self.service = service
    }

    func loadSection(sectionTitle: String, force: Bool = false) async {
        guard let service = service else {
            errorMessage = "서비스가 설정되지 않았습니다."
            return
        }

        if !force, !series.isEmpty {
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            let fetchedSeries = try await service.fetchFullSection(sectionTitle: sectionTitle)
            series = fetchedSeries
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: Private

    private var service: LibraryServicing?
}

#Preview {
    NavigationStack {
        SectionDetailView(sectionTitle: "Recently Added")
    }
}
