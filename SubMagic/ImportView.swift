import SwiftUI
import UniformTypeIdentifiers

struct ImportView: View {
    @Binding var selectedVideoURL: URL?

    var body: some View {
        VStack {
            Text("Импорт видео/аудио")
                .font(.title)
                .padding()
            if let file = selectedVideoURL {
                Text("Выбран файл: \(file.lastPathComponent)")
                    .font(.subheadline)
                    .padding(.top, 8)
            } else {
                Text("Перетащите файл в окно приложения или используйте File → Import")
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
            }
            Spacer()
        }
    }
}

#Preview {
    ImportView(selectedVideoURL: .constant(nil))
}
