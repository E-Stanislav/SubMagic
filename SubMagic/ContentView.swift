//
//  ContentView.swift
//  SubMagic
//
//  Created by Stanislav E on 21.06.2025.
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var selectedTab = 0
    @State private var selectedVideoURL: URL? = nil
    @State private var securityScopedResource: URL? = nil
    @Binding var showFileImporter: Bool
    // Новый биндинг для управления закрытием видео
    var closeVideo: (() -> Void)? = nil
    
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
            isPresented: $showFileImporter,
            allowedContentTypes: [.movie, .audio],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    // Освобождаем предыдущий ресурс, если был
                    if let previous = securityScopedResource {
                        previous.stopAccessingSecurityScopedResource()
                        securityScopedResource = nil
                    }
                    if url.startAccessingSecurityScopedResource() {
                        selectedVideoURL = url
                        securityScopedResource = url
                        selectedTab = 1 // Переключаемся на редактор
                    } else {
                        print("Не удалось получить доступ к файлу: \(url)")
                    }
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
                            // Освобождаем предыдущий ресурс, если был
                            if let previous = securityScopedResource {
                                previous.stopAccessingSecurityScopedResource()
                                securityScopedResource = nil
                            }
                            selectedVideoURL = url
                            selectedTab = 1
                        }
                    } else if let url = item as? URL {
                        DispatchQueue.main.async {
                            // Освобождаем предыдущий ресурс, если был
                            if let previous = securityScopedResource {
                                previous.stopAccessingSecurityScopedResource()
                                securityScopedResource = nil
                            }
                            selectedVideoURL = url
                            selectedTab = 1
                        }
                    }
                }
                return true
            }
            return false
        }
        .onAppear {
            NotificationCenter.default.addObserver(forName: .closeMedia, object: nil, queue: .main) { _ in
                closeCurrentVideo()
            }
        }
        .onDisappear {
            // Освобождаем ресурс при закрытии окна
            if let previous = securityScopedResource {
                previous.stopAccessingSecurityScopedResource()
                securityScopedResource = nil
            }
            NotificationCenter.default.removeObserver(self, name: .closeMedia, object: nil)
        }
        .onChange(of: selectedVideoURL) { newValue in
            // Если видео закрыто, освобождаем ресурс
            if newValue == nil {
                closeVideo?()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .closeMedia)) { _ in
            closeCurrentVideo()
        }
    }
    // Функция для закрытия видео
    func closeCurrentVideo() {
        if let previous = securityScopedResource {
            previous.stopAccessingSecurityScopedResource()
            securityScopedResource = nil
        }
        selectedVideoURL = nil
    }
}

#Preview {
    ContentView(showFileImporter: .constant(false))
}
