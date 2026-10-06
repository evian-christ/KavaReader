//
//  KavaReaderApp.swift
//  KavaReader
//
//  Created by Chan on 22/09/2025.
//

import SwiftUI
import UIKit

@main
struct KavaReaderApp: App {
    init() {
        KavitaCredentials.removeLegacyCredentials()
        AppNavigationTheme.apply()

    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
        }
    }
}

private struct AppRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @AppStorage(AppLanguage.storageKey) private var selectedLanguage = AppLanguage.korean.rawValue
    @AppStorage("server_base_url") private var serverBaseURL = ""
    @AppStorage(KavitaCredentials.revisionKey) private var credentialRevision = 0
    private var apiKey: String {
        _ = credentialRevision
        return KavitaCredentials.read(server: serverBaseURL, field: "apiKey")
    }
    @StateObject private var libraryPlusViewModel = LibraryPlusViewModel()
    @State private var localReloadTask: Task<Void, Never>?
    @AppStorage("library.collection") private var libraryCollection = "Favourite"
    @State private var libraryNavigationPath = NavigationPath()
    @State private var settingsNavigationPath = NavigationPath()
    @State private var settingsNavigationID = UUID()
    @State private var selectedTab: AppTab = .home
    @State private var didEnterBackground = false
    @StateObject private var libraryViewModel =
        LibraryViewModel(service: LibraryServiceFactory(baseURLString: nil, apiKey: nil).makeService())

    var body: some View {
        TabView(selection: $selectedTab) {
            LibraryPlusView(isActive: selectedTab == .home,
                            openFiles: {
                                libraryCollection = "Files"
                                libraryNavigationPath = NavigationPath()
                                selectedTab = .library
                            },
                            openServerSettings: {
                                var path = NavigationPath()
                                path.append(SettingsDestination.server)
                                settingsNavigationPath = path
                                // Reset destination-based screens, including an open Kavita settings page.
                                settingsNavigationID = UUID()
                                selectedTab = .settings
                            })
                .environment(\.horizontalSizeClass, horizontalSizeClass)
                .tabItem {
                    Label("홈", systemImage: "house.fill")
                }
                .tag(AppTab.home)

            ContentView(isSearchTab: true)
                .background(AppTheme.background.ignoresSafeArea())
                .environment(\.horizontalSizeClass, horizontalSizeClass)
                .tabItem {
                    Label("검색", systemImage: "magnifyingglass")
                }
                .tag(AppTab.search)
            ContentView(navigationPath: $libraryNavigationPath)
                .environment(\.horizontalSizeClass, horizontalSizeClass)
                .tabItem {
                    Label("라이브러리", systemImage: "rectangle.stack.fill")
                }
                .tag(AppTab.library)

            SettingsView(navigationPath: $settingsNavigationPath)
                .id(settingsNavigationID)
                .environment(\.horizontalSizeClass, horizontalSizeClass)
                .tabItem {
                    Label("설정", systemImage: "gearshape")
                }
                .tag(AppTab.settings)
        }
        // Keep Apple's native bottom tab bar on iPad while each tab retains
        // the actual window size class. Liquid Glass rendering remains system-managed.
        .environment(\.horizontalSizeClass, .compact)
        .scrollEdgeEffectStyle(.soft, for: .bottom)
        .foregroundStyle(AppTheme.text)
        .tint(AppTheme.accent)
        .environmentObject(libraryViewModel)
        .environmentObject(libraryPlusViewModel)
        .environment(\.locale, (AppLanguage(rawValue: selectedLanguage) ?? .korean).locale)
        .preferredColorScheme(AppTheme.palette.colorScheme)
        .background(AppTheme.background.ignoresSafeArea())
        .background(WindowBackgroundView(palette: AppTheme.palette).ignoresSafeArea())
        .background(NativeTabBarScaleView(scale: UIDevice.current.userInterfaceIdiom == .phone ? 1.0 : 1.08,
                                          selection: selectedTab,
                                          backdropHeightMultiplier: selectedTab == .search ? 1.5 : 1))
        .task(id: "\(serviceSignature)|\(credentialRevision)") {
            try? await FeaturedPreviewCache.shared.removeExpired()
            libraryPlusViewModel.selectIdentity(serviceSignature)
            let factory = LibraryServiceFactory(baseURLString: serverBaseURL,
                                                apiKey: apiKey.isEmpty ? nil : apiKey)
            await libraryViewModel.restore(service: factory.makeService(),
                                           identity: serviceSignature,
                                           baseURL: serverBaseURL, apiKey: apiKey)
            libraryPlusViewModel.prepareLocalMetadata()
        }
        .onReceive(NotificationCenter.default.publisher(for: .localComicsDidChange)) { _ in
            // Start indexing immediately; only the cover/catalog redraw is debounced.
            libraryPlusViewModel.prepareLocalMetadata()
            localReloadTask?.cancel()
            localReloadTask = Task {
                do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
                await libraryViewModel.reloadLocalComics()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .readerDidClose)) { notification in
            guard notification.object as? String == serviceSignature else { return }
            // Also update catalog read markers/total progress after closing the reader.
            Task { await libraryViewModel.refresh(invalidateCovers: false, replaceInFlight: true) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .readerDidRead)) { notification in
            guard let item = notification.userInfo?["item"] as? ContinueReadingItem,
                  let readAt = notification.userInfo?["readAt"] as? Date else { return }
            let identity = notification.object as? String
            Task { await libraryViewModel.recordReadingActivity(item, identity: identity, readAt: readAt) }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background { didEnterBackground = true }
            guard newPhase == .active, didEnterBackground else { return }
            didEnterBackground = false
            let identity = serviceSignature
            Task {
                await ReaderProgressSaveQueue.shared.wait(identity: identity)
                guard serviceSignature == identity else { return }
                await libraryViewModel.refreshContinueReading()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .seriesReadingPauseDidChange)) { notification in
            guard notification.object as? String == serviceSignature else { return }
            libraryViewModel.applyReadingPauseChange()
        }
        .onReceive(NotificationCenter.default.publisher(for: .seriesReadStateDidChange)) { notification in
            guard notification.object as? String == serviceSignature,
                  let seriesId = notification.userInfo?["seriesId"] as? Int,
                  let read = notification.userInfo?["read"] as? Bool
            else { return }
            Task { await libraryViewModel.applyReadStateChange(seriesId: seriesId, read: read) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .seriesWantToReadDidChange)) { notification in
            guard notification.object as? String == serviceSignature,
                  let series = notification.userInfo?["series"] as? LibrarySeries,
                  let isWanted = notification.userInfo?["isWanted"] as? Bool
            else { return }
            Task { await libraryViewModel.applyWantToReadChange(series: series, isWanted: isWanted) }
        }
    }

    private var serviceSignature: String { "\(serverBaseURL)|\(apiKey)" }
}

