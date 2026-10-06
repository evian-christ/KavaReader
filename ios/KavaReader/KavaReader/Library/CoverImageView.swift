import SwiftUI

struct ReadingBookmarkBadge: View {
    var body: some View {
        ReadingBookmarkShape()
            .fill(.orange)
            .frame(width: 24, height: 36)
            .shadow(color: .black.opacity(0.45), radius: 2, y: 2)
            .padding(.trailing, 10)
            .accessibilityLabel("읽는 중")
    }
}

struct ReadCheckBadge: View {
    var body: some View {
        Image(systemName: "checkmark")
            .font(.caption.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background(AppTheme.accentFill, in: Circle())
            .shadow(color: .black.opacity(0.4), radius: 3, y: 2)
            .padding(8)
            .accessibilityLabel("읽음")
    }
}

private struct ReadingBookmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - 8))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

struct CoverImageView: View {
    // MARK: Internal

    enum Phase {
        case idle
        case loading
        case success(Image)
        case failure
    }

    let url: URL
    let height: CGFloat
    let cornerRadius: CGFloat
    let gradientColors: [Color]

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(LinearGradient(colors: gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing))

                switch phase {
                case .idle, .loading:
                    ProgressView().tint(.white)
                case let .success(img):
                    img
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: height)
                        .clipped()
                case .failure:
                    Image(systemName: "photo")
                        .font(.title)
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
            .frame(width: geometry.size.width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        .frame(height: height)
        .task(id: loadIdentity) { await load() }
    }

    // MARK: Private

    @AppStorage("server_base_url") private var serverBaseURL: String = ""
    @AppStorage(KavitaCredentials.revisionKey) private var credentialRevision = 0
    private var serverAPIKey: String {
        _ = credentialRevision
        return KavitaCredentials.read(server: serverBaseURL, field: "apiKey")
    }
    @AppStorage("cover_cache_enabled") private var cacheEnabled = true
    @AppStorage("cover_cache_revision") private var cacheRevision = 0

    @State private var phase: Phase = .idle

    private var loadIdentity: String {
        "\(url.absoluteString)|\(serverBaseURL)|\(serverAPIKey)|\(cacheEnabled)|\(cacheRevision)"
    }

    private func load() async {
        phase = .loading
        do {
            if url.isFileURL {
                let fileURL = url
                let data = try await Task.detached { try Data(contentsOf: fileURL) }.value
                guard !Task.isCancelled else { return }
                phase = UIImage(data: data).map { .success(Image(uiImage: $0)) } ?? .failure
                return
            }
            let request = makeRequest()
            // Hash the URL and stable account credential into the filename so covers
            // from different accounts do not share a cached response.
            let credential = serverAPIKey.isEmpty ? (request.value(forHTTPHeaderField: "Authorization") ?? "") : serverAPIKey
            let identity = "\(url.absoluteString)|\(credential)"
            let data = try await CoverImageCache.shared.imageData(for: request, identity: identity, enabled: cacheEnabled)
            guard !Task.isCancelled else { return }
            if let ui = UIImage(data: data) {
                phase = .success(Image(uiImage: ui))
            } else {
                phase = .failure
            }
        } catch {
            if !Task.isCancelled { phase = .failure }
        }
    }

    private func makeRequest() -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        request.setValue("Kayva/1.0 (KavaReader)", forHTTPHeaderField: "User-Agent")
        guard KavitaCredentials.contains(url, server: serverBaseURL) else { return request }
        // Set Referer/Origin/Host to avoid SPA routing via proxy
        if let base = URL(string: serverBaseURL) {
            request.setValue(base.absoluteString, forHTTPHeaderField: "Referer")
            request.setValue(base.absoluteString, forHTTPHeaderField: "Origin")
            request.setValue(base.host, forHTTPHeaderField: "Host")
        }
        // Auth: prefer Bearer JWT from Keychain, else ApiKey
        let token = KavitaCredentials.read(server: serverBaseURL, field: "token")
        if !token.isEmpty,
           token.split(separator: ".").count == 3
        {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else if !serverAPIKey.isEmpty {
            request.setValue(serverAPIKey, forHTTPHeaderField: "ApiKey")
            request.setValue(serverAPIKey, forHTTPHeaderField: "X-Api-Key")
            request.setValue("Bearer \(serverAPIKey)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

}
