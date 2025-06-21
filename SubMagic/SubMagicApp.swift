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
            ContentView()
                .environment(\._showFileImporter, $showFileImporter)
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Import…") {
                    showFileImporter = true
                }
                .keyboardShortcut("i", modifiers: [.command])
            }
        }
    }
}
