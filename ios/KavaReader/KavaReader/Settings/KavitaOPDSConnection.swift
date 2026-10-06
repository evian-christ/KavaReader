import Foundation

// Accept Kavita catalog URLs, including servers hosted under a reverse-proxy subpath.
struct KavitaOPDSConnection {
    let serverURL: URL
    let apiKey: String
    let upgradedToHTTPS: Bool

    init?(address: String) {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil
        else { return nil }

        let segments = components.percentEncodedPath.split(separator: "/", omittingEmptySubsequences: false)
        guard let index = segments.indices.first(where: {
            segments[$0].lowercased() == "api" &&
                $0 + 2 < segments.count && segments[$0 + 1].lowercased() == "opds"
        }),
            let key = String(segments[index + 2]).removingPercentEncoding,
            !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            !key.contains("/"), !key.contains("\\"),
            !key.contains(where: { $0.isWhitespace || $0.isNewline })
        else { return nil }

        components.percentEncodedPath = segments[..<index].joined(separator: "/")
        components.query = nil
        components.fragment = nil
        let shouldUpgrade = scheme == "http"
        components.scheme = "https"
        if shouldUpgrade && components.port == 80 { components.port = nil }
        if let port = components.port, !(1 ... 65535).contains(port) { return nil }
        guard let candidate = components.url,
              let url = KavitaCredentials.serverURL(candidate.absoluteString) else { return nil }
        serverURL = url
        apiKey = key
        upgradedToHTTPS = shouldUpgrade
    }

    /// Validate the candidate without touching existing credentials or the active server.
    @MainActor
    func verifyAndSave(using session: URLSession,
                       saveAPIKey: @MainActor (String, URL) -> Bool = {
                           KavitaCredentials.save($0, server: $1.absoluteString, field: "apiKey")
                       }) async throws
    {
        do {
            try await KavitaAPIKeyVerifier.verify(base: serverURL, apiKey: apiKey, session: session)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as KavitaAPIKeyVerifier.Failure {
            throw error
        } catch {
            // Do not expose an authentication URL containing the API key in the error message.
            throw Failure.httpsConnectionFailed
        }
        try Task.checkCancellation()
        guard saveAPIKey(apiKey, serverURL) else { throw Failure.credentialSaveFailed }
    }

    enum Failure: LocalizedError {
        case httpsConnectionFailed
        case credentialSaveFailed

        var errorDescription: String? {
            switch self {
            case .httpsConnectionFailed:
                AppLocalization.text("HTTPS 연결에 실패했습니다. 서버의 HTTPS 주소·포트와 인증서를 확인해주세요. 기존 설정은 유지됩니다.")
            case .credentialSaveFailed:
                AppLocalization.text("로그인 정보를 안전하게 저장하지 못했습니다. 서버 URL을 확인해주세요.")
            }
        }
    }
}
