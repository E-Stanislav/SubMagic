//
//  VideoEditorView.swift
//  SubMagic
//
//  Created by Stanislav Seryi on 25.06.2024.
//

import SwiftUI
import AVKit
import AVFoundation

struct VideoEditorView: View {
    @ObservedObject var project: ProjectModel
    @ObservedObject var transcriptionState: TranscriptionState
    let supportedLanguages: [(code: String, name: String)] = [
        ("en", "Английский"), ("ru", "Русский"), ("de", "Немецкий"), ("fr", "Французский"), ("es", "Испанский"), ("zh", "Китайский"), ("ja", "Японский"), ("it", "Итальянский"), ("tr", "Турецкий")
    ]
    @State private var showFullScreen = false
    @FocusState private var isVideoFocused: Bool
    @State private var fullScreenWindowController: FullScreenWindowController? = nil
    var body: some View {
        VStack(spacing: 0) {
            // Динамический заголовок
            Text(project.videoURL?.lastPathComponent ?? "Редактор")
                .font(.title2.bold())
                .foregroundColor(.secondary)
                .padding()
                .frame(maxWidth: .infinity)
                .background(.bar)
            Divider()
            if let player = transcriptionState.player {
                ZStack {
                    VideoPlayer(player: player)
                        .onAppear {
                            player.play()
                        }
                    VStack {
                        Spacer()
                        if !transcriptionState.subtitlesHidden, let text = transcriptionState.transcriptionResult ?? transcriptionState.translationResult, !text.isEmpty {
                            Text(text)
                                .foregroundColor(.white)
                                .padding()
                                .background(Color.black.opacity(0.5))
                                .cornerRadius(8)
                                .padding(.bottom, 50)
                                .transition(.opacity.animation(.easeInOut))
                        }
                        if let error = transcriptionState.lastError {
                            VStack {
                                Spacer()
                                Text(error)
                                    .foregroundColor(.white)
                                    .padding()
                                    .background(Color.red.opacity(0.8))
                                    .cornerRadius(8)
                                    .padding(.bottom, 60)
                                Button("Скрыть ошибку") {
                                    transcriptionState.lastError = nil
                                }
                                .padding(.bottom, 40)
                            }
                            .transition(.opacity.animation(.easeInOut))
                        }
                    }
                }
                .onDisappear {
                    stopWhisperProcessing()
                    player.pause()
                }
                .contextMenu {
                    Button("Открыть в полном экране") {
                        openFullScreen(player: player)
                    }
                    .keyboardShortcut("f", modifiers: .command)
                }
                .background(KeyboardShortcutCatcher(openFullScreen: { openFullScreen(player: player) }))
                HStack {
                    Button("Транскрибировать") {
                        transcriptionState.subtitlesHidden = false
                        Task { await transcribeWithWhisper() }
                    }
                    Button("Перевести") {
                        transcriptionState.subtitlesHidden = false
                        transcriptionState.isTranslating.toggle()
                    }
                    .popover(isPresented: $transcriptionState.isTranslating, arrowEdge: .bottom) {
                        VStack {
                            Picker("Выберите язык", selection: $transcriptionState.selectedLanguage) {
                                ForEach(supportedLanguages, id: \.code) { lang in
                                    Text(lang.name).tag(lang.code)
                                }
                            }
                            .pickerStyle(MenuPickerStyle())
                            Button("Начать перевод") {
                                transcriptionState.subtitlesHidden = false
                                Task { await translateWithWhisper(targetLanguage: transcriptionState.selectedLanguage) }
                                transcriptionState.isTranslating = false
                            }
                        }
                        .padding()
                    }
                    if ((transcriptionState.transcriptionResult != nil && !transcriptionState.transcriptionResult!.isEmpty) || (transcriptionState.translationResult != nil && !transcriptionState.translationResult!.isEmpty)) && !transcriptionState.subtitlesHidden {
                        Button("Скрыть субтитры") {
                            transcriptionState.subtitlesHidden = true
                        }
                    }
                    Spacer()
                    Button(role: .destructive) {
                        project.closeProject()
                    } label: {
                        Label("Закрыть", systemImage: "xmark.circle")
                    }
                }
                .padding()
            } else {
                Text("Загрузка видео...")
                    .onAppear {
                        if let url = project.videoURL {
                            transcriptionState.player = AVPlayer(url: url)
                        }
                    }
            }
            Spacer()
        }
        .onReceive(NotificationCenter.default.publisher(for: .closeMedia)) { _ in
            fullScreenWindowController?.close()
            fullScreenWindowController = nil
        }
        .onAppear {
            if transcriptionState.player == nil, let url = project.videoURL {
                transcriptionState.player = AVPlayer(url: url)
            }
        }
        .onChange(of: project.videoURL) { _, newURL in
            transcriptionState.player?.pause()
            stopWhisperProcessing()
            transcriptionState.transcriptionResult = nil
            transcriptionState.translationResult = nil
            if let newURL = newURL {
                let newPlayer = AVPlayer(url: newURL)
                transcriptionState.player = newPlayer
                newPlayer.play()
            } else {
                transcriptionState.player = nil
            }
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
    private func stopWhisperProcessing() {
        if let player = transcriptionState.player, let token = transcriptionState.timeObserverToken {
            player.removeTimeObserver(token)
            transcriptionState.timeObserverToken = nil
        }
        transcriptionState.processedSegments.removeAll()
    }
    func transcribeWithWhisper() async {
        stopWhisperProcessing()
        transcriptionState.transcriptionResult = nil
        transcriptionState.translationResult = nil
        await startProcessing(isTranslation: false)
    }
    func translateWithWhisper(targetLanguage: String) async {
        stopWhisperProcessing()
        transcriptionState.transcriptionResult = nil
        transcriptionState.translationResult = nil
        await startProcessing(isTranslation: true, language: targetLanguage)
    }
    private func startProcessing(isTranslation: Bool, language: String = "ru") async {
        guard let player = transcriptionState.player, let videoURL = (player.currentItem?.asset as? AVURLAsset)?.url else {
            print("[ERROR] Player or video URL not available.")
            return
        }
        stopWhisperProcessing()
        if isTranslation {
            transcriptionState.translationResult = ""
            transcriptionState.transcriptionResult = nil
        } else {
            transcriptionState.transcriptionResult = ""
            transcriptionState.translationResult = nil
        }

        guard let whisperPath = getWhisperPath() else { 
            print("[ERROR] Whisper binary not found")
            return 
        }
        
        print("[DEBUG] Using whisper binary: \(whisperPath)")
        
        // Получаем путь к модели - сначала из UserDefaults, затем из папки bin
        var modelPath = UserDefaults.standard.string(forKey: "whisperModelPath") ?? ""
        if modelPath.isEmpty || !FileManager.default.fileExists(atPath: modelPath) {
            // Пробуем найти модель в bundle приложения
            if let bundleModelPath = Bundle.main.path(forResource: "ggml-base.en", ofType: "bin") {
                modelPath = bundleModelPath
                print("[DEBUG] Using model from app bundle: \(modelPath)")
            } else {
                // Пробуем найти модель в папке bin
                let binModelPath = "/Users/stanislave/Documents/Projects/SubMagic/SubMagic/bin/ggml-base.en.bin"
                if FileManager.default.fileExists(atPath: binModelPath) {
                    modelPath = binModelPath
                    print("[DEBUG] Using model from bin directory: \(modelPath)")
                } else {
                    print("[ERROR] Model file not found. Please download a model in Settings.")
                    return
                }
            }
        } else {
            print("[DEBUG] Using model from UserDefaults: \(modelPath)")
        }

        let asset = AVURLAsset(url: videoURL)
        guard let duration = try? await asset.load(.duration) else { return }
        let durationInSeconds = CMTimeGetSeconds(duration)
        let segmentDuration: Double = 10.0

        print("[DEBUG] Starting processing with language: \(language), isTranslation: \(isTranslation)")

        transcriptionState.timeObserverToken = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1.0, preferredTimescale: 600), queue: .main) { [self] _ in
            guard let currentTime = self.transcriptionState.player?.currentTime().seconds, currentTime < durationInSeconds else { return }
            
            let segmentIndex = Int(floor(currentTime / segmentDuration))
            
            if !transcriptionState.processedSegments.contains(segmentIndex) {
                transcriptionState.processedSegments.insert(segmentIndex)
                
                Task {
                    await MainActor.run {
                        if isTranslation {
                            self.transcriptionState.translationResult = "..."
                        } else {
                            self.transcriptionState.transcriptionResult = "..."
                        }
                    }
                    
                    let result = await self.processSegment(
                        segmentIndex: segmentIndex,
                        videoURL: videoURL,
                        segmentDuration: segmentDuration,
                        duration: durationInSeconds,
                        whisperPath: whisperPath,
                        modelPath: modelPath,
                        language: language,
                        isTranslation: isTranslation
                    )
                    
                    await MainActor.run {
                        if isTranslation {
                            self.transcriptionState.translationResult = result
                        } else {
                            self.transcriptionState.transcriptionResult = result
                        }
                    }
                }
            }
        }
    }
    
