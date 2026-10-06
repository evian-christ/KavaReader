import SwiftUI

enum KavitaConnectionType: String, CaseIterable, Identifiable {
    case direct
    case opds

    var id: String { rawValue }

    var title: String {
        switch self {
        case .direct: "Kavita"
        case .opds: "Kavita OPDS"
        }
    }

    var subtitle: String {
        switch self {
        case .direct: "서버 주소와 인증 정보로 연결"
        case .opds: "OPDS 주소 하나로 연결"
        }
    }

    var systemImage: String {
        self == .direct ? "server.rack" : "books.vertical"
    }
}

private enum KavitaAuthenticationMethod: String, CaseIterable, Identifiable {
    case apiKey
    case account

    var id: String { rawValue }
    var title: String { self == .apiKey ? "API 키" : "계정 로그인" }
}

/// Each setup screen owns its saved inputs. Runtime credentials remain server-scoped.
struct KavitaConnectionProfile: Codable {
    var serverURL: String
    var apiKey: String
    var username: String
    var password: String
    var opdsURL: String
    var authenticationMethod: String

    static func storageKey(for type: KavitaConnectionType) -> String {
        "kavita.connection.profile.\(type.rawValue)"
    }

    static func load(for type: KavitaConnectionType,
                     read: (String) -> Data? = { KeychainHelper.shared.read(key: $0) }) -> Self? {
        guard let data = read(storageKey(for: type)) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }

    func save(for type: KavitaConnectionType,
              write: (String, Data) -> Bool = { KeychainHelper.shared.save(key: $0, data: $1) }) -> Bool {
        guard let data = try? JSONEncoder().encode(self) else { return false }
        return write(Self.storageKey(for: type), data)
    }
}

struct KavitaServerSettingsView: View {
    var connectionType: KavitaConnectionType = .direct

    @AppStorage("server_base_url") private var activeServerURL = ""
    @AppStorage("kavita_active_connection_type") private var activeConnectionType = ""
    @State private var serverURL = ""
    @State private var apiKey = ""
    @State private var username = ""
    @State private var password = ""
    @State private var opdsURL = ""
    @State private var authenticationMethod = KavitaAuthenticationMethod.apiKey
    @State private var isConnecting = false
    @State private var didLoadProfile = false
    @State private var showAlert = false
    @State private var message = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                if connectionType == .opds {
                    opdsSettings
                } else {
                    directSettings
                }
                AppGlassActionButton(
                    title: AppLocalization.text(isConnecting ? "연결 중" : "연결"),
                    systemImage: "link",
                    size: CGSize(width: 180, height: 44),
                    isEnabled: canConnect && !isConnecting,
                    isHighlighted: false,
                    variant: .standard,
                    expandsToFitTitle: true,
                    accessibilityLabel: AppLocalization.text("연결")
                ) {
                    Task { await connect() }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
            .disabled(isConnecting)
        }
        .background(AppTheme.background)
        .navigationTitle(connectionType.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { loadProfile() }
        .alert(AppLocalization.text(message), isPresented: $showAlert) {
            Button("확인", role: .cancel) {}
        }
    }

    private var opdsSettings: some View {
        SettingsCard(title: "OPDS 주소", footer: "Kavita 사용자 설정 → 외부 클라이언트에서 복사") {
            SecureField("OPDS 주소", text: $opdsURL)
                .textFieldStyle(.plain)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .submitLabel(.go)
                .onSubmit { Task { await connect() } }
                .padding(16)
        }
    }

    private var directSettings: some View {
        VStack(spacing: 24) {
            SettingsCard(title: "서버 주소") {
                TextField("서버 URL", text: $serverURL)
                    .textFieldStyle(.plain)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .padding(16)
            }
            SettingsCard(title: "인증 방식") {
                Picker("인증 방식", selection: $authenticationMethod) {
                    ForEach(KavitaAuthenticationMethod.allCases) { method in
                        Text(AppLocalization.text(method.title)).tag(method)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.bottom, 12)

                if authenticationMethod == .apiKey {
                    SecureField("API 키", text: $apiKey)
                        .textFieldStyle(.plain)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.go)
                        .onSubmit { Task { await connect() } }
                        .padding(16)
                } else {
                    TextField("사용자명", text: $username)
                        .textFieldStyle(.plain)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(16)
                    SettingsCardDivider()
                    SecureField("비밀번호", text: $password)
                        .textFieldStyle(.plain)
                        .textContentType(.password)
                        .submitLabel(.go)
                        .onSubmit { Task { await connect() } }
                        .padding(16)
                }
            }
        }
    }

