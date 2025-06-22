//
//  SubMagicApp.swift
//  SubMagic
//
//  Created by Stanislav Seryi on 25.06.2024.
//

import SwiftUI

@main
struct SubMagicApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .saveItem) {}
            CommandGroup(replacing: .undoRedo) {}
        }

        Settings {
            SettingsView()
        }
    }
}

// ВНИЗУ ФАЙЛА
extension Notification.Name {
    static let closeMedia = Notification.Name("CloseMediaNotification")
}
