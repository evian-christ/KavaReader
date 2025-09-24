import SwiftUI

struct SettingsView: View {
    // MARK: Internal

    var body: some View {
        NavigationStack {
            Form {
                Section("서버") {
                    TextField("https://reader.local", text: $serverBaseURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    Text("Synology NAS에서 운영 중인 Kavita Adapter 주소를 입력하세요.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("인증") {
                    SecureField("API Key (선택)", text: $serverAPIKey)
                        .textInputAutocapitalization(.never)
                    Text("Adapter 설정 화면에서 발급한 API 키가 필요 없다면 빈칸으로 두세요.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("도움말") {
                    Text("라이브러리 화면은 Adapter 연결에 실패하면 자동으로 목 데이터를 사용합니다.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("설정")
        }
    }

    // MARK: Private

    @AppStorage("server_base_url") private var serverBaseURL: String = ""
    @AppStorage("server_api_key") private var serverAPIKey: String = ""
}

#Preview {
    SettingsView()
}
