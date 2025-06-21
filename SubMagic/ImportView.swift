import SwiftUI
import UniformTypeIdentifiers

struct ImportView: View {
    @State private var showFilePicker = false
    @State private var selectedFile: URL?

    var body: some View {
        VStack {
            Text("Импорт видео/аудио")
                .font(.title)
                .padding()
            Button(action: {
                showFilePicker = true
            }) {
                Label("Выбрать файл", systemImage: "plus")
            }
            .padding()
            if let file = selectedFile {
                Text("Выбран файл: \(file.lastPathComponent)")
                    .font(.subheadline)
                    .padding(.top, 8)
            }
            Spacer()
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [UTType.movie, UTType.audio],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let url):
                selectedFile = url.first
            case .failure:
                selectedFile = nil
            }
        }
    }
}

#Preview {
    ImportView()
}
