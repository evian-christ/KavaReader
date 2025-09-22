import SwiftUI

struct LibrarySeries: Identifiable, Hashable {
    // MARK: Lifecycle

    init(id: UUID = UUID(), title: String, author: String, coverGradients: [Color]) {
        self.id = id
        self.title = title
        self.author = author
        self.coverGradients = coverGradients
    }

    // MARK: Internal

    let id: UUID
    let title: String
    let author: String
    let coverGradients: [Color]
}

struct LibrarySection: Identifiable {
    // MARK: Lifecycle

    init(id: UUID = UUID(), title: String, items: [LibrarySeries]) {
        self.id = id
        self.title = title
        self.items = items
    }

    // MARK: Internal

    let id: UUID
    let title: String
    let items: [LibrarySeries]
}

struct ContentView: View {
    // MARK: Internal

    var body: some View {
        NavigationStack {
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
            .navigationTitle("라이브러리")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "작가, 제목, 태그 검색")
        }
        .navigationDestination(for: LibrarySeries.self) { series in
            Text("\(series.title) 상세 보기")
                .font(.title)
                .padding()
        }
    }

    // MARK: Private

    @State private var searchText: String = ""

    private let sections: [LibrarySection] = LibrarySection.mock

    private let grid = [GridItem(.adaptive(minimum: 140), spacing: 24)]

    private var filteredSections: [LibrarySection] {
        guard !searchText.isEmpty else { return sections }
        return sections.compactMap { section -> LibrarySection? in
            let matches = section.items.filter { item in
                item.title.localizedCaseInsensitiveContains(searchText) ||
                    item.author.localizedCaseInsensitiveContains(searchText)
            }
            return matches.isEmpty ? nil : LibrarySection(title: section.title, items: matches)
        }
    }
}

private struct LibraryCoverView: View {
    let series: LibrarySeries

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(LinearGradient(colors: series.coverGradients, startPoint: .topLeading,
                                         endPoint: .bottomTrailing))
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
}

private extension LibrarySection {
    static let mock: [LibrarySection] = [
        LibrarySection(title: "최근 추가",
                       items: [
                           LibrarySeries(title: "은하 해적단", author: "김하늘", coverGradients: [.pink, .purple]),
                           LibrarySeries(title: "도시의 빛", author: "이도윤", coverGradients: [.orange, .red]),
                           LibrarySeries(title: "서늘한 바람", author: "최유나", coverGradients: [.blue, .teal]),
                       ]),
        LibrarySection(title: "읽던 만화",
                       items: [
                           LibrarySeries(title: "밤의 노트", author: "박여울", coverGradients: [.mint, .blue]),
                           LibrarySeries(title: "코드 브레이커", author: "정태규", coverGradients: [.purple, .indigo]),
                           LibrarySeries(title: "숲 속 이야기", author: "한서윤", coverGradients: [.green, .teal]),
                       ]),
    ]
}

#Preview {
    ContentView()
}
