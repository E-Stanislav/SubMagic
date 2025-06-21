//
//  ContentView.swift
//  SubMagic
//
//  Created by Stanislav E on 21.06.2025.
//

import SwiftUI
import UniformTypeIdentifiers

private struct ShowFileImporterKey: EnvironmentKey {
    static let defaultValue: Binding<Bool>? = nil
}

extension EnvironmentValues {
    var _showFileImporter: Binding<Bool>? {
        get { self[ShowFileImporterKey.self] }
        set { self[ShowFileImporterKey.self] = newValue }
    }
}

struct ContentView: View {
    @State private var selectedTab = 0
    @State private var selectedVideoURL: URL? = nil
    @State private var showFileImporter = false
    @Environment(\._showFileImporter) private var showFileImporterFromMenu
    
    var body: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                VideoEditorView(videoURL: selectedVideoURL)
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
        .fileImporter(
            isPresented: showFileImporterFromMenu ?? $showFileImporter,
            allowedContentTypes: [.movie, .audio],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    selectedVideoURL = url
                    selectedTab = 1 // Переключаемся на редактор
                }
            case .failure:
                break
            }
        }
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: nil) { providers in
            if let provider = providers.first {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    if let data = item as? Data,
                       let url = URL(dataRepresentation: data, relativeTo: nil) {
                        DispatchQueue.main.async {
                            selectedVideoURL = url
                            selectedTab = 1
                        }
                    } else if let url = item as? URL {
                        DispatchQueue.main.async {
                            selectedVideoURL = url
                            selectedTab = 1
                        }
                    }
                }
                return true
            }
            return false
        }
    }
}

#Preview {
    ContentView()
}
