import SwiftUI
import UIKit
import WebKit

struct EpubReaderView: View {
    let series: LibrarySeries
    let volumeID: UUID
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("epub_font_size") private var fontSize = 18.0
    @State private var volume: LocalComicVolume?
    @State private var location = EpubLocation(section: 0, fraction: 0)
    @State private var requestRevision = UUID()
    @State private var error: String?
    @State private var finished = false
    @State private var hasDisplayedContent = false

    var body: some View {
        Group {
            if let publication = volume?.epub {
                EpubWebView(volumeID: volumeID, publication: publication, location: location,
                            revision: requestRevision, fontSize: fontSize, onLocation: { record($0) }, onSave: { record($0, updateDisplay: false) },
                            onReady: { hasDisplayedContent = true },
                            onFailure: { error = $0 })
            } else if let error {
                Text(error).foregroundStyle(AppTheme.secondaryText).padding()
            } else {
                ProgressView("EPUB을 불러오는 중")
            }
        }
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle(volume?.title ?? series.title)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if let publication = volume?.epub {
                HStack(spacing: 16) {
                    readerButton("이전 본문", icon: "chevron.left", enabled: location.section > 0) {
                        select(location.section - 1)
                    }
                    Spacer()
                    Text(AppLocalization.format("본문 %d / %d", location.section + 1, publication.sections.count))
                        .font(.footnote).foregroundStyle(AppTheme.secondaryText)
                    Spacer()
                    readerButton("다음 본문", icon: "chevron.right", enabled: location.section + 1 < publication.sections.count) {
                        select(location.section + 1)
                    }
                }
                .padding(.horizontal, 20).padding(.vertical, 8)
                .background(AppTheme.background)
            }
        }
        .toolbar {
            if let publication = volume?.epub {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ForEach(Array(publication.sections.enumerated()), id: \.offset) { index, section in
                            Button(section.title) { select(index) }
                        }
                    } label: {
                        Image(systemName: "list.bullet").frame(width: 38, height: 38)
                    }
                    .buttonStyle(.plain).glassEffect(.regular.interactive(), in: .circle)
                    .accessibilityLabel("본문 목록")
                }
                .sharedBackgroundVisibility(.hidden)
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if !publication.fixedLayout {
                            Picker("글자 크기", selection: $fontSize) {
                                ForEach([14.0, 18.0, 22.0, 26.0], id: \.self) { size in
                                    Text("\(Int(size))").tag(size)
                                }
                            }
                        }
                        Button("완독으로 표시", systemImage: "checkmark") {
                            record(EpubLocation(section: publication.sections.count - 1, fraction: 1))
                            finished = true
                            dismiss()
                        }
                    } label: {
                        Image(systemName: "textformat.size").frame(width: 38, height: 38)
                    }
                    .buttonStyle(.plain).glassEffect(.regular.interactive(), in: .circle)
                    .accessibilityLabel("EPUB 읽기 설정")
                }
                .sharedBackgroundVisibility(.hidden)
            }
        }
        .safeAreaInset(edge: .top) {
            if volume != nil, let error { Text(error).font(.footnote).foregroundStyle(.orange).padding(8) }
        }
        .task(id: volumeID) {
            do {
                let loaded = try await LocalComicStore.shared.epubVolume(volumeID)
                guard !Task.isCancelled else { return }
                volume = loaded
                location = loaded.epubLocation ?? EpubLocation(section: 0, fraction: 0)
                requestRevision = UUID()
            } catch { self.error = error.localizedDescription }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active, volume != nil { record(location) }
        }
        .onDisappear { if volume != nil { record(location) } }
    }

    private func readerButton(_ title: String, icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        AppGlassActionButton(title: nil, systemImage: icon, size: CGSize(width: 44, height: 44),
                             isEnabled: enabled, isHighlighted: false, variant: .standard,
                             accessibilityLabel: AppLocalization.text(title), action: action)
    }

    private func select(_ section: Int) {
        guard let publication = volume?.epub, publication.sections.indices.contains(section) else { return }
        // Native controls request a new document; scroll updates do not trigger reloads.
        location = EpubLocation(section: section, fraction: 0)
        requestRevision = UUID()
    }

    private func record(_ location: EpubLocation, updateDisplay: Bool = true) {
        guard !finished, hasDisplayedContent, let volume, location.fraction.isFinite,
              volume.epub?.sections.indices.contains(location.section) == true else { return }
        if updateDisplay { self.location = location }
        let page = max(1, location.section * 1000 + Int(min(1, max(0, location.fraction)) * 1000))
        let chapter = SeriesChapter(id: volumeID, title: volume.title, number: 1,
                                    pageCount: volume.pageCount, lastReadPage: page, isEpub: true)
        let item = ContinueReadingItem(series: series, lastReadChapter: chapter,
                                       progress: ProgressDto(volumeId: 0, chapterId: 0, pageNum: page, seriesId: 0,
                                                             libraryId: 0, bookScrollId: nil, lastModifiedUtc: ""))
        NotificationCenter.default.post(name: .readerDidRead, object: nil,
                                        userInfo: ["item": item, "readAt": Date()])
        ReaderProgressSaveQueue.shared.enqueue(identity: "epub:\(volumeID)", seriesId: 0) {
            do { try await LocalComicStore.shared.saveEpubLocation(seriesID: series.id, volumeID: volumeID, location: location) }
            catch { self.error = error.localizedDescription }
        }
    }
}

