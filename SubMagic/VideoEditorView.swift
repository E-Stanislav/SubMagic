import SwiftUI
import AVKit
import AVFoundation

struct VideoEditorView: View {
    @ObservedObject var playerHolder: PlayerHolder
    @State private var showFullScreen = false
    @FocusState private var isVideoFocused: Bool
    @State private var fullScreenWindowController: FullScreenWindowController? = nil
    @State private var selectedTargetLanguage: String = "en"
    @State private var isTranslating: Bool = false
    @State private var translationResult: String? = nil
    let supportedLanguages: [(code: String, name: String)] = [
        ("en", "Английский"), ("ru", "Русский"), ("de", "Немецкий"), ("fr", "Французский"), ("es", "Испанский"), ("zh", "Китайский"), ("ja", "Японский"), ("it", "Итальянский"), ("tr", "Турецкий")
    ]
    
    private func getWhisperPath() -> String? {
        // Сначала пробуем найти в bundle (для production)
        if let bundlePath = Bundle.main.path(forResource: "whisper-cli", ofType: nil, inDirectory: "bin") {
            return bundlePath
        }
        
        // Затем пробуем абсолютный путь к новому бинарю (для development)
        let developmentPath = "/Users/stanislave/Documents/Projects/SubMagic/SubMagic/bin/whisper-cli"
        if FileManager.default.fileExists(atPath: developmentPath) {
            return developmentPath
        }
        
        // Fallback к старому бинарю (если новый не найден)
        let oldDevelopmentPath = "/Users/stanislave/Documents/Projects/SubMagic/SubMagic/bin/whisper"
        if FileManager.default.fileExists(atPath: oldDevelopmentPath) {
            return oldDevelopmentPath
        }
        
        // Наконец, пробуем UserDefaults (если пользователь указал свой путь)
        if let userPath = UserDefaults.standard.string(forKey: "whisperPath"),
           FileManager.default.fileExists(atPath: userPath) {
            return userPath
        }
        
        return nil
    }
    
    var body: some View {
        VStack {
            Text("Редактор видео и субтитров")
                .font(.title)
                .padding()
            if let player = playerHolder.player {
                ZStack {
                    VideoPlayer(player: player)
                        .aspectRatio(16/9, contentMode: .fit)
                        .frame(minHeight: 300)
                        .padding()
                }
                .contextMenu {
                    Button("Открыть в полном экране") {
                        openFullScreen(player: player)
                    }
                    .keyboardShortcut("f", modifiers: .command)
                }
                .background(KeyboardShortcutCatcher(openFullScreen: { openFullScreen(player: player) }))
                // --- КНОПКИ ПОД ВИДЕО ---
                HStack(spacing: 12) {
                    Button(action: transcribeWithWhisper) {
                        Label("Транскрибировать (Whisper)", systemImage: "waveform")
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.15)))
                    Picker("Язык перевода", selection: $selectedTargetLanguage) {
                        ForEach(supportedLanguages, id: \.code) { lang in
                            Text(lang.name).tag(lang.code)
                        }
                    }
                    .frame(width: 160)
                    Button(action: translateWithWhisper) {
                        Label("Перевести (Whisper)", systemImage: "globe")
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.15)))
                    .disabled(isTranslating)
                }
                .padding(.bottom, 8)
            } else {
                Text("Нет выбранного видео")
                    .foregroundColor(.secondary)
                    .padding()
            }
            Spacer()
        }
        .onReceive(NotificationCenter.default.publisher(for: .closeMedia)) { _ in
            fullScreenWindowController?.close()
            fullScreenWindowController = nil
        }
        .alert(isPresented: Binding<Bool>(
            get: { translationResult != nil },
            set: { if !$0 { translationResult = nil } }
        )) {
            Alert(title: Text("Результат перевода"), message: Text(translationResult ?? ""), dismissButton: .default(Text("OK")))
        }
    }
    
    private func openFullScreen(player: AVPlayer) {
        fullScreenWindowController?.close()
        let controller = FullScreenWindowController(player: player) {
            self.fullScreenWindowController = nil
        }
        fullScreenWindowController = controller
        controller.showWindow(nil)
        controller.window?.toggleFullScreen(nil)
    }
}

// --- ВНИЗУ ФАЙЛА ---

import AppKit
import AVFoundation

extension VideoEditorView {
    func transcribeWithWhisper() {
        guard let url = playerHolder.player?.currentItem?.asset as? AVURLAsset else { return }
        let videoURL = url.url
        let audioURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        
        print("[DEBUG] Starting audio extraction to: \(audioURL.path)")
        
        extractAudio(from: videoURL, to: audioURL) { success in
            if success {
                print("[DEBUG] Audio extraction successful. Running transcription.")
                self.runWhisperTranscription(audioURL: audioURL)
            } else {
                print("[DEBUG] Audio extraction failed.")
                self.showTranscriptionResult("Ошибка извлечения аудио")
            }
        }
    }
    
