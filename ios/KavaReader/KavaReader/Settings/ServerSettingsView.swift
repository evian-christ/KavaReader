import SwiftUI

struct ServerSettingsView: View {
    @EnvironmentObject private var viewModel: LibraryViewModel
    @AppStorage("kavita_active_connection_type") private var activeConnectionType = ""
    @AppStorage("server_base_url") private var activeServerURL = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                SettingsCard(title: "연결 방식") {
                    ForEach(KavitaConnectionType.allCases) { type in
                        if type == .opds {
                            SettingsCardDivider()
                        }
                        NavigationLink {
                            KavitaServerSettingsView(connectionType: type)
                        } label: {
                            HStack {
                                Image(systemName: type.systemImage)
                                    .foregroundColor(AppTheme.accent)
                                    .frame(width: 28)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(AppLocalization.text(type.title))
                                        .font(.body)
                                    Text(AppLocalization.text(type.subtitle))
                                        .font(.caption)
                                        .foregroundColor(AppTheme.secondaryText)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)

                                if activeConnectionType == type.rawValue && !activeServerURL.isEmpty {
                                    Text("사용 중")
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(AppTheme.accent)
                                }

                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(AppTheme.tertiaryText)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                }

                VStack(alignment: .center, spacing: 10) {
                    AppGlassActionButton(title: AppLocalization.text("라이브러리 업데이트"),
                                         systemImage: "arrow.down.to.line",
                                         size: CGSize(width: 180, height: 44),
                                         isEnabled: !viewModel.isRefreshing,
                                         isHighlighted: false,
                                         variant: .standard,
                                         expandsToFitTitle: true,
                                         accessibilityLabel: AppLocalization.text("라이브러리 업데이트")) {
                        Task { await viewModel.refresh(updateLibraryPlus: true) }
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(height: 44)

                    HStack(spacing: 4) {
                        Text("최근 업데이트:")
                        if let lastUpdatedAt = viewModel.lastUpdatedAt {
                            Text(lastUpdatedAt, format: .dateTime.year().month().day().hour().minute())
                        } else {
                            Text("기록 없음")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)

                    if let errorMessage = viewModel.errorMessage {
                        Text(AppLocalization.text(errorMessage))
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
        }
        .background(AppTheme.background)
        .toolbar {
            ToolbarItem(placement: .principal) {
                AppLoadingStatus(message: viewModel.isRefreshing ? AppLocalization.text("라이브러리 업데이트 중") : nil,
                                 title: "서버 설정")
            }
        }
        .navigationTitle("서버 설정")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        ServerSettingsView()
    }
    .environmentObject(LibraryViewModel(service: LibraryServiceFactory(baseURLString: nil, apiKey: nil)
            .makeService()))
}
