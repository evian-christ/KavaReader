import SwiftUI

struct ReaderSettingsView: View {
    // MARK: Internal

    var body: some View {
        Form {
            Section {
                Picker("읽기 방향", selection: $readerSettings.scrollDirection) {
                    ForEach(ScrollDirection.allCases) { direction in
                        Text(direction.displayName).tag(direction)
                    }
                }

            } footer: {
                Text("선택한 스크롤 방향은 모든 만화에 기본으로 적용됩니다.")
            }

            Section {
                Button("기본값으로 재설정") {
                    readerSettings.resetToDefaults()
                }
                .foregroundStyle(.red)
            }
        }
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
