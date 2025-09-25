import SwiftUI
import OSLog

struct CoverImageView: View {
    let url: URL
    let height: CGFloat
    let cornerRadius: CGFloat
    let gradientColors: [Color]

    @AppStorage("server_base_url") private var serverBaseURL: String = ""
    @AppStorage("server_api_key") private var serverAPIKey: String = ""

    @State private var phase: Phase = .idle

    enum Phase {
        case idle
        case loading
        case success(Image)
        case failure
    }

    var body: some View {
        ZStack {
            switch phase {
            case .idle, .loading:
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(LinearGradient(colors: gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(height: height)
                    .overlay(ProgressView().tint(.white))
            case let .success(img):
                img
                    .resizable()
                    .scaledToFill()
                    .frame(height: height)
                    .clipped()
                    .cornerRadius(cornerRadius)
            case .failure:
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(LinearGradient(colors: gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(height: height)
                    .overlay(Image(systemName: "photo").font(.title).foregroundStyle(.white.opacity(0.9)))
            }
        }
        .task { await load() }
    }

    private func load() async {
        // Use pattern matching to avoid ambiguity with SwiftUI's ScrollPhase.idle
        guard case .idle = phase else { return }
        phase = .loading
        do {
            let (data, response) = try await URLSession.shared.data(for: makeRequest())
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                phase = .failure; return
            }
            let contentType = http.value(forHTTPHeaderField: "Content-Type") ?? ""
            if contentType.lowercased().hasPrefix("image/") == false, isHTML(data) {
                // SPA HTML or non-image
                phase = .failure
                return
            }
            if let ui = UIImage(data: data) {
                phase = .success(Image(uiImage: ui))
            } else {
                phase = .failure
            }
        } catch {
            phase = .failure
        }
    }

    private func makeRequest() -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        request.setValue("Kayva/1.0 (KavaReader)", forHTTPHeaderField: "User-Agent")
        // Set Referer/Origin/Host to avoid SPA routing via proxy
        if let base = URL(string: serverBaseURL) {
            request.setValue(base.absoluteString, forHTTPHeaderField: "Referer")
            request.setValue(base.absoluteString, forHTTPHeaderField: "Origin")
            request.setValue(base.host, forHTTPHeaderField: "Host")
        }
        // Auth: prefer Bearer JWT from Keychain, else ApiKey
        if let tokenData = KeychainHelper.shared.read(key: "kavita_api_token"),
           let token = String(data: tokenData, encoding: .utf8), !token.isEmpty,
           token.split(separator: ".").count == 3 {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else if !serverAPIKey.isEmpty {
            request.setValue(serverAPIKey, forHTTPHeaderField: "ApiKey")
            request.setValue(serverAPIKey, forHTTPHeaderField: "X-Api-Key")
            request.setValue("Bearer \(serverAPIKey)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func isHTML(_ data: Data) -> Bool {
        guard let s = String(data: data, encoding: .utf8) else { return false }
        let lowered = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return lowered.hasPrefix("<!doctype") || lowered.hasPrefix("<html")
    }
}
