import SwiftUI

enum SettingsDestination: Hashable {
    case general, theme, server, reader, cache, advanced, privacy, support
}

struct SettingsView: View {
    // MARK: Lifecycle

    init(navigationPath: Binding<NavigationPath>? = nil) {
        externalNavigationPath = navigationPath
    }

    // MARK: Internal

    var body: some View {
        NavigationStack(path: externalNavigationPath ?? $localNavigationPath) {
            ScrollView {
                VStack(spacing: 20) {
                    SettingsCard {
                        NavigationLink(value: SettingsDestination.general) {
                            HStack {
                                Label("일반 설정", systemImage: "gearshape")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(AppTheme.tertiaryText)
                            }
                            .frame(height: rowHeight)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 8)

                        NavigationLink(value: SettingsDestination.theme) {
                            HStack {
                                Label("테마 설정", systemImage: "paintpalette")
                                Spacer()
                                Text(AppLocalization.text(AppTheme.palette.name))
                                    .foregroundStyle(AppTheme.secondaryText)
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(AppTheme.tertiaryText)
                            }
                            .frame(minHeight: rowHeight)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 8)

                        NavigationLink(value: SettingsDestination.server) {
                            HStack {
                                Label("서버 설정", systemImage: "server.rack")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(AppTheme.tertiaryText)
                            }
                            .frame(height: rowHeight)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 8)

                        HStack {
                            Label("언어", systemImage: "globe")
                            Spacer()
                            Picker("언어", selection: $selectedLanguage) {
                                Text(verbatim: "한국어").tag(AppLanguage.korean.rawValue)
                                Text(verbatim: "English").tag(AppLanguage.english.rawValue)
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }
                        .frame(height: rowHeight)
                        .padding(.leading, 8)

                        NavigationLink(value: SettingsDestination.reader) {
                            HStack {
                                Label("읽기 설정", systemImage: "book.pages")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(AppTheme.tertiaryText)
                            }
                            .frame(height: rowHeight)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 8)

                        NavigationLink(value: SettingsDestination.cache) {
                            HStack {
                                Label("캐시 설정", systemImage: "externaldrive")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(AppTheme.tertiaryText)
                            }
                            .frame(height: rowHeight)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 8)

                        NavigationLink(value: SettingsDestination.advanced) {
                            HStack {
                                Label("고급 설정", systemImage: "slider.horizontal.3")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(AppTheme.tertiaryText)
                            }
                            .frame(height: rowHeight)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 8)
                    }

                    SettingsCard(title: "앱 정보", horizontalInset: 8) {
                        HStack {
                            Label("버전", systemImage: "info.circle")
                            Spacer()
                            Text(Bundle.main
                                .object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1")
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                        .frame(height: rowHeight)
                        .padding(.horizontal, 8)

                        NavigationLink(value: SettingsDestination.support) {
                            HStack {
                                Label("고객지원", systemImage: "envelope")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(AppTheme.tertiaryText)
                            }
                            .frame(minHeight: rowHeight)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 8)

                        NavigationLink(value: SettingsDestination.privacy) {
                            HStack {
                                Label("개인정보", systemImage: "hand.raised")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(AppTheme.tertiaryText)
                            }
                            .frame(minHeight: rowHeight)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 8)

                        Link(destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!) {
                            HStack {
                                Label("이용약관", systemImage: "doc.text")
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(AppTheme.tertiaryText)
                            }
                            .frame(minHeight: rowHeight)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 8)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 20)
            }
            .background(AppTheme.background)
            .navigationDestination(for: SettingsDestination.self) { destination in
                switch destination {
                case .general: GeneralSettingsView()
                case .theme: ThemeSettingsView()
                case .server: ServerSettingsView()
                case .reader: ReaderSettingsView()
                case .cache: CacheSettingsView()
                case .advanced: AdvancedSettingsView()
                case .privacy: PrivacyPolicyView()
                case .support: SupportView()
                }
            }
            .navigationTitle("설정")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: Private

    @State private var localNavigationPath = NavigationPath()
    @AppStorage(AppLanguage.storageKey) private var selectedLanguage = AppLanguage.korean.rawValue

    private let externalNavigationPath: Binding<NavigationPath>?
    private let rowHeight: CGFloat = 56
}

private struct CacheSettingsView: View {
    // MARK: Internal

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                SettingsCard(title: "커버 이미지", footer: "캐시를 끄면 다음부터 커버를 서버에서 다시 받습니다. 기존 이미지는 삭제하기 전까지 유지됩니다.") {
                    Toggle(isOn: $coverCacheEnabled) {
                        Label("커버 이미지 캐시", systemImage: "square.stack.3d.up")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                    SettingsCardDivider()

                    HStack {
                        Label("저장된 크기", systemImage: "internaldrive")
                        Spacer()
                        Text(ByteCountFormatter.string(fromByteCount: coverSize, countStyle: .file))
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                    SettingsCardDivider()

                    Button("커버 캐시 삭제") {
                        Task {
                            do {
                                try await CoverImageCache.shared.clear()
                            } catch {
                                presentClearError(error)
                            }
                            coverSize = await CoverImageCache.shared.sizeInBytes()
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppTheme.accent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
        }
        .background(AppTheme.background)
        .navigationTitle("캐시 설정")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            coverSize = await CoverImageCache.shared.sizeInBytes()
        }
        .alert("캐시 삭제 실패", isPresented: $showClearError) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(AppLocalization.text(clearErrorMessage))
        }
    }

    // MARK: Private

    @AppStorage("cover_cache_enabled") private var coverCacheEnabled = true
    @State private var coverSize: Int64 = 0
    @State private var clearErrorMessage = ""
    @State private var showClearError = false

    private func presentClearError(_ error: Error) {
        clearErrorMessage = error.localizedDescription
        showClearError = true
    }
}

#Preview {
    SettingsView()
        .environmentObject(LibraryViewModel(service: LibraryServiceFactory(baseURLString: nil, apiKey: nil)
                .makeService()))
}