    func extractAudio(from videoURL: URL, to audioURL: URL, completion: @escaping (Bool) -> Void) {
        let asset = AVURLAsset(url: videoURL)

        guard let reader = try? AVAssetReader(asset: asset) else {
            print("[AUDIO_EXPORT_ERROR] Failed to create AVAssetReader")
            completion(false)
            return
        }

        guard let audioTrack = asset.tracks(withMediaType: .audio).first else {
            print("[AUDIO_EXPORT_ERROR] No audio track found in the video")
            completion(false)
            return
        }

        let readerOutputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        
        let readerOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: readerOutputSettings)

        if reader.canAdd(readerOutput) {
            reader.add(readerOutput)
        } else {
            print("[AUDIO_EXPORT_ERROR] Can't add reader output")
            completion(false)
            return
        }

        if FileManager.default.fileExists(atPath: audioURL.path) {
            try? FileManager.default.removeItem(at: audioURL)
        }

        guard let writer = try? AVAssetWriter(outputURL: audioURL, fileType: .wav) else {
            print("[AUDIO_EXPORT_ERROR] Failed to create AVAssetWriter for url \(audioURL)")
            completion(false)
            return
        }

        let writerInput = AVAssetWriterInput(mediaType: .audio, outputSettings: readerOutput.outputSettings)
        writerInput.expectsMediaDataInRealTime = false

        if writer.canAdd(writerInput) {
            writer.add(writerInput)
        } else {
            print("[AUDIO_EXPORT_ERROR] Can't add writer input")
            completion(false)
            return
        }

        writer.startWriting()
        reader.startReading()
        writer.startSession(atSourceTime: .zero)
        
        let queue = DispatchQueue(label: "audio-extraction-queue", qos: .userInitiated)
        
        writerInput.requestMediaDataWhenReady(on: queue) {
            while writerInput.isReadyForMoreMediaData {
                if reader.status == .reading, let sampleBuffer = readerOutput.copyNextSampleBuffer() {
                    if !writerInput.append(sampleBuffer) {
                         print("[AUDIO_EXPORT_ERROR] Failed to append buffer")
                         reader.cancelReading()
                         break
                    }
                } else {
                    writerInput.markAsFinished()
                    
                    if reader.status == .failed {
                        print("[AUDIO_EXPORT_ERROR] Reader failed with error: \(reader.error?.localizedDescription ?? "Unknown error")")
                        writer.cancelWriting()
                        completion(false)
                        return
                    }
                    
                    writer.finishWriting {
                        DispatchQueue.main.async {
                            if writer.status == .completed {
                                completion(true)
                            } else {
                                print("[AUDIO_EXPORT_ERROR] Writer failed with status \(writer.status.rawValue)")
                                if let writerError = writer.error {
                                    print("[AUDIO_EXPORT_ERROR] Writer error: \(writerError.localizedDescription)")
                                }
                                completion(false)
                            }
                        }
                    }
                    break
                }
            }
        }
    }
    
    func runWhisperTranscription(audioURL: URL) {
        guard let whisperPath = getWhisperPath() else {
            showTranscriptionResult("Файл бинаря whisper не найден.")
            return
        }

        let modelPath = UserDefaults.standard.string(forKey: "whisperModelPath") ?? ""
        if modelPath.isEmpty || !FileManager.default.fileExists(atPath: modelPath) {
            showTranscriptionResult("Модель не выбрана или не скачана.")
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: whisperPath)
        let arguments = ["--file", audioURL.path, "--model", modelPath, "--language", "ru", "--no-timestamps", "--no-prints"]
        process.arguments = arguments
        
        print("[DEBUG] Running command: \(whisperPath) \(arguments.joined(separator: " "))")

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        process.terminationHandler = { process in
            print("[DEBUG] Process terminated. Status: \(process.terminationStatus), Reason: \(process.terminationReason.rawValue)")
        }

        do {
            try process.run()
            print("[DEBUG] Whisper process started successfully.")
        } catch {
            showTranscriptionResult("Ошибка запуска whisper: \(error.localizedDescription)")
            return
        }
        
        // Читаем stderr для отладки
        DispatchQueue.global().async {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            if let errorOutput = String(data: errorData, encoding: .utf8), !errorOutput.isEmpty {
                print("[DEBUG] Whisper stderr:\n---\n\(errorOutput)\n---")
            }
        }
        
        // Читаем stdout для результата
        DispatchQueue.global().async {
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: outputData, encoding: .utf8) ?? ""
            
            DispatchQueue.main.async {
                if output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    self.showTranscriptionResult("Транскрипция не дала результата. Проверьте лог в Xcode.")
                } else {
                    self.showTranscriptionResult(output)
                }
            }
        }
    }
    
    func showTranscriptionResult(_ text: String) {
        let alert = NSAlert()
        alert.messageText = "Результат транскрипции"
        alert.informativeText = text.prefix(5000).description // Ограничение на размер
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    
    func translateWithWhisper() {
        guard let url = playerHolder.player?.currentItem?.asset as? AVURLAsset else { return }
        let videoURL = url.url
        let audioURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        isTranslating = true
        extractAudio(from: videoURL, to: audioURL) { success in
            if success {
                runWhisperTranslation(audioURL: audioURL, targetLanguage: selectedTargetLanguage)
            } else {
                showTranslationResult("Ошибка извлечения аудио")
            }
        }
    }
    func runWhisperTranslation(audioURL: URL, targetLanguage: String) {
        guard let whisperPath = getWhisperPath() else {
            showTranslationResult("Файл бинаря whisper не найден. Проверьте настройки в WhisperBinaryManager.")
            return
        }
        
        let modelPath = UserDefaults.standard.string(forKey: "whisperModelPath") ?? ""
        if modelPath.isEmpty || !FileManager.default.fileExists(atPath: modelPath) {
            showTranslationResult("Модель не выбрана или не скачана. Укажите путь к модели в настройках.")
            return
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: whisperPath)
        
        // Используем явные флаги для аргументов и отключаем таймстампы
        let arguments = ["--file", audioURL.path, "--model", modelPath, "--language", targetLanguage, "--translate", "--no-timestamps"]
        process.arguments = arguments
        
        print("[DEBUG] Running command: \(whisperPath) \(arguments.joined(separator: " "))")

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        process.terminationHandler = { process in
            print("[DEBUG] Process terminated. Status: \(process.terminationStatus), Reason: \(process.terminationReason.rawValue)")
        }

        do {
            try process.run()
            print("[DEBUG] Whisper process started successfully.")
        } catch {
            showTranslationResult("Ошибка запуска whisper: \(error.localizedDescription)")
            return
        }
        
        DispatchQueue.global().async {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            
            DispatchQueue.main.async {
                print("[DEBUG] Raw whisper output:\n---\n\(output)\n---")
                if output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    self.showTranslationResult("Перевод не дал результата. Проверьте лог в Xcode на наличие ошибок от whisper-cli.")
                } else {
                    self.showTranslationResult(output)
                }
            }
        }
    }
    func showTranslationResult(_ text: String) {
        isTranslating = false
        translationResult = text.prefix(5000).description
    }
}

