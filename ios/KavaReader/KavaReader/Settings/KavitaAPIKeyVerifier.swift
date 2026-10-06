import Foundation

/// Both requests must succeed before a candidate connection can be saved.
enum KavitaAPIKeyVerifier {
    enum Failure: LocalizedError, Equatable {
        case invalidURL
        case invalidResponse
        case authenticationRejected
        case authenticationFailed(Int)
        case missingToken
        case verificationFailed(Int)

        var errorDescription: String? {
            switch self {
            case .invalidURL: AppLocalization.text("유효하지 않은 서버 URL입니다.")
            case .invalidResponse: AppLocalization.text("서버 응답 형식이 올바르지 않습니다.")
            case .authenticationRejected: AppLocalization.text("서버에는 연결됐지만 API 키 인증에 실패했습니다.")
            case let .authenticationFailed(status): AppLocalization.format("인증 요청 실패 (상태 코드: %d)", status)
            case .missingToken: AppLocalization.text("서버 응답에 인증 토큰이 없습니다.")
            case let .verificationFailed(status): AppLocalization.format("인증 토큰 검증 실패 (상태 코드: %d)", status)
            }
        }
    }

    static func verify(base: URL, apiKey: String, session: URLSession) async throws {
        try Task.checkCancellation()
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            throw Failure.invalidURL
        }
        // Preserve encoded reverse-proxy paths while appending API endpoints.
        let basePath = components.percentEncodedPath == "/" ? "" : components.percentEncodedPath
        components.percentEncodedPath = basePath + "/api/Plugin/authenticate"
        components.queryItems = [
            URLQueryItem(name: "apiKey", value: apiKey.trimmingCharacters(in: .whitespacesAndNewlines)),
            URLQueryItem(name: "pluginName", value: "KavaReader"),
        ]
        guard let authenticationURL = components.url else { throw Failure.invalidURL }
        var authRequest = URLRequest(url: authenticationURL)
        authRequest.httpMethod = "POST"
        authRequest.timeoutInterval = 10
        authRequest.setValue("application/json", forHTTPHeaderField: "Accept")

        let (authData, authResponse) = try await session.data(for: authRequest)
        try Task.checkCancellation()
        guard let authHTTP = authResponse as? HTTPURLResponse else { throw Failure.invalidResponse }
        guard 200 ..< 300 ~= authHTTP.statusCode else {
            if authHTTP.statusCode == 401 || authHTTP.statusCode == 403 { throw Failure.authenticationRejected }
            throw Failure.authenticationFailed(authHTTP.statusCode)
        }
        guard let json = try? JSONSerialization.jsonObject(with: authData) as? [String: Any],
              let token = json["token"] as? String,
              !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { throw Failure.missingToken }

        components.queryItems = nil
        components.percentEncodedPath = basePath + "/api/Library/libraries"
        guard let librariesURL = components.url else { throw Failure.invalidURL }
        var request = URLRequest(url: librariesURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw Failure.invalidResponse }
        guard 200 ..< 300 ~= http.statusCode else { throw Failure.verificationFailed(http.statusCode) }
        guard (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]) != nil else {
            throw Failure.invalidResponse
        }
    }
}