    private var canConnect: Bool {
        if connectionType == .opds {
            return !opdsURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard KavitaCredentials.serverURL(serverURL) != nil else { return false }
        return authenticationMethod == .apiKey
            ? !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            : !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty
    }

    private func loadProfile() {
        guard !didLoadProfile else { return }
        didLoadProfile = true
        // Legacy active credentials have no reliable setup provenance; keep the
        // working connection without copying them into either setup form.
        guard let profile = KavitaConnectionProfile.load(for: connectionType) else { return }
        serverURL = profile.serverURL
        apiKey = profile.apiKey
        username = profile.username
        password = profile.password
        opdsURL = profile.opdsURL
        authenticationMethod = KavitaAuthenticationMethod(rawValue: profile.authenticationMethod) ?? .apiKey
    }

    @MainActor
    private func connect() async {
        guard canConnect && !isConnecting else { return }
        isConnecting = true
        defer { isConnecting = false }
        do {
            let base: URL
            let key: String
            let token: String
            if connectionType == .opds {
                guard let connection = KavitaOPDSConnection(address: opdsURL) else {
                    throw ConnectionFailure.invalidOPDS
                }
                base = connection.serverURL
                key = connection.apiKey
                token = ""
                try await KavitaAPIKeyVerifier.verify(base: base, apiKey: key,
                                                      session: KavitaServerSession.session(for: base.absoluteString))
            } else {
                guard let url = KavitaCredentials.serverURL(serverURL) else {
                    throw KavitaAPIKeyVerifier.Failure.invalidURL
                }
                base = url
                if authenticationMethod == .apiKey {
                    key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
                    token = ""
                    try await KavitaAPIKeyVerifier.verify(base: base, apiKey: key,
                                                          session: KavitaServerSession.session(for: base.absoluteString))
                } else {
                    key = ""
                    token = try await login(base: base)
                }
            }
            try Task.checkCancellation()
            let profile = KavitaConnectionProfile(
                serverURL: base.absoluteString,
                apiKey: connectionType == .direct ? key : "",
                username: connectionType == .direct && authenticationMethod == .account ? username : "",
                password: connectionType == .direct && authenticationMethod == .account ? password : "",
                opdsURL: connectionType == .opds ? opdsURL.trimmingCharacters(in: .whitespacesAndNewlines) : "",
                authenticationMethod: authenticationMethod.rawValue
            )
            try activate(profile: profile, base: base, key: key, token: token)
            message = "서버에 연결되었습니다."
            showAlert = true
        } catch is CancellationError {
            return
        } catch {
            // Transport errors can include an OPDS URL or authentication query.
            message = (error as? LocalizedError)?.errorDescription ??
                AppLocalization.text("서버에 연결할 수 없습니다. 주소와 인증 정보를 확인해주세요.")
            if error is URLError {
                message = "서버에 연결할 수 없습니다. 주소와 인증 정보를 확인해주세요."
            }
            showAlert = true
        }
    }

    @MainActor
    private func activate(profile: KavitaConnectionProfile, base: URL, key: String, token: String) throws {
        let server = base.absoluteString
        guard let keyAccount = KavitaCredentials.key(server: server, field: "apiKey"),
              let tokenAccount = KavitaCredentials.key(server: server, field: "token") else {
            throw ConnectionFailure.saveFailed
        }
        let keychain = KeychainHelper.shared
        let oldKey = keychain.read(key: keyAccount)
        let oldToken = keychain.read(key: tokenAccount)
        // Publish one credential revision only after the complete setup is saved.
        guard keychain.save(key: keyAccount, data: Data(key.utf8)),
              keychain.save(key: tokenAccount, data: Data(token.utf8)),
              profile.save(for: connectionType) else {
            for (account, previous) in [(keyAccount, oldKey), (tokenAccount, oldToken)] {
                if let previous {
                    _ = keychain.save(key: account, data: previous)
                } else {
                    keychain.delete(key: account)
                }
            }
            throw ConnectionFailure.saveFailed
        }
        activeServerURL = server
        activeConnectionType = connectionType.rawValue
        let defaults = UserDefaults.standard
        defaults.set(defaults.integer(forKey: KavitaCredentials.revisionKey) + 1,
                     forKey: KavitaCredentials.revisionKey)
    }

    @MainActor
    private func login(base: URL) async throws -> String {
        let session = KavitaServerSession.session(for: base.absoluteString)
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            throw KavitaAPIKeyVerifier.Failure.invalidURL
        }
        let basePath = components.percentEncodedPath
        components.percentEncodedPath = basePath + "/api/Account/login"
        guard let loginURL = components.url else { throw KavitaAPIKeyVerifier.Failure.invalidURL }
        var request = URLRequest(url: loginURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(["username": username, "password": password])
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw KavitaAPIKeyVerifier.Failure.invalidResponse
        }
        guard 200 ..< 300 ~= http.statusCode else {
            throw ConnectionFailure.accountRejected
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["token"] as? String, !token.isEmpty else {
            throw KavitaAPIKeyVerifier.Failure.missingToken
        }
        components.percentEncodedPath = basePath + "/api/Library/libraries"
        guard let librariesURL = components.url else { throw KavitaAPIKeyVerifier.Failure.invalidURL }
        var verification = URLRequest(url: librariesURL)
        verification.timeoutInterval = 15
        verification.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        verification.setValue("application/json", forHTTPHeaderField: "Accept")
        let (libraries, verificationResponse) = try await session.data(for: verification)
        guard let verified = verificationResponse as? HTTPURLResponse,
              200 ..< 300 ~= verified.statusCode,
              (try? JSONSerialization.jsonObject(with: libraries) as? [[String: Any]]) != nil else {
            throw ConnectionFailure.accountRejected
        }
        return token
    }

    private enum ConnectionFailure: LocalizedError {
        case invalidOPDS
        case saveFailed
        case accountRejected

        var errorDescription: String? {
            switch self {
            case .invalidOPDS:
                AppLocalization.text("올바른 Kavita OPDS 주소를 입력해주세요. 주소에 /api/opds/와 인증 키가 포함되어야 합니다.")
            case .accountRejected:
                AppLocalization.text("계정 인증에 실패했습니다. 사용자명과 비밀번호를 확인해주세요.")
            case .saveFailed:
                AppLocalization.text("로그인 정보를 안전하게 저장하지 못했습니다. 서버 URL을 확인해주세요.")
            }
        }
    }
}

#Preview {
    NavigationStack {
        KavitaServerSettingsView()
    }
}
