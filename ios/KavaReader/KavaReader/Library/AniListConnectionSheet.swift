import Combine
import SwiftUI
import UIKit

@MainActor
final class AniListConnectionSearchModel: ObservableObject {
    // MARK: Lifecycle

    init(service: AniListMetadataService = AniListMetadataService()) {
        self.service = service
    }

    // MARK: Internal

    @Published var query = ""
    @Published private(set) var candidates: [AniListSearchCandidate] = []
    @Published private(set) var isSearching = false
    @Published private(set) var searchedTitle: String?
    @Published private(set) var hasNextPage = false
    @Published private(set) var errorMessage: String?

    func search() {
        let title = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        fetch(title: title, page: 1)
    }

    func loadMore() {
        guard !isSearching, hasNextPage, let searchedTitle else { return }
        fetch(title: searchedTitle, page: page + 1)
    }

    func cancel() {
        task?.cancel()
        task = nil
        requestID = UUID()
        isSearching = false
    }

    // MARK: Private

    private let service: AniListMetadataService
    private var task: Task<Void, Never>?
    private var requestID = UUID()
    private var page = 0
    private var blockedUntil: Date?

    private func fetch(title: String, page requestedPage: Int) {
        if let blockedUntil, blockedUntil > Date() {
            errorMessage = AppLocalization.text("AniList 요청 제한에 도달했습니다. 잠시 후 다시 검색해 주세요.")
            return
        }
        cancel()
        let id = UUID()
        requestID = id
        errorMessage = nil
        isSearching = true
        if requestedPage == 1 {
            candidates = []
            hasNextPage = false
            searchedTitle = title
            page = 0
        }
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await service.search(title: title, page: requestedPage)
                guard !Task.isCancelled, requestID == id else { return }
                var seen = Set(candidates.map(\.id))
                candidates.append(contentsOf: result.candidates.filter { seen.insert($0.id).inserted })
                page = requestedPage
                hasNextPage = result.hasNextPage
            } catch let ExternalLookupError.rateLimited(retryAfter) {
                guard !Task.isCancelled, requestID == id else { return }
                blockedUntil = Date().addingTimeInterval(retryAfter)
                errorMessage = AppLocalization.text("AniList 요청 제한에 도달했습니다. 잠시 후 다시 검색해 주세요.")
            } catch {
                guard !Task.isCancelled, requestID == id else { return }
                errorMessage = AppLocalization.text("AniList 검색에 실패했습니다. 연결 상태를 확인하고 다시 시도해 주세요.")
            }
            guard requestID == id else { return }
            isSearching = false
        }
    }
}

struct AniListConnectionSheet: View {
    // MARK: Lifecycle

    init(series: LibrarySeries, identity: String, onConnected: @escaping () -> Void) {
        self.series = series
        self.identity = identity
        self.onConnected = onConnected
        _model = StateObject(wrappedValue: AniListConnectionSearchModel(service: AniListMetadataService(includeNovels: series.isLocal)))
    }

    // MARK: Internal

    let series: LibrarySeries
    let identity: String
    let onConnected: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(model.candidates) { candidate in
                        NavigationLink {
                            AniListConnectionConfirmation(series: series, identity: identity, candidate: candidate) {
                                onConnected()
                                dismiss()
                            }
                        } label: {
                            AniListCandidateSummary(candidate: candidate)
                        }
                    }
                    if let error = model.errorMessage {
                        Text(error).foregroundStyle(AppTheme.secondaryText)
                    } else if model.searchedTitle != nil && model.candidates.isEmpty && !model.isSearching {
                        Text(AppLocalization.text("검색 결과가 없습니다. 원제나 다른 제목으로 검색해 보세요."))
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                    if model.isSearching {
                        ProgressView(AppLocalization.text("AniList 검색 중"))
                    } else if model.hasNextPage {
                        Button(AppLocalization.text("결과 더 보기")) { model.loadMore() }
                    }
                } header: {
                    if let title = model.searchedTitle {
                        Text(AppLocalization.format("검색 결과: %@", title))
                    }
                }
                .listRowBackground(Color.clear)
            }
            .listStyle(.insetGrouped)
            .modifier(AniListTransparentPage())
            .overlay {
                if model.searchedTitle == nil && model.errorMessage == nil && !model.isSearching {
                    ContentUnavailableView {
                        Label(AppLocalization.text("연결할 작품을 검색하세요."), systemImage: "magnifyingglass")
                    }
                    .allowsHitTesting(false)
                }
            }
            .searchable(text: $model.query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: AppLocalization.text("AniList 검색어"))
            .autocorrectionDisabled()
            .onSubmit(of: .search) { model.search() }
            .navigationTitle(AppLocalization.text("AniList 작품 연결"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLocalization.text("닫기"), systemImage: "xmark") { dismiss() }
                        .labelStyle(.iconOnly)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(AppLocalization.text("검색"), systemImage: "magnifyingglass") { model.search() }
                        .disabled(model.isSearching || model.query.trimmingCharacters(in: .whitespacesAndNewlines)
                            .isEmpty)
                }
            }
            .onDisappear { model.cancel() }
        }
        .presentationBackground {
            Color.clear.glassEffect(.regular, in: .rect)
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: AniListConnectionSearchModel
}

private struct AniListCandidateSummary: View {
    // MARK: Internal