    private func processSegment(segmentIndex: Int, videoURL: URL, segmentDuration: Double, duration: Double, whisperPath: String, modelPath: String, language: String, isTranslation: Bool) async -> String {
        let startTime = Double(segmentIndex) * segmentDuration
        let endTime = min(startTime + segmentDuration, duration)
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("segment_\(UUID().uuidString).wav")

        let success = await extractAudioSegment(from: videoURL, to: tempURL, startTime: startTime, endTime: endTime)
        
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        guard success else {
            print("[ERROR] Failed to extract segment \(segmentIndex)")
            transcriptionState.lastError = "Ошибка при извлечении сегмента \(segmentIndex)"
            return ""
        }

        return await processAudioSegment(tempURL, whisperPath: whisperPath, modelPath: modelPath, language: language, isTranslation: isTranslation)
    }

    func extractAudioSegment(from sourceURL: URL, to destinationURL: URL, startTime: Double, endTime: Double) async -> Bool {
        let asset = AVURLAsset(url: sourceURL)

        guard let audioTrack = (try? await asset.loadTracks(withMediaType: .audio))?.first else {
            print("[ERROR] No audio track found in the asset.")
            transcriptionState.lastError = "Не найден аудиотрек в ассете"
            return false
        }

        let timeRange = CMTimeRange(start: CMTime(seconds: startTime, preferredTimescale: 600),
                                    end: CMTime(seconds: endTime, preferredTimescale: 600))

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try? FileManager.default.removeItem(at: destinationURL)
        }

