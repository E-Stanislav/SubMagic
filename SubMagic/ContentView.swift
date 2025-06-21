//
//  ContentView.swift
//  SubMagic
//
//  Created by Stanislav E on 21.06.2025.
//

import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            ImportView()
                .tabItem {
                    Label("Импорт", systemImage: "square.and.arrow.down")
                }
                .tag(0)
            VideoEditorView()
                .tabItem {
                    Label("Редактор", systemImage: "film")
                }
                .tag(1)
            ModelManagerView()
                .tabItem {
                    Label("Модели", systemImage: "cpu")
                }
                .tag(2)
            SettingsView()
                .tabItem {
                    Label("Настройки", systemImage: "gear")
                }
                .tag(3)
        }
    }
}

#Preview {
    ContentView()
}