    let candidate: AniListSearchCandidate

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            AsyncImage(url: candidate.coverURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Rectangle().fill(.quaternary).overlay { Image(systemName: "book.closed") }
            }
            .frame(width: 62, height: 88)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(candidate.title).font(.headline).foregroundStyle(AppTheme.text)
                if let native = candidate.nativeTitle, native != candidate.title {
                    Text(native).font(.subheadline).foregroundStyle(AppTheme.secondaryText)
                }
                if !candidate.creators.isEmpty {
                    Text(candidate.creators.joined(separator: " · ")).font(.caption).foregroundStyle(AppTheme.secondaryText)
                }
                Text([candidate.year.map(String.init), formatName].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(AppTheme.secondaryText)
                Text("AniList · \(candidate.id)").font(.caption2).foregroundStyle(AppTheme.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Private

    private var formatName: String? {
        switch candidate.format {
        case "MANGA": AppLocalization.text("만화")
        case "ONE_SHOT": AppLocalization.text("단편")
        case "NOVEL": AppLocalization.text("소설")
        default: candidate.format
        }
    }
}

private struct AniListConnectionConfirmation: View {
    // MARK: Internal

    let series: LibrarySeries
    let identity: String
    let candidate: AniListSearchCandidate
    let onConnected: () -> Void

    var body: some View {
        List {
            Section {
                HStack(alignment: .top, spacing: 12) {
                    AniListCandidateSummary(candidate: candidate)
                    AppGlassActionButton(title: nil, systemImage: "arrow.up.right",
                                         size: CGSize(width: 44, height: 44), isEnabled: true,
                                         isHighlighted: false, variant: .standard,
                                         accessibilityLabel: AppLocalization.text("AniList에서 보기"))
                    {
                        openURL(candidate.metadata.sourceURL)
                    }
                    .frame(width: 44, height: 44)
                }
                .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                .alignmentGuide(.listRowSeparatorTrailing) { dimensions in dimensions.width }

                categories("장르", values: candidate.metadata.genres)
                categories("태그", values: candidate.metadata.tags)

                if candidate.metadata.genres.isEmpty && candidate.metadata.tags.isEmpty {
                    Text(AppLocalization.text("분류 정보가 없는 작품입니다. 연결은 저장할 수 있습니다."))
                        .foregroundStyle(AppTheme.secondaryText)
                }

                if let errorMessage {
                    Text(errorMessage).foregroundStyle(AppTheme.secondaryText)
                }
                if isSaving { ProgressView() }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        }
        .listStyle(.insetGrouped)
        .contentMargins(.top, 8, for: .scrollContent)
        .modifier(AniListTransparentPage())
        .navigationTitle(AppLocalization.text("연결 확인"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(AppLocalization.text("이 작품에 연결")) {
                    Task { await connect() }
                }
                .disabled(isSaving)
            }
        }
        .navigationBarBackButtonHidden(isSaving)
        .interactiveDismissDisabled(isSaving)
    }

    // MARK: Private

    @Environment(\.openURL) private var openURL
    @AppStorage(AppLanguage.storageKey) private var selectedLanguage = AppLanguage.korean.rawValue
    @State private var isSaving = false
    @State private var errorMessage: String?

    @ViewBuilder
    private func categories(_ label: String, values: [String]) -> some View {
        if !values.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(AppLocalization.text(label))
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
                Text(values.map {
                    MetadataLocalization.displayName($0, language: AppLanguage(rawValue: selectedLanguage) ?? .korean)
                }.joined(separator: " · "))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
            .alignmentGuide(.listRowSeparatorTrailing) { dimensions in dimensions.width }
        }
    }

    private func connect() async {
        guard !isSaving else { return }
        isSaving = true
        errorMessage = nil
        do {
            let record = ManualSeriesMetadataRecord(metadata: candidate.metadata, updatedAt: Date())
            if series.isLocal {
                try await LocalSeriesMetadataStore.shared.set(record, id: series.id)
            } else if let id = series.kavitaSeriesId {
                try await ManualSeriesMetadataStore.shared.set(record, identity: identity, seriesID: id)
                NotificationCenter.default.post(name: .seriesMetadataConnectionDidChange, object: identity)
            } else { throw LibraryServiceError.noData }
            onConnected()
        } catch {
            errorMessage = AppLocalization.text("연결을 저장하지 못했습니다. 다시 시도해 주세요.")
        }
        isSaving = false
    }
}

/// Pages stay transparent; the sheet owns the only glass surface during navigation.
private struct AniListTransparentPage: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(AniListTransparentNavigationBackground())
            .toolbarBackground(.hidden, for: .navigationBar)
    }
}

/// A pushed SwiftUI hosting controller can introduce an opaque system background
/// even after List's scroll background is hidden. Clear only this page's host.
private struct AniListTransparentNavigationBackground: UIViewControllerRepresentable {
    func makeUIViewController(context _: Context) -> Controller {
        Controller()
    }

    func updateUIViewController(_ controller: Controller, context _: Context) {
        controller.clearHostingBackground()
    }

    final class Controller: UIViewController {
        override func loadView() {
            view = UIView()
            view.backgroundColor = .clear
            view.isUserInteractionEnabled = false
        }

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            clearHostingBackground()
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            clearHostingBackground()
        }

        func clearHostingBackground() {
            parent?.view.backgroundColor = .clear
        }
    }
}