private struct EpubWebView: UIViewRepresentable {
    let volumeID: UUID
    let publication: EpubPublication
    let location: EpubLocation
    let revision: UUID
    let fontSize: Double
    let onLocation: (EpubLocation) -> Void
    let onSave: (EpubLocation) -> Void
    let onReady: () -> Void
    let onFailure: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.setURLSchemeHandler(context.coordinator, forURLScheme: "kava-epub")
        let web = WKWebView(frame: .zero, configuration: configuration)
        web.isOpaque = false
        web.backgroundColor = UIColor(AppTheme.background)
        web.scrollView.backgroundColor = UIColor(AppTheme.background)
        web.navigationDelegate = context.coordinator
        web.scrollView.delegate = context.coordinator
        context.coordinator.web = web
        // Block remote subresources as well as remote navigation, including SVG/CSS requests.
        let rules = #"[{"trigger":{"url-filter":"^https?://"},"action":{"type":"block"}}]"#
        WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "KavaEpubOffline",
                                                               encodedContentRuleList: rules) { [weak web, weak coordinator = context.coordinator] list, error in
            guard let web, let coordinator else { return }
            if let list {
                web.configuration.userContentController.add(list)
                coordinator.ready = true
                if let request = coordinator.pendingRequest { web.load(request) }
            } else { coordinator.parent.onFailure(error?.localizedDescription ?? AppLocalization.text("EPUB 본문 구조를 읽을 수 없습니다.")) }
        }
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        web.backgroundColor = UIColor(AppTheme.background)
        web.scrollView.backgroundColor = UIColor(AppTheme.background)
        if coordinator.revision != revision {
            coordinator.flush(updateDisplay: false)
            coordinator.saveTask?.cancel()
            coordinator.restoreTask?.cancel()
            coordinator.revision = revision
            coordinator.restoring = true
            coordinator.section = min(max(0, location.section), publication.sections.count - 1)
            coordinator.restoreFraction = location.fraction
            coordinator.lastLocation = nil
            let request = URLRequest(url: coordinator.url(publication.sections[coordinator.section].path))
            coordinator.pendingRequest = request
            if coordinator.ready { web.load(request) }
        } else if coordinator.fontSize != fontSize || coordinator.palette != AppTheme.palette {
            coordinator.fontSize = fontSize
            coordinator.applyStyle()
        }
    }

    static func dismantleUIView(_ web: WKWebView, coordinator: Coordinator) {
        coordinator.flush(updateDisplay: false)
        coordinator.saveTask?.cancel()
        coordinator.restoreTask?.cancel()
        web.stopLoading()
        coordinator.resourceTasks.values.forEach { $0.cancel() }
        coordinator.resourceTasks.removeAll()
        web.navigationDelegate = nil
        web.scrollView.delegate = nil
    }

    final class Coordinator: NSObject, WKURLSchemeHandler, WKNavigationDelegate, UIScrollViewDelegate {
        var parent: EpubWebView
        weak var web: WKWebView?
        var revision: UUID?
        var ready = false
        var pendingRequest: URLRequest?
        var section = 0
        var restoreFraction = 0.0
        var restoring = true
        var fontSize = 18.0
        var palette = AppTheme.palette
        var lastLocation: EpubLocation?
        var saveTask: Task<Void, Never>?
        var restoreTask: Task<Void, Never>?
        var resourceTasks: [ObjectIdentifier: Task<Void, Never>] = [:]

        init(parent: EpubWebView) { self.parent = parent }

        func url(_ path: String) -> URL {
            // Appending a path component percent-encodes spaces and non-ASCII filenames.
            URL(string: "kava-epub://book/")!.appendingPathComponent(path)
        }

        func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
            let id = ObjectIdentifier(urlSchemeTask)
            guard let url = urlSchemeTask.request.url, url.scheme == "kava-epub", url.host == "book" else {
                urlSchemeTask.didFailWithError(EpubPublication.Failure.unsafePath)
                return
            }
            let path = String(url.path.dropFirst())
            let volumeID = parent.volumeID
            resourceTasks[id] = Task { [weak self] in
                do {
                    let resource = try await LocalComicStore.shared.epubResource(volumeID: volumeID, path: path)
                    guard let self, !Task.isCancelled, resourceTasks[id] != nil else { return }
                    var data = resource.data
                    var mime = resource.mime
                    if ["application/xhtml+xml", "text/html"].contains(mime) {
                        guard var html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) else {
                            throw EpubPublication.Failure.invalid
                        }
                        // Restrict book resources to this publication. EPUB content scripts stay disabled.
                        let viewport = parent.publication.fixedLayout ? "" : "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">"
                        let policy = viewport + "<meta http-equiv=\"Content-Security-Policy\" content=\"default-src kava-epub: data:; script-src 'none'; style-src kava-epub: 'unsafe-inline'; img-src kava-epub: data:; font-src kava-epub: data:; connect-src 'none'; object-src 'none'; frame-src 'none'; base-uri 'none'\">"
                        if let head = html.range(of: "<head[^>]*>", options: [.regularExpression, .caseInsensitive]) {
                            html.insert(contentsOf: policy, at: head.upperBound)
                        } else { html = policy + html }
                        data = Data(html.utf8)
                        mime = "text/html"
                    }
                    urlSchemeTask.didReceive(URLResponse(url: url, mimeType: mime, expectedContentLength: data.count,
                                                         textEncodingName: mime == "text/html" ? "utf-8" : nil))
                    urlSchemeTask.didReceive(data)
                    urlSchemeTask.didFinish()
                    resourceTasks.removeValue(forKey: id)
                } catch {
                    guard let self, !Task.isCancelled, resourceTasks[id] != nil else { return }
                    urlSchemeTask.didFailWithError(error)
                    resourceTasks.removeValue(forKey: id)
                }
            }
        }

        func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
            resourceTasks.removeValue(forKey: ObjectIdentifier(urlSchemeTask))?.cancel()
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url, url.scheme == "kava-epub", url.host == "book" else {
                decisionHandler(.cancel)
                return
            }
            if navigationAction.targetFrame?.isMainFrame != false {
                let path = String(url.path.dropFirst())
                guard let index = parent.publication.sections.firstIndex(where: { $0.path == path }) else {
                    decisionHandler(.cancel)
                    return
                }
                if index != section {
                    flush()
                    section = index
                    restoreFraction = url.fragment == nil ? 0 : -1
                    restoring = true
                    lastLocation = nil
                }
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            fontSize = parent.fontSize
            applyStyle()
            restoreTask?.cancel()
            restoreTask = Task { [weak self] in
                // Allow CSS, images and layout to settle, then restore by a viewport-independent ratio.
                do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
                guard let self, let web = self.web else { return }
                let scroll = web.scrollView
                let distance = max(0, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.top + scroll.adjustedContentInset.bottom)
                if restoreFraction >= 0 {
                    scroll.setContentOffset(CGPoint(x: 0, y: -scroll.adjustedContentInset.top + distance * CGFloat(min(1, max(0, restoreFraction)))), animated: false)
                }
                restoring = false
                parent.onReady()
                capture(scroll)
                flush()
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            parent.onFailure(error.localizedDescription)
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            parent.onFailure(error.localizedDescription)
        }

        func applyStyle() {
            palette = AppTheme.palette
            let scheme = palette.colorScheme == .light ? "light" : "dark"
            let colors = palette.hexColors.map { String(format: "#%06X", $0) }
            guard !parent.publication.fixedLayout else { return }
            let size = min(32, max(12, parent.fontSize))
            let script = """
            (() => {
              let style = document.getElementById('kava-reading-style');
              if (!style) { style = document.createElement('style'); style.id = 'kava-reading-style'; (document.head || document.documentElement).appendChild(style); }
              style.textContent = 'html { color-scheme: \(scheme); } body { background:\(colors[0])!important; color:\(colors[3])!important; padding:20px!important; margin:0 auto!important; max-width:850px; font-size:\(size)px!important; line-height:1.65!important; overflow-wrap:break-word; } img,svg { max-width:100%; height:auto; } a { color:\(colors[1])!important; }';
            })();
            """
            web?.evaluateJavaScript(script, in: nil, in: .defaultClient, completionHandler: nil)
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard !restoring else { return }
            capture(scrollView)
            saveTask?.cancel()
            saveTask = Task { [weak self] in
                do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
                self?.flush()
            }
        }

        func capture(_ scroll: UIScrollView) {
            let distance = max(0, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.top + scroll.adjustedContentInset.bottom)
            let fraction = distance > 0 ? min(1, max(0, (scroll.contentOffset.y + scroll.adjustedContentInset.top) / distance)) : 0
            lastLocation = EpubLocation(section: section, fraction: Double(fraction))
        }

        func flush(updateDisplay: Bool = true) {
            guard let location = lastLocation else { return }
            lastLocation = nil
            if updateDisplay { parent.onLocation(location) } else { parent.onSave(location) }
        }
    }
}
