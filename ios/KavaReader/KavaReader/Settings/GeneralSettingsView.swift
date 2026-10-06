import SwiftUI

struct GeneralSettingsView: View {
    @AppStorage(GeneralSettings.homeItemsPerRowKey) private var homeItemsPerRow = GeneralSettings.defaultItemsPerRow
    @AppStorage(GeneralSettings.libraryItemsPerRowKey) private var libraryItemsPerRow = GeneralSettings.defaultItemsPerRow
    @AppStorage(GeneralSettings.detailItemsPerRowKey) private var detailItemsPerRow = GeneralSettings.defaultItemsPerRow

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                SettingsCard(title: "한 줄당 작품 수",
                             footer: "홈의 추천 및 이어서 읽기, 라이브러리, 만화 상세의 권·챕터·스페셜 목록에 각각 적용됩니다.",
                             horizontalInset: 8) {
                    itemsPerRowPicker("홈", systemImage: "house", selection: $homeItemsPerRow)
                    SettingsCardDivider()
                    itemsPerRowPicker("라이브러리", systemImage: "rectangle.stack", selection: $libraryItemsPerRow)
                    SettingsCardDivider()
                    itemsPerRowPicker("만화 상세", systemImage: "book", selection: $detailItemsPerRow)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 20)
        }
        .background(AppTheme.background)
        .navigationTitle("일반 설정")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func itemsPerRowPicker(_ title: LocalizedStringKey, systemImage: String,
                                  selection: Binding<Int>) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
            Spacer()
            Picker(title, selection: selection) {
                ForEach(GeneralSettings.itemsPerRowRange, id: \.self) { count in
                    Text(verbatim: String(count)).tag(count)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
        .frame(height: 56)
        .padding(.horizontal, 16)
    }
}

#Preview {
    NavigationStack {
        GeneralSettingsView()
    }
}
