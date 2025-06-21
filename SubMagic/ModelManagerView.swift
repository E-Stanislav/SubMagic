import SwiftUI
import Foundation

struct WhisperModel: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let url: URL
    let filename: String
    let sizeMB: Int
    
    static func == (lhs: WhisperModel, rhs: WhisperModel) -> Bool {
        lhs.name == rhs.name && lhs.filename == rhs.filename
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(filename)
    }
}

class WhisperModelManager: ObservableObject {
    @Published var modelPath: String? = UserDefaults.standard.string(forKey: "whisperModelPath")
    @Published var isDownloading: Bool = false
    @Published var downloadProgress: Double = 0
    @Published var error: String? = nil
    @Published var downloadingModelName: String? = nil
    private var currentDownloadTask: URLSessionDownloadTask? = nil
    
    let availableModels: [WhisperModel] = [
        WhisperModel(name: "tiny",  url: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin")!,  filename: "ggml-tiny.bin",  sizeMB: 75),
        WhisperModel(name: "base",  url: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin")!,  filename: "ggml-base.bin",  sizeMB: 142),
        WhisperModel(name: "small", url: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin")!, filename: "ggml-small.bin", sizeMB: 466),
        WhisperModel(name: "medium",url: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.bin")!,filename: "ggml-medium.bin",sizeMB: 1460),
        WhisperModel(name: "large", url: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3.bin")!, filename: "ggml-large-v3.bin", sizeMB: 2890)
    ]
    
    func setModelPath(_ path: String) {
        modelPath = path
        UserDefaults.standard.set(path, forKey: "whisperModelPath")
    }
    
    func downloadModel(_ model: WhisperModel, to directory: URL, completion: @escaping (Bool) -> Void) {
        isDownloading = true
        error = nil
        downloadingModelName = model.name
        downloadProgress = 0
        let destination = directory.appendingPathComponent(model.filename)
        var request = URLRequest(url: model.url)
        // Добавляем user-agent, как у браузера, чтобы HuggingFace не блокировал
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.1 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        let task = URLSession.shared.downloadTask(with: request) { url, response, err in
            DispatchQueue.main.async {
                self.isDownloading = false
                self.downloadingModelName = nil
                self.currentDownloadTask = nil
                if let url = url {
                    do {
                        try FileManager.default.moveItem(at: url, to: destination)
                        self.setModelPath(destination.path)
                        completion(true)
                    } catch {
                        self.error = error.localizedDescription
                        completion(false)
                    }
                } else {
                    if (err as? URLError)?.code == .cancelled {
                        self.error = "Загрузка отменена"
                    } else {
                        self.error = err?.localizedDescription ?? "Unknown error"
                    }
                    completion(false)
                }
            }
        }
        self.currentDownloadTask = task
        _ = task.progress.observe(\.fractionCompleted) { progress, _ in
            DispatchQueue.main.async {
                self.downloadProgress = progress.fractionCompleted
            }
        }
        task.resume()
    }
    func cancelDownload() {
        currentDownloadTask?.cancel()
        isDownloading = false
        downloadingModelName = nil
        currentDownloadTask = nil
    }
}

struct ModelManagerView: View {
    @StateObject private var modelManager = WhisperModelManager()
    @State private var showFilePicker = false
    @State private var selectedModel: WhisperModel? = nil
    @State private var showStatusBar = false
    @State private var downloadedModels: [URL] = []
    @State private var activeModelPath: String? = UserDefaults.standard.string(forKey: "whisperModelPath")
    
    // Папка для моделей внутри Application Support
    private var modelsDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("SubMagic/models", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    
    private func refreshDownloadedModels() {
        let urls = (try? FileManager.default.contentsOfDirectory(at: modelsDirectory, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []
        downloadedModels = urls.filter { $0.pathExtension == "bin" }
    }
    
    private func setActiveModel(_ url: URL) {
        modelManager.setModelPath(url.path)
        activeModelPath = url.path
    }
    
    private func deleteModel(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
        if activeModelPath == url.path {
            modelManager.setModelPath("")
            activeModelPath = nil
        }
        refreshDownloadedModels()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Менеджер моделей Whisper")
                .font(.title)
                .padding(.top)
            if let path = modelManager.modelPath, !path.isEmpty {
                Text("Текущая модель: \(URL(fileURLWithPath: path).lastPathComponent)")
                    .font(.subheadline)
            } else {
                Text("Модель не выбрана")
                    .foregroundColor(.secondary)
            }
            HStack(spacing: 12) {
                Button("Выбрать файл модели…") {
                    showFilePicker = true
                }
                Picker("Модель:", selection: $selectedModel) {
                    Text("— выберите —").tag(Optional<WhisperModel>(nil))
                    ForEach(modelManager.availableModels) { model in
                        Text("\(model.name) (\(model.sizeMB) MB)").tag(Optional(model))
                    }
                }
                .frame(width: 200)
                Button("Скачать выбранную модель…") {
                    if let model = selectedModel {
                        modelManager.downloadModel(model, to: modelsDirectory) { _ in
                            refreshDownloadedModels()
                        }
                    }
                }
                .disabled(selectedModel == nil || modelManager.isDownloading)
            }
            if modelManager.isDownloading, let name = modelManager.downloadingModelName {
                VStack(alignment: .leading) {
                    Text("Загрузка модели: \(name)")
                    ProgressView(value: modelManager.downloadProgress) {
                        Text(String(format: "%.0f%%", modelManager.downloadProgress * 100))
                    }
                    .progressViewStyle(LinearProgressViewStyle())
                    Button("Стоп") {
                        modelManager.cancelDownload()
                    }
                    .padding(.top, 4)
                }
            }
            if let error = modelManager.error {
                Text("Ошибка: \(error)")
                    .foregroundColor(.red)
            }
            Divider()
            Text("Скачанные модели:")
                .font(.headline)
            List {
                ForEach(downloadedModels, id: \.path) { url in
                    HStack {
                        Text(url.lastPathComponent)
                            .font(activeModelPath == url.path ? .headline : .body)
                        Spacer()
                        if activeModelPath == url.path {
                            Text("(активная)")
                                .foregroundColor(.accentColor)
                        } else {
                            Button("Сделать активной") {
                                setActiveModel(url)
                            }
                        }
                        Button(role: .destructive) {
                            deleteModel(url)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(BorderlessButtonStyle())
                    }
                }
            }
            .frame(height: 180)
            .onAppear {
                refreshDownloadedModels()
                activeModelPath = modelManager.modelPath
            }
            .onChange(of: modelManager.modelPath) { _, newPath in
                activeModelPath = newPath
            }
            .onChange(of: modelManager.isDownloading) { _, _ in
                refreshDownloadedModels()
            }
            Spacer()
        }
        .padding()
        .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.data], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                modelManager.setModelPath(url.path)
                refreshDownloadedModels()
            }
        }
        .onChange(of: modelManager.isDownloading) { _, downloading in
            showStatusBar = downloading
        }
        if showStatusBar, modelManager.isDownloading {
            WhisperDownloadStatusBar(progress: modelManager.downloadProgress, modelName: modelManager.downloadingModelName)
                .transition(.move(edge: .bottom))
                .animation(.default, value: modelManager.downloadProgress)
        }
    }
}

struct WhisperDownloadStatusBar: View {
    let progress: Double
    let modelName: String?
    var body: some View {
        HStack {
            if let name = modelName {
                Text("Загрузка: \(name)")
            }
            ProgressView(value: progress)
                .frame(width: 120)
            Text(String(format: "%.0f%%", progress * 100))
                .font(.caption)
        }
        .padding(8)
        .background(Color(.windowBackgroundColor).opacity(0.95))
        .cornerRadius(8)
        .shadow(radius: 2)
        .padding(.horizontal)
    }
}

#Preview {
    ModelManagerView()
}