        do {
            let reader = try AVAssetReader(asset: asset)
            let readerOutputSettings: [String: Any] = [ AVFormatIDKey: kAudioFormatLinearPCM ]
            let readerOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: readerOutputSettings)
            
            if reader.canAdd(readerOutput) { reader.add(readerOutput) } else {
                print("[ERROR] Cannot add reader output.")
                transcriptionState.lastError = "Невозможно добавить выходной поток чтения"
                return false
            }

            let writer = try AVAssetWriter(url: destinationURL, fileType: .wav)
            let writerInputSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 16000,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false
            ]
            let writerInput = AVAssetWriterInput(mediaType: .audio, outputSettings: writerInputSettings)

            if writer.canAdd(writerInput) { writer.add(writerInput) } else {
                print("[ERROR] Cannot add writer input.")
                transcriptionState.lastError = "Невозможно добавить входной поток записи"
                return false
            }
            
            reader.timeRange = timeRange
            writer.shouldOptimizeForNetworkUse = false

            guard reader.startReading() else {
                print("[ERROR] Failed to start asset reader: \(reader.error?.localizedDescription ?? "Unknown error")")
                transcriptionState.lastError = "Невозможно начать чтение ассета: \(reader.error?.localizedDescription ?? "Неизвестная ошибка")"
                return false
            }
            
            writer.startWriting()
            writer.startSession(atSourceTime: timeRange.start)
            
            return await withCheckedContinuation { continuation in
                let queue = DispatchQueue(label: "audio.segment.processing.queue")
                writerInput.requestMediaDataWhenReady(on: queue) {
                    while writerInput.isReadyForMoreMediaData {
                        if reader.status == .reading, let sampleBuffer = readerOutput.copyNextSampleBuffer() {
                            if !writerInput.append(sampleBuffer) {
                                print("[ERROR] Failed to append sample buffer to writer.")
                                reader.cancelReading()
                                writer.finishWriting { continuation.resume(returning: false) }
                                return
                            }
                        } else {
                            writerInput.markAsFinished()
                            writer.finishWriting {
                                continuation.resume(returning: writer.status == .completed)
                            }
                            break
                        }
                    }
                }
            }
        } catch {
            print("[ERROR] Failed to set up AVAssetReader/Writer: \(error.localizedDescription)")
            transcriptionState.lastError = "Невозможно настроить AVAssetReader/Writer: \(error.localizedDescription)"
            return false
        }
    }
    
    func processAudioSegment(_ audioURL: URL, whisperPath: String, modelPath: String, language: String, isTranslation: Bool) async -> String {
        await Task.detached(priority: .userInitiated) {
            print("[DEBUG] Processing audio segment: \(audioURL.path)")
            print("[DEBUG] Whisper path: \(whisperPath)")
            print("[DEBUG] Model path: \(modelPath)")
            print("[DEBUG] Language: \(language), isTranslation: \(isTranslation)")
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: whisperPath)
            
            var arguments = ["--file", audioURL.path, "--model", modelPath, "--language", language, "--no-timestamps", "--no-prints"]
            if isTranslation {
                arguments.append("--translate")
            }
            
            process.arguments = arguments
            
            print("[DEBUG] Whisper command: \(whisperPath) \(arguments.joined(separator: " "))")
            
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe
            
            do {
                try process.run()
                process.waitUntilExit() // Ждем завершения здесь
                
                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                
                let output = String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let error = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                
                if !error.isEmpty {
                    print("[ERROR] Whisper stderr: \(error)")
                    transcriptionState.lastError = "Ошибка при выполнении whisper: \(error)"
                }
                
                print("[DEBUG] Whisper output: '\(output)'")
                return output
            } catch {
                print("[ERROR] Failed to run whisper process: \(error.localizedDescription)")
                transcriptionState.lastError = "Невозможно выполнить процесс whisper: \(error.localizedDescription)"
                return ""
            }
        }.value
    }

    private func getWhisperPath() -> String? {
        // 1. Пробуем найти в bundle (production)
        if let bundlePath = Bundle.main.path(forResource: "whisper-cli", ofType: nil, inDirectory: nil) {
            print("[DEBUG] Found whisper-cli in bundle: \(bundlePath)")
            return bundlePath
        }
        // 2. Пробуем абсолютный путь к бинарю (development)
        let devPath = "/Users/stanislave/Documents/Projects/SubMagic/SubMagic/bin/whisper-cli"
        if FileManager.default.fileExists(atPath: devPath) {
            print("[DEBUG] Found whisper-cli in dev path: \(devPath)")
            return devPath
        }
        // 3. Fallback к старому бинарю (если новый не найден)
        let oldDevPath = "/Users/stanislave/Documents/Projects/SubMagic/SubMagic/bin/whisper"
        if FileManager.default.fileExists(atPath: oldDevPath) {
            print("[DEBUG] Found old whisper in dev path: \(oldDevPath)")
            return oldDevPath
        }
        // 4. Пробуем UserDefaults (если пользователь указал свой путь)
        if let userPath = UserDefaults.standard.string(forKey: "whisperPath"),
           FileManager.default.fileExists(atPath: userPath) {
            print("[DEBUG] Found whisper in user path: \(userPath)")
            return userPath
        }
        print("[ERROR] Whisper binary not found in any location")
        return nil
    }
}

import AppKit
import AVFoundation

extension VideoEditorView {
    private func getCacheURL(for type: String) -> URL {
        let cacheDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let cacheURL = cacheDirectory.appendingPathComponent(type).appendingPathExtension("wav")
        return cacheURL
    }
}

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
    VideoEditorView(project: ProjectModel(), transcriptionState: TranscriptionState())
}
