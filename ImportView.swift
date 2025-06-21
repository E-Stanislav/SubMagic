import SwiftUI

struct ImportView: View {
    @State private var selectedFile: URL? = nil
    @State private var showFilePicker = false
    
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
            allowedContentTypes: [.movie, .audio],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                selectedFile = urls.first
            case .failure:
                selectedFile = nil
            }
        }
    }
}

#Preview {
    ImportView()
}
