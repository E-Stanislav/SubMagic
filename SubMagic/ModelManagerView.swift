import SwiftUI

struct ModelManagerView: View {
    var body: some View {
        VStack {
            Text("Менеджер моделей")
                .font(.title)
                .padding()
            // ...добавить список моделей, загрузку, удаление...
            Spacer()
        }
    }
}

#Preview {
    ModelManagerView()
}
