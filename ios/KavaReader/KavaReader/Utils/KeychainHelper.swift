import Foundation
import CryptoKit
import Security

final class KeychainHelper {
    static let shared = KeychainHelper()

    func save(key: String, data: Data) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        let item = query.merging(attributes) { _, new in new }
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    func read(key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

/// A server is its scheme, host, effective port and reverse-proxy base path.
/// Never use an unscoped credential as a fallback for a new server.
enum KavitaCredentials {
    static let revisionKey = "kavita_credentials_revision"

    static func serverURL(_ raw: String) -> URL? {
        guard var parts = URLComponents(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = parts.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil
        else { return nil }
        parts.scheme = scheme
        parts.host = host.lowercased()
        if parts.port == (scheme == "https" ? 443 : 80) { parts.port = nil }
        while parts.path.hasSuffix("/") { parts.path.removeLast() }
        return parts.url
    }

    static func key(server: String, field: String) -> String? {
        guard let url = serverURL(server) else { return nil }
        let hash = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        return "kavita.server.\(hash).\(field)"
    }

    static func read(server: String, field: String) -> String {
        guard let key = key(server: server, field: field),
              let data = KeychainHelper.shared.read(key: key) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    @discardableResult
    static func save(_ value: String, server: String, field: String) -> Bool {
        guard let key = key(server: server, field: field) else { return false }
        guard KeychainHelper.shared.save(key: key, data: Data(value.utf8)) else { return false }
        UserDefaults.standard.set(UserDefaults.standard.integer(forKey: revisionKey) + 1, forKey: revisionKey)
        return true
    }

    static func contains(_ url: URL, server: String) -> Bool {
        guard let base = serverURL(server),
              let target = URLComponents(url: url, resolvingAgainstBaseURL: false),
              target.user == nil, target.password == nil,
              base.scheme?.lowercased() == url.scheme?.lowercased(),
              base.host?.lowercased() == url.host?.lowercased(),
              (base.port ?? (base.scheme == "https" ? 443 : 80)) ==
                (url.port ?? (url.scheme == "https" ? 443 : 80)) else { return false }
        return base.path.isEmpty || url.path == base.path || url.path.hasPrefix(base.path + "/")
    }

    /// Old global values have no trustworthy server binding; require login again.
    static func removeLegacyCredentials() {
        for key in ["server_username", "server_password", "server_api_key"] {
            UserDefaults.standard.removeObject(forKey: key)
        }
        KeychainHelper.shared.delete(key: "kavita_api_token")
    }
}

/// Separate in-memory cookie jars, including servers under different proxy paths.
final class KavitaServerSession: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private static let lock = NSLock()
    private static var sessions: [String: KavitaServerSession] = [:]
    private let server: String
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()

    private init(server: String) { self.server = server }

    static func session(for server: String) -> URLSession {
        let identity = KavitaCredentials.serverURL(server)?.absoluteString ?? ""
        lock.lock()
        defer { lock.unlock() }
        if let existing = sessions[identity] { return existing.session }
        let owner = KavitaServerSession(server: identity)
        sessions[identity] = owner
        return owner.session
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        guard let url = request.url, KavitaCredentials.contains(url, server: server) else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}
