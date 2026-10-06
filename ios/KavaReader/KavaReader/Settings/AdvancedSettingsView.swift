import SwiftUI

struct AdvancedSettingsView: View {
    // MARK: Internal

    var body: some View {
        ScrollView {
            SettingsCard(title: "인덱싱") {
                Toggle(isOn: $alternateTitleSearch) {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("다른 언어 제목으로 재검색")
                            Text("작품 이름이 원어가 아닐 경우 인덱싱에 도움이 될 수 있습니다.")
                                .font(.footnote)
                                .foregroundStyle(AppTheme.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } icon: {
                        Image(systemName: "character.book.closed")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
        }
        .background(AppTheme.background)
        .navigationTitle("고급 설정")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Private

    @AppStorage(IndexingSettings.alternateTitleSearchKey) private var alternateTitleSearch = false
}