private enum AppTab: Hashable {
    case home
    case search
    case library
    case settings
}

/// Colors the window behind navigation transitions as well as the visible root view.
private enum AppNavigationTheme {
    static func apply(to root: UIView? = nil) {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(AppTheme.background)
        appearance.shadowColor = .clear
        appearance.titleTextAttributes = [.foregroundColor: UIColor(AppTheme.text)]
        appearance.largeTitleTextAttributes = [.foregroundColor: UIColor(AppTheme.text)]
        configure(UINavigationBar.appearance(), appearance: appearance)
        if let root { updateBars(in: root, appearance: appearance) }
    }

    private static func configure(_ bar: UINavigationBar, appearance: UINavigationBarAppearance) {
        bar.standardAppearance = appearance
        bar.scrollEdgeAppearance = appearance
        bar.compactAppearance = appearance
        bar.compactScrollEdgeAppearance = appearance
        bar.tintColor = UIColor(AppTheme.accent)
    }

    private static func updateBars(in view: UIView, appearance: UINavigationBarAppearance) {
        if let bar = view as? UINavigationBar { configure(bar, appearance: appearance) }
        for child in view.subviews { updateBars(in: child, appearance: appearance) }
    }
}

private struct WindowBackgroundView: UIViewRepresentable {
    let palette: ThemePalette
    func makeUIView(context _: Context) -> BackgroundView {
        let view = BackgroundView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = UIColor(AppTheme.background)
        return view
    }

    func updateUIView(_ uiView: BackgroundView, context _: Context) {
        uiView.backgroundColor = UIColor(palette.background)
        uiView.window?.backgroundColor = UIColor(palette.background)
        AppNavigationTheme.apply(to: uiView.window)
    }

    final class BackgroundView: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            window?.backgroundColor = UIColor(AppTheme.background)
            AppNavigationTheme.apply(to: window)
        }
    }
}
