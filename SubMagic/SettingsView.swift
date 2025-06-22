//
//  SettingsView.swift
//  SubMagic
//
//  Created by Stanislav Seryi on 25.06.2024.
//

import SwiftUI

struct SettingsView: View {
    var body: some View {
        Form {
            Section(header: Text("Управление моделями Whisper")) {
                ModelManagerView()
            }
        }
        .padding()
        .frame(minWidth: 400, minHeight: 400)
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}
