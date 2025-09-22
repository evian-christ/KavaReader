//
//  KavaReaderApp.swift
//  KavaReader
//
//  Created by Chan on 22/09/2025.
//

import SwiftUI

@main
struct KavaReaderApp: App {
    var body: some Scene {
        WindowGroup {
            TabView {
                ContentView()
                    .tabItem {
                        Label("라이브러리", systemImage: "rectangle.stack.fill")
                    }

                SettingsView()
                    .tabItem {
                        Label("설정", systemImage: "gearshape")
                    }
            }
        }
    }
}
