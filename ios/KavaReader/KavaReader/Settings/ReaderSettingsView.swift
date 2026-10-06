import SwiftUI

struct ReaderSettingsView: View {
    // MARK: Internal

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                SettingsCard(footer: "만화별 설정이 없는 작품에 적용됩니다.", horizontalInset: 8) {
                    HStack {
                        Label("읽기 방향", systemImage: "arrow.left.and.right")
                        Spacer()
                        Picker("읽기 방향", selection: $readerSettings.scrollDirection) {
                            ForEach(ScrollDirection.allCases) { option in
                                Text(option.displayName).tag(option)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                    .frame(height: 56)
                    .padding(.horizontal, 16)

                    if readerSettings.scrollDirection.isHorizontal {
                        SettingsCardDivider()

                        Toggle(isOn: $readerSettings.pageCurlEnabled) {
                            Label("페이지 넘김 효과", systemImage: "book.pages")
                        }
                        .frame(minHeight: 56)
                        .padding(.horizontal, 16)

                        SettingsCardDivider()

                        HStack {
                            Label("표시 방식", systemImage: "rectangle.on.rectangle")
                            Spacer()
                            Picker("표시 방식", selection: $readerSettings.horizontalDisplayMode) {
                                ForEach(HorizontalDisplayMode.allCases) { mode in
                                    Text(mode.displayName).tag(mode)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }
                        .frame(height: 56)
                        .padding(.horizontal, 16)

                        if readerSettings.horizontalDisplayMode == .doublePage {
                            SettingsCardDivider()

                            Toggle(isOn: $readerSettings.firstPageAlone) {
                                Label("첫 페이지 단독 표시", systemImage: "doc")
                            }
                            .frame(minHeight: 56)
                            .padding(.horizontal, 16)
                        }
                    }

                    SettingsCardDivider()

                    Toggle(isOn: $readerSettings.extendPageEdges) {
                        Label("페이지 색으로 여백 채우기", systemImage: "paintpalette")
                    }
                    .frame(minHeight: 56)
                    .padding(.horizontal, 16)

                    SettingsCardDivider()

                    Toggle(isOn: $readerSettings.tapEdgesToTurnPages) {
                        Label("가장자리 탭으로 페이지 넘기기", systemImage: "hand.tap")
                    }
                    .frame(minHeight: 56)
                    .padding(.horizontal, 16)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 20)
        }
        .background(AppTheme.background)
        .navigationTitle("읽기 설정")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Private

    @StateObject private var readerSettings = ReaderSettings.shared
}

#Preview {
    NavigationStack {
        ReaderSettingsView()
    }
}
