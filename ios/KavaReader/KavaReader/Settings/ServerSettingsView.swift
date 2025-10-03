import SwiftUI

struct ServerSettingsView: View {
    var body: some View {
        Form {
            Section {
                NavigationLink {
                    KavitaServerSettingsView()
                } label: {
                    HStack {
                        Image(systemName: "server.rack")
                            .foregroundColor(.blue)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Kavita")
                                .font(.body)
                            Text("만화 및 소설 서버")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            } header: {
                Text("서버 유형")
            } footer: {
                Text("연결할 서버를 선택하세요")
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
}
