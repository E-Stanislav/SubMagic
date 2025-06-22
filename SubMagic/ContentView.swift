//
//  ContentView.swift
//  SubMagic
//
//  Created by Stanislav Seryi on 25.06.2024.
//

import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 1
    @StateObject private var project = ProjectModel()
    @State private var window: NSWindow?
    
    var body: some View {
        TabView(selection: $selectedTab) {
            ImportView(project: project)
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
        .background(WindowAccessor(window: $window))
        .onChange(of: project.videoURL) { _, newURL in
            window?.title = newURL?.lastPathComponent ?? "SubMagic"
        }
        .onAppear {
            window?.title = "SubMagic"
        }
    }
}

// Helper to access the NSWindow instance from a SwiftUI view
struct WindowAccessor: NSViewRepresentable {
    @Binding var window: NSWindow?

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            self.window = view.window   
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
