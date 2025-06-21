import SwiftUI

struct SettingsView: View {
    var body: some View {
        VStack {
            Text("Настройки")
                .font(.title)
                .padding()
            // ...добавить настройки, выбор языка, темы, бенчмарк...
            Spacer()
        }
    }
}

#Preview {
    SettingsView()
}
