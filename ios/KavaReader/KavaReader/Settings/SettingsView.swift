import SwiftUI

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink(destination: ServerSettingsView()) {
                        Label("서버 설정", systemImage: "server.rack")
                    }

                    NavigationLink(destination: ReaderSettingsView()) {
                        Label("읽기 설정", systemImage: "book.pages")
                    }
                } header: {
                    Text("설정")
                }

                Section {
                    HStack {
                        Label("버전", systemImage: "info.circle")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("앱 정보")
                }
            }
            .navigationTitle("설정")
        }
    }
}

#Preview {
    SettingsView()
}
