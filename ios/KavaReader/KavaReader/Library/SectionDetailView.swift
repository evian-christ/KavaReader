import SwiftUI

struct SectionDetailView: View {
    // MARK: Internal

    let sectionTitle: String
    @ObservedObject var viewModel: LibraryViewModel
    @AppStorage(AppLanguage.storageKey) private var selectedLanguage = AppLanguage.korean.rawValue

    var body: some View {
        Group {
            if series.isEmpty {
                SectionEmptyView(message: sectionTitle == "Favourite"
                    ? "작품에서 하트를 누르면 여기에 표시됩니다."
                    : "표시할 작품이 없습니다.")
            } else {
                sectionContent
            }
        }
        .navigationTitle(AppLocalization.text(sectionTitle,
                                             language: AppLanguage(rawValue: selectedLanguage) ?? .korean))
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Private

    private let grid = [GridItem(.adaptive(minimum: 140), spacing: 24)]

    private var series: [LibrarySeries] {
        viewModel.sections.first(where: { $0.title == sectionTitle })?.series ?? []
    }

    private var readingSeriesIds: Set<Int> {
        Set(viewModel.sections.first(where: { $0.title == "읽는 중" })?.items.compactMap(\.kavitaSeriesId) ?? [])
    }

    private var sectionContent: some View {
        ScrollView {
            LazyVGrid(columns: grid, spacing: 24) {
                ForEach(series) { series in
                    NavigationLink(value: series) {
                        LibraryCoverView(series: series,
                                         isReading: series.kavitaSeriesId.map(readingSeriesIds.contains) ?? false)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 32)
        }
        .background(AppTheme.background)
    }
}

private struct LibraryCoverView: View {
    // MARK: Internal

    let series: LibrarySeries
    let isReading: Bool

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomLeading) {
                if let url = series.coverURL {
                    CoverImageView(url: url, height: geometry.size.height, cornerRadius: 6,
                                   gradientColors: gradientColors)
                } else {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(LinearGradient(colors: gradientColors, startPoint: .topLeading,
                                             endPoint: .bottomTrailing))
                        .frame(height: geometry.size.height)
                }
                LinearGradient(colors: [.clear, .black.opacity(0.8)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: geometry.size.height * 0.55)
                VStack(alignment: .leading, spacing: 4) {
                    Text(series.title)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .shadow(color: .black.opacity(0.9), radius: 5, x: 0, y: 2)
                    Text(series.author)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                        .shadow(color: .black.opacity(0.8), radius: 4, x: 0, y: 2)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 10)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(alignment: .topTrailing) {
                if isReading && !series.isRead { ReadingBookmarkBadge() }
            }
            .overlay(alignment: .topTrailing) {
                if series.isRead { ReadCheckBadge() }
            }
        }
        .aspectRatio(2.0 / 3.0, contentMode: .fit)
    }

    // MARK: Private

    @MainActor
    private var gradientColors: [Color] {
        let colors = series.coverColorHexes.compactMap(Color.init(hex:))
        return colors.isEmpty ? AppTheme.coverGradient : colors
    }
}

private struct SectionEmptyView: View {
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.largeTitle)
                .foregroundStyle(AppTheme.secondaryText)
            Text(AppLocalization.text(message))
                .foregroundStyle(AppTheme.secondaryText)
        }
        .padding(32)
    }
}

#Preview {
    NavigationStack {
        SectionDetailView(sectionTitle: "Recently Added",
                          viewModel: LibraryViewModel(service: LibraryServiceFactory(baseURLString: nil,
                                                                                    apiKey: nil).makeService()))
    }
}
