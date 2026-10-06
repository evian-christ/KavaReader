import Foundation
@testable import KavaReader
import Testing

@MainActor
struct KavitaOPDSConnectionTests {
    @Test func upgradesHTTPAndPreservesProxyPathAndDecodedKey() throws {
        let connection = try #require(KavitaOPDSConnection(
            address: "  HTTP://Example.com:80/comic%20library/api/opds/new%2Bkey/catalog?ignored=yes#fragment  "
        ))
        #expect(connection.serverURL.absoluteString == "https://example.com/comic%20library")
        #expect(connection.apiKey == "new+key")
        #expect(connection.upgradedToHTTPS)
    }

    @Test func keepsExplicitPortsAndExistingHTTPS() throws {
        let custom = try #require(KavitaOPDSConnection(address: "http://example.com:5000/api/opds/key"))
        #expect(custom.serverURL.absoluteString == "https://example.com:5000")
        let secure = try #require(KavitaOPDSConnection(address: "https://example.com:8443/kavita/api/opds/key"))
        #expect(secure.serverURL.absoluteString == "https://example.com:8443/kavita")
        #expect(!secure.upgradedToHTTPS)
    }

    @Test func rejectsInvalidAddresses() {
        for address in ["ftp://example.com/api/opds/key", "http://example.com/api/opds/",
                        "http://user:password@example.com/api/opds/key", "http://example.com/api/opds/a%2Fb",
                        "http://example.com:70000/api/opds/key"] {
            #expect(KavitaOPDSConnection(address: address) == nil)
        }
    }

    @Test func savesOnlyAfterAuthenticationAndLibraryAccessSucceed() async throws {
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let connection = try #require(KavitaOPDSConnection(address: "http://success.example/kavita/api/opds/new-key"))
        var savedKey = "old-key"
        var savedServer = "https://old.example"
        var saves = 0
        try await connection.verifyAndSave(using: session) { key, server in
            savedKey = key
            savedServer = server.absoluteString
            saves += 1
            return true
        }
        #expect(saves == 1)
        #expect(savedKey == "new-key")
        #expect(savedServer == "https://success.example/kavita")
    }

    @Test func failedVerificationNeverChangesSavedCredentials() async throws {
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        for scenario in ["tls", "unauthorized", "missing-token", "library-denied", "html"] {
            let connection = try #require(KavitaOPDSConnection(
                address: "http://\(scenario).example/kavita/api/opds/new-key"
            ))
            var saves = 0
            do {
                try await connection.verifyAndSave(using: session) { _, _ in
                    saves += 1
                    return true
                }
                Issue.record("Failed HTTPS or API verification must not succeed: \(scenario)")
            } catch {
                #expect(!error.localizedDescription.contains("new-key"))
                switch scenario {
                case "tls":
                    #expect(error is KavitaOPDSConnection.Failure)
                case "unauthorized":
                    #expect(error as? KavitaAPIKeyVerifier.Failure == .authenticationRejected)
                case "missing-token":
                    #expect(error as? KavitaAPIKeyVerifier.Failure == .missingToken)
                case "library-denied":
                    #expect(error as? KavitaAPIKeyVerifier.Failure == .verificationFailed(403))
                default:
                    #expect(error as? KavitaAPIKeyVerifier.Failure == .invalidResponse)
                }
            }
            #expect(saves == 0)
        }
    }

    @Test func credentialStorageFailureIsNotReportedAsSuccess() async throws {
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let connection = try #require(KavitaOPDSConnection(address: "http://success.example/kavita/api/opds/new-key"))
        do {
            try await connection.verifyAndSave(using: session) { _, _ in false }
            Issue.record("A failed credential write must not succeed")
        } catch {
            guard case KavitaOPDSConnection.Failure.credentialSaveFailed = error else {
                Issue.record("Expected a credential storage failure")
                return
            }
        }
    }

    @Test func cancellationBeforeSavingKeepsExistingCredentials() async throws {
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let connection = try #require(KavitaOPDSConnection(address: "http://success.example/kavita/api/opds/new-key"))
        var saves = 0
        let task = Task { @MainActor in
            try await connection.verifyAndSave(using: session) { _, _ in
                saves += 1
                return true
            }
        }
        task.cancel()
        do {
            try await task.value
            Issue.record("A cancelled connection must not succeed")
        } catch {
            #expect(error is CancellationError)
        }
        #expect(saves == 0)
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OPDSConnectionFixtureProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private final class OPDSConnectionFixtureProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, url.scheme == "https" else {
            Issue.record("OPDS connections must never fall back to HTTP")
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        let scenario = url.host?.components(separatedBy: ".").first ?? ""
        if scenario == "tls" {
            client?.urlProtocol(self, didFailWithError: URLError(.secureConnectionFailed))
            return
        }
        let status: Int
        let body: String
        if url.path == "/kavita/api/Plugin/authenticate" {
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
            #expect(request.httpMethod == "POST")
            #expect(query?.first { $0.name == "apiKey" }?.value == "new-key")
            status = scenario == "unauthorized" ? 401 : 200
            body = scenario == "missing-token" ? "{}" : #"{"token":"test-token"}"#
        } else if url.path == "/kavita/api/Library/libraries" {
            #expect(request.httpMethod == "GET")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
            #expect(url.query == nil)
            status = scenario == "library-denied" ? 403 : 200
            body = scenario == "html" ? "<html>Proxy login</html>" : "[]"
        } else {
            Issue.record("Unexpected API path")
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil,
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() { }
}


@MainActor
struct KavitaConnectionProfileTests {
    @Test func sameServerKeepsDirectAndOPDSInputsSeparate() throws {
        var storage: [String: Data] = [:]
        let direct = profile(key: "direct-key", opds: "")
        let opds = profile(key: "", opds: "https://example.com/api/opds/opds-key")
        #expect(direct.save(for: .direct) { storage[$0] = $1; return true })
        #expect(opds.save(for: .opds) { storage[$0] = $1; return true })
        let restoredDirect = try #require(KavitaConnectionProfile.load(for: .direct) { storage[$0] })
        let restoredOPDS = try #require(KavitaConnectionProfile.load(for: .opds) { storage[$0] })
        #expect(restoredDirect.apiKey == "direct-key")
        #expect(restoredDirect.opdsURL.isEmpty)
        #expect(restoredOPDS.apiKey.isEmpty)
        #expect(restoredOPDS.opdsURL == opds.opdsURL)

        #expect(profile(key: "replacement", opds: "").save(for: .direct) {
            storage[$0] = $1; return true
        })
        #expect(KavitaConnectionProfile.load(for: .opds, read: { storage[$0] })?.opdsURL == opds.opdsURL)
    }

    @Test func OPDSOnlySetupDoesNotPopulateDirectProfile() {
        var storage: [String: Data] = [:]
        #expect(profile(key: "", opds: "https://example.com/api/opds/key").save(for: .opds) {
            storage[$0] = $1; return true
        })
        #expect(KavitaConnectionProfile.load(for: .direct) { storage[$0] } == nil)
    }

    @Test func missingOrInvalidProfileDoesNotReuseRuntimeCredentials() {
        #expect(KavitaConnectionProfile.load(for: .direct) { _ in nil } == nil)
        #expect(KavitaConnectionProfile.load(for: .opds) { _ in Data("invalid".utf8) } == nil)
        #expect(!profile(key: "key", opds: "").save(for: .direct) { _, _ in false })
    }

    private func profile(key: String, opds: String) -> KavitaConnectionProfile {
        KavitaConnectionProfile(serverURL: "https://example.com", apiKey: key,
                                username: "", password: "", opdsURL: opds,
                                authenticationMethod: "apiKey")
    }
}
