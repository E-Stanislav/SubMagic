//
//  ContentView.swift
//  SubMagic
//
//  Created by Stanislav Seryi on 25.06.2024.
//

import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 1
    
    var body: some View {
        TabView(selection: $selectedTab) {
            ImportView()
                .tabItem {
                    Label("Редактор", systemImage: "film")
                }
                .tag(1)
            
            SettingsView()
                .tabItem {
                    Label("Настройки", systemImage: "gear")
                }
                .tag(2)
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
