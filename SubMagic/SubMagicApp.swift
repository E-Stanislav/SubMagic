//
//  SubMagicApp.swift
//  SubMagic
//
//  Created by Stanislav E on 21.06.2025.
//

import SwiftUI

@main
struct SubMagicApp: App {
    @State private var showFileImporter = false
    
    var body: some Scene {
        WindowGroup {
            ContentView(showFileImporter: $showFileImporter)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Import…") {
                    showFileImporter = true
                }
                .keyboardShortcut("i", modifiers: [.command])
                Button("Close Media…") {
                    NotificationCenter.default.post(name: .closeMedia, object: nil)
                }
                .keyboardShortcut("w", modifiers: [.command])
                .disabled(false)
            }
        }
    }
}

// ВНИЗУ ФАЙЛА
extension Notification.Name {
    static let closeMedia = Notification.Name("CloseMediaNotification")
}
