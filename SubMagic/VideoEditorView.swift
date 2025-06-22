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
    @State private var player: AVPlayer?
    @State private var transcriptionResult: String?
    @State private var translationResult: String?
    @State private var isTranslating = false
    @State private var selectedLanguage: String = "en"
    @State private var timeObserverToken: Any?
    @State private var processedSegments = Set<Int>()
    @State private var showFullScreen = false
    @FocusState private var isVideoFocused: Bool
    @State private var fullScreenWindowController: FullScreenWindowController? = nil
    @State private var selectedTargetLanguage: String = "en"
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
            if let player = player {
                ZStack {
                    VideoPlayer(player: player)
                        .onAppear {
                            player.play()
                        }
                    
                    // Отображение субтитров поверх видео
                    VStack {
                        Spacer()
                        if let text = transcriptionResult ?? translationResult, !text.isEmpty {
                            Text(text)
                                .font(.title)
                                .foregroundColor(.white)
                                .padding()
                                .background(Color.black.opacity(0.6))
                                .cornerRadius(10)
                                .padding(.bottom, 50)
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
                // --- КНОПКИ ПОД ВИДЕО ---
                HStack {
                    Button("Транскрибировать") {
                        Task { await transcribeWithWhisper() }
                    }
                    
                    Button("Перевести") {
                        isTranslating.toggle()
                    }
                    .popover(isPresented: $isTranslating, arrowEdge: .bottom) {
                        VStack {
                            Picker("Выберите язык", selection: $selectedLanguage) {
                                ForEach(supportedLanguages, id: \.code) { lang in
                                    Text(lang.name).tag(lang.code)
                                }
                            }
                            .pickerStyle(MenuPickerStyle())
                            
                            Button("Начать перевод") {
                                Task { await translateWithWhisper(targetLanguage: selectedLanguage) }
                                isTranslating = false
                            }
                        }
                        .padding()
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
                            self.player = AVPlayer(url: url)
                        }
                    }
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
        .onAppear {
            if player == nil, let url = project.videoURL {
                player = AVPlayer(url: url)
            }
        }
        .onChange(of: project.videoURL) { _, newURL in
            player?.pause()
            stopWhisperProcessing()
            transcriptionResult = nil
            translationResult = nil
            
            if let newURL = newURL {
                let newPlayer = AVPlayer(url: newURL)
                self.player = newPlayer
                newPlayer.play()
            } else {
                self.player = nil
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
        if let player = self.player, let token = self.timeObserverToken {
            player.removeTimeObserver(token)
            self.timeObserverToken = nil
        }
        self.processedSegments.removeAll()
    }

    func transcribeWithWhisper() async {
        await startProcessing(isTranslation: false)
    }

    func translateWithWhisper(targetLanguage: String) async {
        await startProcessing(isTranslation: true, language: targetLanguage)
    }
    
    private func startProcessing(isTranslation: Bool, language: String = "ru") async {
        guard let player = self.player, let videoURL = (player.currentItem?.asset as? AVURLAsset)?.url else {
            print("[ERROR] Player or video URL not available.")
            return
        }
        
	        stopWhisperProcessing()
        
        if isTranslation {
            self.translationResult = ""
            self.transcriptionResult = nil
        } else {
            self.transcriptionResult = ""
            self.translationResult = nil
        }

        guard let whisperPath = getWhisperPath() else { return }
        let modelPath = UserDefaults.standard.string(forKey: "whisperModelPath") ?? ""
        if modelPath.isEmpty || !FileManager.default.fileExists(atPath: modelPath) {
            return
        }

        let asset = AVURLAsset(url: videoURL)
        guard let duration = try? await asset.load(.duration) else { return }
        let durationInSeconds = CMTimeGetSeconds(duration)
        let segmentDuration: Double = 10.0

        timeObserverToken = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1.0, preferredTimescale: 600), queue: .main) { [self] _ in
            guard let currentTime = self.player?.currentTime().seconds, currentTime < durationInSeconds else { return }
            
            let segmentIndex = Int(floor(currentTime / segmentDuration))
            
            if !processedSegments.contains(segmentIndex) {
                processedSegments.insert(segmentIndex)
                
                Task {
                    await MainActor.run {
                        if isTranslation {
                            self.translationResult = "..."
                        } else {
                            self.transcriptionResult = "..."
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
                            self.translationResult = result
                        } else {
                            self.transcriptionResult = result
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
            return ""
        }

        return await processAudioSegment(tempURL, whisperPath: whisperPath, modelPath: modelPath, language: language, isTranslation: isTranslation)
    }

    func extractAudioSegment(from sourceURL: URL, to destinationURL: URL, startTime: Double, endTime: Double) async -> Bool {
        let asset = AVURLAsset(url: sourceURL)

        guard let audioTrack = (try? await asset.loadTracks(withMediaType: .audio))?.first else {
            print("[ERROR] No audio track found in the asset.")
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
                return false
            }
            
            reader.timeRange = timeRange
            writer.shouldOptimizeForNetworkUse = false

            guard reader.startReading() else {
                print("[ERROR] Failed to start asset reader: \(reader.error?.localizedDescription ?? "Unknown error")")
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
            return false
        }
    }
    
    func processAudioSegment(_ audioURL: URL, whisperPath: String, modelPath: String, language: String, isTranslation: Bool) async -> String {
        await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: whisperPath)
            
            var arguments = ["--file", audioURL.path, "--model", modelPath, "--language", language, "--no-timestamps", "--no-prints"]
            if isTranslation {
                arguments.append("--translate")
            }
            
            process.arguments = arguments
            
            let outputPipe = Pipe()
            process.standardOutput = outputPipe
            
            do {
                try process.run()
            } catch {
                print("[ERROR] Failed to run whisper process: \(error.localizedDescription)")
                return ""
            }
            
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            
            return String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }.value
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
    VideoEditorView(project: ProjectModel())
}
