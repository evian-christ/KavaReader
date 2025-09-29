import SwiftUI

struct ReaderSettingsView: View {
    @StateObject private var readerSettings = ReaderSettings.shared

    var body: some View {
        Form {
            Section {
                Picker("페이지 맞춤", selection: $readerSettings.pageFitMode) {
                    ForEach(PageFitMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }

                Picker("읽기 방향", selection: $readerSettings.scrollDirection) {
                    ForEach(ScrollDirection.allCases) { direction in
                        Text(direction.displayName).tag(direction)
                    }
                }

            } footer: {
                Text("선택한 설정은 모든 만화에 기본으로 적용됩니다.")
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
}

#Preview {
    NavigationStack {
        ReaderSettingsView()
    }
}