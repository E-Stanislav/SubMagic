import SwiftUI
import Combine

struct SettingsView: View {
    @AppStorage("whisperPath") private var whisperPath: String = "/Users/stanislave/Documents/Projects/SubMagic/SubMagic/bin/whisper"
    @State private var showFilePicker = false
    @StateObject private var whisperManager = WhisperBinaryManager()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Настройки")
                .font(.title)
                .padding(.top)
            GroupBox(label: Label("Путь к whisper.cpp", systemImage: "terminal")) {
                HStack {
                    TextField("Путь к whisper", text: $whisperPath)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 320)
                    Button {
                        showFilePicker = true
                    } label: {
                        Label("Выбрать…", systemImage: "folder")
                    }
                }
                .padding(.vertical, 4)
                Text("Укажите путь к исполняемому файлу whisper (например, /Users/stanislave/Documents/Projects/SubMagic/SubMagic/bin/whisper)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Divider()
                switch whisperManager.status {
                case .idle:
                    Button("Проверить бинарь whisper.cpp") {
                        whisperManager.ensureWhisperBinary()
                    }
                case .checkingDependencies:
                    ProgressView("Проверка бинаря whisper...")
                case .missingDependencies:
                    Text("Бинарь whisper не найден или не исполняемый.")
                        .foregroundColor(.red)
                    Button("Повторить проверку") {
                        whisperManager.ensureWhisperBinary()
                    }
                case .ready(let url):
                    VStack(alignment: .leading) {
                        Text("whisper.cpp готов: \(url.path)")
                            .foregroundColor(.green)
                        Button("Использовать этот бинарник") {
                            whisperPath = url.path
                        }
                    }
                case .failed(let error):
                    VStack(alignment: .leading) {
                        Text("Ошибка: \(error)")
                            .foregroundColor(.red)
                        Button("Повторить попытку") {
                            whisperManager.ensureWhisperBinary()
                        }
                    }
                }
            }
            .padding(.bottom, 8)
            Divider()
            Spacer()
        }
        .padding()
        .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.executable], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                whisperPath = url.path
            }
        }
    }
}

#Preview {
    SettingsView()
}
