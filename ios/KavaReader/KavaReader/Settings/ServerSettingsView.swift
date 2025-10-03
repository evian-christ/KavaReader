import SwiftUI

struct ServerSettingsView: View {
    // MARK: Internal

    var body: some View {
        Form {
            Section("서버") {
                TextField("서버 URL", text: $serverBaseURL)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)

                if !isValidURL && !serverBaseURL.isEmpty {
                    Text("올바른 URL 형식을 입력해주세요")
                        .font(.caption)
                        .foregroundColor(.red)
                }

                Button("연결 테스트") {
                    Task { await testConnection() }
                }
                .disabled(serverBaseURL.isEmpty || !isValidURL || isTestingConnection)
            }

            Section("계정") {
                TextField("사용자명", text: $username)
                    .textInputAutocapitalization(.never)
                SecureField("비밀번호", text: $password)
                TextField("API Key (선택사항)", text: $apiKey)
                    .textInputAutocapitalization(.never)

                Button("로그인") {
                    Task { await performLogin() }
                }
                .disabled(!canLogin || isLoggingIn)
            }
        }
        .navigationTitle("서버 설정")
        .navigationBarTitleDisplayMode(.inline)
        .alert(connectionTestMessage, isPresented: $showConnectionAlert) {
            Button("확인", role: .cancel) {}
        }
        .alert(loginAlertMessage, isPresented: $showLoginAlert) {
            Button("확인", role: .cancel) {}
        }
    }

    // MARK: Private

    @AppStorage("server_base_url") private var serverBaseURL: String = ""
    @AppStorage("server_username") private var username: String = ""
    @AppStorage("server_password") private var password: String = ""
    @AppStorage("server_api_key") private var apiKey: String = ""

    @State private var isLoggingIn: Bool = false
    @State private var showLoginAlert: Bool = false
    @State private var loginAlertMessage: String = ""
    @State private var isTestingConnection: Bool = false
    @State private var showConnectionAlert: Bool = false
    @State private var connectionTestMessage: String = ""

    private var isValidURL: Bool {
        guard !serverBaseURL.isEmpty else { return true }
        return URL(string: serverBaseURL) != nil
    }

    private var canLogin: Bool {
        !serverBaseURL.isEmpty &&
            isValidURL &&
            ((!username.isEmpty && !password.isEmpty) || !apiKey.isEmpty)
    }

    private func testConnection() async {
        guard let base = URL(string: serverBaseURL) else {
            connectionTestMessage = "유효하지 않은 URL입니다"
            showConnectionAlert = true
            return
        }

        isTestingConnection = true
        defer { isTestingConnection = false }

        do {
            var request = URLRequest(url: base)
            request.httpMethod = "GET"
            request.timeoutInterval = 10
            request.setValue("Kavita/1.0 (KavaReader)", forHTTPHeaderField: "User-Agent")

            let (_, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                if (200 ... 299).contains(httpResponse.statusCode) {
                    connectionTestMessage = "서버에 성공적으로 연결되었습니다"
                } else {
                    connectionTestMessage = "서버 응답 오류 (상태 코드: \(httpResponse.statusCode))"
                }
            } else {
                connectionTestMessage = "알 수 없는 응답 형식입니다"
            }
        } catch {
            if let urlError = error as? URLError {
                switch urlError.code {
                case .notConnectedToInternet:
                    connectionTestMessage = "인터넷 연결을 확인해주세요"
                case .timedOut:
                    connectionTestMessage = "연결 시간이 초과되었습니다"
                case .cannotFindHost:
                    connectionTestMessage = "서버를 찾을 수 없습니다"
                case .cannotConnectToHost:
                    connectionTestMessage = "서버에 연결할 수 없습니다"
                default:
                    connectionTestMessage = "네트워크 오류: \(urlError.localizedDescription)"
                }
            } else {
                connectionTestMessage = "연결 실패: \(error.localizedDescription)"
            }
        }

        showConnectionAlert = true
    }

    private func performLogin() async {
        guard let base = URL(string: serverBaseURL) else {
            loginAlertMessage = "유효하지 않은 서버 URL입니다."
            showLoginAlert = true
            return
        }

        isLoggingIn = true
        defer { isLoggingIn = false }

        // Try multiple possible endpoints used by Kavita or proxies
        let endpoints = [
            "/api/auth/login", // JSON
            "/api/account/login", // sometimes used
            "/auth/login", // fallback
            "/login", // HTML form
        ]
        var lastError = ""

        for path in endpoints {
            guard var comps = URLComponents(url: base, resolvingAgainstBaseURL: false) else { continue }
            let basePath = comps.path
            comps.path = basePath + path
            guard let url = comps.url else { continue }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            // Use JSON for API-like endpoints; use form-encoded for classic /login
            if path == "/login" {
                request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
                request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
                                 forHTTPHeaderField: "Accept")
                // broad compatibility: include common aliases for username/email and password
                let pairs = [
                    ("username", urlEncode(username)),
                    ("user", urlEncode(username)),
                    ("email", urlEncode(username)),
                    ("password", urlEncode(password)),
                ]
                let bodyString = pairs.map { "\($0)=\($1)" }.joined(separator: "&")
                request.httpBody = bodyString.data(using: .utf8)
            } else {
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                let body = ["username": username, "password": password]
                do {
                    request.httpBody = try JSONEncoder().encode(body)
                } catch {
                    lastError = "Request encoding error: \(error.localizedDescription)"
                    continue
                }
            }

            // Set anti-caching headers and referer/origin to help some reverse proxies
            request.setValue(base.absoluteString, forHTTPHeaderField: "Referer")
            request.setValue(base.absoluteString, forHTTPHeaderField: "Origin")
            request.setValue("Kayva/1.0 (KavaReader)", forHTTPHeaderField: "User-Agent")

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse {
                    // detect token from common auth headers (e.g., Authorization: Bearer ... in response)
                    if let authHeader = (http.allHeaderFields["Authorization"] as? String) ??
                        (http.allHeaderFields["authorization"] as? String)
                    {
                        if authHeader.lowercased().hasPrefix("bearer ") {
                            let t = String(authHeader.dropFirst("Bearer ".count))
                            if !t.isEmpty { saveTokenAndNotify(t); return }
                        }
                    }

                    // detect Set-Cookie and persist into shared cookie storage for subsequent requests
                    if let headerFields = http.allHeaderFields as? [String: String] {
                        let lowerKeys = headerFields.keys.map { $0.lowercased() }
                        if lowerKeys.contains(where: { $0.contains("set-cookie") }) {
                            // Parse cookies and store
                            let cookies = HTTPCookie.cookies(withResponseHeaderFields: headerFields, for: url)
                            for c in cookies {
                                HTTPCookieStorage.shared.setCookie(c)
                                // Some deployments put api key or jwt-like token into cookie (e.g., auth_token,
                                // api_key)
                                let nameLower = c.name.lowercased()
                                if nameLower.contains("token") || nameLower
                                    .contains("jwt") || nameLower == "api_key" || nameLower == "apikey" || nameLower ==
                                    "x-api-key"
                                {
                                    saveTokenAndNotify(c.value)
                                    return
                                }
                            }
                            // If we received cookies but not a token value, verify auth immediately
                            if await verifyAuth(base: base) {
                                loginAlertMessage = "로그인 성공: 세션 쿠키 저장 및 인증 확인 완료."
                                showLoginAlert = true
                                return
                            } else {
                                lastError = "쿠키 수신했으나 인증 확인 실패"
                                continue
                            }
                        }
                    }

                    // if JSON returned, try to parse token-like fields
                    let contentTypeRaw = (http.allHeaderFields["Content-Type"] as? String) ??
                        (http.allHeaderFields["content-type"] as? String)
                    if let contentType = contentTypeRaw?.lowercased(), contentType.contains("application/json") {
                        if let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                            let tokenKeys = ["token", "access_token", "accessToken", "jwt", "api_key", "apiKey", "key"]
                            for key in tokenKeys {
                                if let v = json[key] as? String {
                                    saveTokenAndNotify(v)
                                    return
                                }
                            }
                            // If JSON but no token, present preview
                            if let s = String(data: data, encoding: .utf8) {
                                loginAlertMessage = "로그인 성공 (JSON 응답): \n\(s.prefix(1024))"
                                showLoginAlert = true
                                return
                            }
                        }
                    }

                    // If success but no token/cookie, continue to try next endpoint
                    if 200 ..< 300 ~= http.statusCode {
                        lastError = "\(path) responded 2xx but no token/cookie detected."
                        continue
                    } else {
                        lastError = "\(path) returned status \(http.statusCode)"
                        continue
                    }
                }
            } catch {
                lastError = "Network error: \(error.localizedDescription)"
                continue
            }
        }

        // As a final fallback, attempt CSRF-based form login flow
        if await performCSRFFormLogin(base: base) {
            if await verifyAuth(base: base) {
                loginAlertMessage = "로그인 성공: CSRF 폼 플로우를 통해 인증되었습니다."
                showLoginAlert = true
                return
            }
        }

        loginAlertMessage = "로그인 실패: \(lastError)"
        showLoginAlert = true
    }

    // Attempt GET /login -> extract CSRF token -> POST form with credentials and token
    private func performCSRFFormLogin(base: URL) async -> Bool {
        guard var comps = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return false }
        let basePath = comps.path
        comps.path = basePath + "/login"
        guard let loginURL = comps.url else { return false }

        do {
            var getReq = URLRequest(url: loginURL)
            getReq.httpMethod = "GET"
            getReq.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
                            forHTTPHeaderField: "Accept")
            getReq.setValue(base.absoluteString, forHTTPHeaderField: "Referer")
            let (htmlData, getResp) = try await URLSession.shared.data(for: getReq)
            if let http = getResp as? HTTPURLResponse {
                if let headerFields = http.allHeaderFields as? [String: String] {
                    let cookies = HTTPCookie.cookies(withResponseHeaderFields: headerFields, for: loginURL)
                    cookies.forEach { HTTPCookieStorage.shared.setCookie($0) }
                }
            }
            guard let html = String(data: htmlData, encoding: .utf8) else { return false }
            guard let (param, token) = extractCSRFToken(from: html) else {
                return false
            }

            var post = URLRequest(url: loginURL)
            post.httpMethod = "POST"
            post.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            post.setValue(base.absoluteString, forHTTPHeaderField: "Referer")
            // If there is a XSRF-TOKEN cookie, mirror to header (common in many frameworks)
            if let xsrf = readCookieValue(nameCandidates: ["XSRF-TOKEN", "xsrf-token", "_xsrf"]) {
                post.setValue(xsrf, forHTTPHeaderField: "X-XSRF-TOKEN")
            }

            let fields: [(String, String)] = [
                ("username", urlEncode(username)),
                ("user", urlEncode(username)),
                ("email", urlEncode(username)),
                ("password", urlEncode(password)),
                (param, urlEncode(token)),
            ]
            let bodyString = fields.map { "\($0)=\($1)" }.joined(separator: "&")
            post.httpBody = bodyString.data(using: .utf8)

            let (data, resp) = try await URLSession.shared.data(for: post)
            if let http = resp as? HTTPURLResponse {
                if let headerFields = http.allHeaderFields as? [String: String] {
                    let cookies = HTTPCookie.cookies(withResponseHeaderFields: headerFields, for: loginURL)
                    cookies.forEach { HTTPCookieStorage.shared.setCookie($0) }
                    // try to extract token-like cookie
                    if let tok = readCookieValue(nameCandidates: [
                        "auth_token",
                        "jwt",
                        "token",
                        "api_key",
                        "apikey",
                        "x-api-key",
                    ]) {
                        saveTokenAndNotify(tok)
                        return true
                    }
                }
                // If success without explicit token, consider cookies enough; verify
                if 200 ..< 400 ~= http.statusCode {
                    return true
                }
            }
            // also attempt JSON parse for token
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let tokenKeys = ["token", "access_token", "accessToken", "jwt", "api_key", "apiKey", "key"]
                for k in tokenKeys {
                    if let v = json[k] as? String { saveTokenAndNotify(v); return true }
                }
            }
        } catch {
            return false
        }
        return false
    }

    private func extractCSRFToken(from html: String) -> (param: String, value: String)? {
        // Try common hidden input names
        let candidates = [
            "__RequestVerificationToken",
            "__RequestAntiForgeryToken",
            "_csrf",
            "csrfmiddlewaretoken",
            "authenticity_token",
        ]
        for name in candidates {
            if let value = match(html: html, pattern: "name=\\\"\(name)\\\"[^>]*value=\\\"([^\\\"]+)\\\"") {
                return (name, value)
            }
        }
        // Try meta tag
        if let content = match(html: html,
                               pattern: "<meta[^>]*name=\\\"csrf-token\\\"[^>]*content=\\\"([^\\\"]+)\\\"")
        {
            return ("csrf-token", content)
        }
        return nil
    }

    private func match(html: String, pattern: String) -> String? {
        do {
            let re = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators])
            let range = NSRange(html.startIndex ..< html.endIndex, in: html)
            if let m = re.firstMatch(in: html, options: [], range: range), m.numberOfRanges > 1,
               let r = Range(m.range(at: 1), in: html)
            {
                return String(html[r])
            }
        } catch {}
        return nil
    }

    private func readCookieValue(nameCandidates: [String]) -> String? {
        let storage = HTTPCookieStorage.shared
        for cookie in storage.cookies ?? [] {
            if nameCandidates.contains(where: { $0.caseInsensitiveCompare(cookie.name) == .orderedSame }) {
                return cookie.value
            }
        }
        return nil
    }

    private func verifyAuth(base: URL) async -> Bool {
        guard var comps = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return false }
        comps.path = comps.path + "/api/library/libraries"
        guard let url = comps.url else { return false }
        var req = URLRequest(url: url)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) { return true }
        } catch {}
        return false
    }

    private func readStoredToken() -> String? {
        if let data = KeychainHelper.shared.read(key: "kavita_api_token"), let s = String(data: data, encoding: .utf8) {
            let norm = normalizeToken(s)
            if !norm.isEmpty { return norm }
        }
        return nil
    }

    private func saveTokenAndNotify(_ token: String) {
        let norm = normalizeToken(token)
        if let data = norm.data(using: .utf8) {
            _ = KeychainHelper.shared.save(key: "kavita_api_token", data: data)
        }
        loginAlertMessage = "로그인 성공: 토큰 수신. Keychain에 저장했습니다."
        showLoginAlert = true
    }

    // MARK: - Helpers

    private func urlEncode(_ s: String) -> String {
        return s.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? s
    }

    private func previewBody(data: Data, maxLength: Int) -> String {
        if data.isEmpty { return "" }
        if let s = String(data: data, encoding: .utf8) {
            if s.count <= maxLength { return s }
            return String(s.prefix(maxLength))
        }
        // binary data -> show size
        return "<binary data, \(data.count) bytes>"
    }

    private func normalizeToken(_ raw: String) -> String {
        var t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.lowercased().hasPrefix("bearer ") {
            t = String(t.dropFirst("bearer ".count))
        }
        // strip enclosing quotes if pasted JSON-like
        if t.hasPrefix("\"") && t.hasSuffix("\"") {
            t = String(t.dropFirst().dropLast())
        }
        return t
    }
}

#Preview {
    NavigationStack {
        ServerSettingsView()
    }
}