import AppKit
class FullScreenWindowController: NSWindowController {
    private var onClose: (() -> Void)?
    init(player: AVPlayer, onClose: (() -> Void)? = nil) {
        let hosting = NSHostingController(rootView: FullScreenVideoPlayerStandalone(player: player, onClose: onClose))
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .resizable, .fullSizeContentView]
        window.title = "Полноэкранное видео"
        window.isReleasedWhenClosed = false
        window.backgroundColor = .black
        super.init(window: window)
        self.onClose = onClose
        window.delegate = self
    }
    required init?(coder: NSCoder) { fatalError() }
    override func close() {
        super.close()
        onClose?()
    }
}

extension FullScreenWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        onClose?()
    }
}

struct FullScreenVideoPlayerStandalone: View {
    let player: AVPlayer
    var onClose: (() -> Void)?
    @Environment(\.presentationMode) private var presentationMode
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            VideoPlayer(player: player)
                .ignoresSafeArea()
            Button(action: {
                NSApp.keyWindow?.close()
                onClose?()
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.white)
                    .padding()
            }
        }
        .background(FullScreenKeyboardCatcher(onClose: {
            NSApp.keyWindow?.close()
        }))
    }
}

struct FullScreenKeyboardCatcher: NSViewRepresentable {
    var onClose: () -> Void
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Только закрытие полноэкранного окна, не сбрасываем выбранный файл
            if event.keyCode == 53 || (event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "f") {
                onClose() // Закрывает только окно
                return nil
            }
            return event
        }
        context.coordinator.monitor = monitor
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
    func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        if let monitor = coordinator.monitor {
            NSEvent.removeMonitor(monitor)
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    class Coordinator {
        var monitor: Any?
    }
}

// KeyboardShortcutCatcher: View для перехвата Command+F
struct KeyboardShortcutCatcher: NSViewRepresentable {
    var openFullScreen: () -> Void
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "f" {
                openFullScreen()
                return nil
            }
            return event
        }
        context.coordinator.monitor = monitor
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
    func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        if let monitor = coordinator.monitor {
            NSEvent.removeMonitor(monitor)
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    class Coordinator {
        var monitor: Any?
    }
}

#Preview {
    VideoEditorView(playerHolder: PlayerHolder())
}
