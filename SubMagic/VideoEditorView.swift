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
    @State private var showExportLanguagePicker = false
    @State private var selectedExportLanguage: String = "ru"
    @State private var showExportModelPicker = false
    @State private var selectedExportModel: String = ""
    let availableModels: [(path: String, name: String, speed: String)] = [
        ("bin/ggml-base.en.bin", "base (быстро, менее точно)", "fast"),
        ("bin/ggml-small.en.bin", "small (быстро, средняя точность)", "fast"),
        ("models/ggml-medium.bin", "medium (медленнее, точнее)", "accurate"),
        ("models/ggml-large-v3.bin", "large (самый медленный, максимальная точность)", "accurate")
    ]
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
                        .id(project.videoURL)
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
                                HStack(spacing: 16) {
                                    Button("Скрыть ошибку") {
                                        transcriptionState.lastError = nil
                                    }
                                    Button("Скопировать ошибку") {
                                        #if os(macOS)
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(error, forType: .string)
                                        #endif
                                    }
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
                    Button("Субтитры") {
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
                    if ((transcriptionState.transcriptionResult != nil && !transcriptionState.transcriptionResult!.isEmpty) || (transcriptionState.translationResult != nil && !transcriptionState.translationResult!.isEmpty)) {
                        Button("Экспорт субтитров") {
                            selectedExportLanguage = "ru"
                            showExportModelPicker = true
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
            // Статус-бар экспорта субтитров
            if let exportStatus = transcriptionState.exportStatus {
                HStack(spacing: 12) {
                    ProgressView(value: transcriptionState.exportProgress)
                        .frame(width: 120)
                    Text(String(format: "%.0f%%", transcriptionState.exportProgress * 100))
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    Text(exportStatus)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    if transcriptionState.exportCompleted {
                        Label("Субтитры готовы!", systemImage: "checkmark.seal.fill")
                            .foregroundColor(.green)
                            .font(.footnote.bold())
                    }
                }
                .padding(.bottom, 8)
                .transition(.opacity)
            }
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
        .popover(isPresented: $showExportModelPicker, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Выберите модель для экспорта")
                    .font(.headline)
                Picker("Модель", selection: $selectedExportModel) {
                    ForEach(availableModels, id: \.path) { model in
                        let exists = FileManager.default.fileExists(atPath: model.path)
                        let displayName = exists ? model.name : model.name + " (не скачана, скачайте в настройках)"
                        Text(displayName).tag(model.path)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                Text("base/small — быстро, но менее точно. medium/large — медленно, но точнее.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                HStack {
                    Spacer()
                    Button("Отмена") { showExportModelPicker = false }
                    Button("Далее") {
                        showExportModelPicker = false
                        showExportLanguagePicker = true
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!FileManager.default.fileExists(atPath: selectedExportModel))
                }
            }
            .padding()
            .frame(width: 350)
        }
        .popover(isPresented: $showExportLanguagePicker, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Выберите язык субтитров")
                    .font(.headline)
                Picker("Язык", selection: $selectedExportLanguage) {
                    ForEach(supportedLanguages, id: \.code) { lang in
                        Text(lang.name).tag(lang.code)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                HStack {
                    Spacer()
                    Button("Отмена") { showExportLanguagePicker = false }
                    Button("Экспортировать") {
                        transcriptionState.selectedLanguage = selectedExportLanguage
                        showExportLanguagePicker = false
                        exportSubtitles(selectedModelPath: selectedExportModel)
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding()
            .frame(width: 300)
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
        await transcriptionState.player?.seek(to: .zero)
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
            // Пробуем найти модель по имени
            modelPath = resolveModelPath(named: "ggml-base.en.bin") ?? ""
            if modelPath.isEmpty {
                print("[ERROR] Model file not found. Please download a model in Settings.")
                return
            }
        } else {
            print("[DEBUG] Using model from UserDefaults: \(modelPath)")
        }

        let asset = AVURLAsset(url: videoURL)
        guard let duration = try? await asset.load(.duration) else { return }
        let durationInSeconds = CMTimeGetSeconds(duration)
        let segmentDuration: Double = 10.0 // 1 минута

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
        // 2. Пробуем относительный путь bin/whisper-cli
        if let binURL = Bundle.main.resourceURL?.appendingPathComponent("bin/whisper-cli"),
           FileManager.default.fileExists(atPath: binURL.path) {
            print("[DEBUG] Found whisper-cli in bin: \(binURL.path)")
            return binURL.path
        }
        // 3. Fallback к старому бинарю (если новый не найден)
        if let oldBinURL = Bundle.main.resourceURL?.appendingPathComponent("bin/whisper"),
           FileManager.default.fileExists(atPath: oldBinURL.path) {
            print("[DEBUG] Found old whisper in bin: \(oldBinURL.path)")
            return oldBinURL.path
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

    private func exportSubtitles(selectedModelPath: String? = nil) {
        let panel = NSSavePanel()
        panel.title = "Экспорт субтитров"
        panel.allowedFileTypes = ["srt"]
        panel.nameFieldStringValue = (project.videoURL?.deletingPathExtension().lastPathComponent ?? "subtitles") + ".srt"
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.begin { response in
            guard response == .OK, let saveURL = panel.url, let videoURL = project.videoURL else { return }
            guard let whisperPath = getWhisperPath() else {
                transcriptionState.lastError = "Не найден бинарник whisper-cli"
                return
            }
            var modelPath = selectedModelPath ?? UserDefaults.standard.string(forKey: "whisperModelPath") ?? ""
            if modelPath.isEmpty || !FileManager.default.fileExists(atPath: modelPath) {
                // Пробуем найти модель по имени
                modelPath = resolveModelPath(named: "ggml-base.en.bin") ?? ""
                if modelPath.isEmpty {
                    print("[ERROR] Model file not found. Please download a model in Settings.")
                    return
                }
            }
            let language = transcriptionState.selectedLanguage
            let isTranslation = (transcriptionState.translationResult != nil && !transcriptionState.translationResult!.isEmpty)
            let baseOutput = saveURL.deletingPathExtension().path
            let segmentDuration: Double = 60 // 1 минута
            let cpuCores = ProcessInfo.processInfo.activeProcessorCount
            transcriptionState.exportStatus = "Извлечение аудиодорожки из видео..."
            Task {
                let asset = AVURLAsset(url: videoURL)
                guard let duration = try? await asset.load(.duration) else {
                    DispatchQueue.main.async {
                        transcriptionState.exportStatus = nil
                        transcriptionState.lastError = "Не удалось получить длительность видео."
                    }
                    return
                }
                let durationInSeconds = CMTimeGetSeconds(duration)
                let tempWavURL = FileManager.default.temporaryDirectory.appendingPathComponent("export_audio_\(UUID().uuidString).wav")
                let audioExtracted = await extractAudioSegment(from: videoURL, to: tempWavURL, startTime: 0, endTime: durationInSeconds)
                guard audioExtracted else {
                    DispatchQueue.main.async {
                        transcriptionState.exportStatus = nil
                        transcriptionState.lastError = "Не удалось извлечь аудиодорожку из видео."
                    }
                    return
                }
                // Разбиваем аудио на сегменты
                let segmentCount = Int(ceil(durationInSeconds / segmentDuration))
                var segmentURLs: [URL] = []
                for i in 0..<segmentCount {
                    let start = Double(i) * segmentDuration
                    let end = min(start + segmentDuration, durationInSeconds)
                    if end - start < 1.0 { continue }
                    let segURL = FileManager.default.temporaryDirectory.appendingPathComponent("segment_\(i)_\(UUID().uuidString).wav")
                    let ok = await extractAudioSegment(from: tempWavURL, to: segURL, startTime: start, endTime: end)
                    let fileSize = (try? FileManager.default.attributesOfItem(atPath: segURL.path)[.size] as? Int) ?? 0
                    print("[DEBUG] Сегмент #\(i): \(segURL.lastPathComponent), размер: \(fileSize) байт, ok=\(ok)")
                    if ok && fileSize > 1000 { segmentURLs.append(segURL) } else { try? FileManager.default.removeItem(at: segURL) }
                }
                if segmentURLs.isEmpty {
                    DispatchQueue.main.async {
                        transcriptionState.exportStatus = nil
                        transcriptionState.lastError = "Не удалось создать ни одного валидного сегмента для экспорта."
                    }
                    try? FileManager.default.removeItem(at: tempWavURL)
                    return
                }
                DispatchQueue.main.async {
                    transcriptionState.exportStatus = "Экспорт субтитров (ускоренный)..."
                }
                // Параллельно запускаем whisper-cli для каждого сегмента
                let group = DispatchGroup()
                var srtPaths: [String] = Array(repeating: "", count: segmentURLs.count)
                var completedSegments = 0
                DispatchQueue.main.async {
                    transcriptionState.exportProgress = 0
                    transcriptionState.exportCompleted = false
                }
                for (i, segURL) in segmentURLs.enumerated() {
                    group.enter()
                    DispatchQueue.main.async {
                        // Промежуточный прогресс при старте обработки сегмента
                        let startedSegments = i + 1
                        print("[PROGRESS] startedSegments = \(startedSegments), total = \(segmentURLs.count)")
                        transcriptionState.exportProgress = max(transcriptionState.exportProgress, Double(startedSegments - 1) / Double(segmentURLs.count))
                    }
                    DispatchQueue.global(qos: .userInitiated).async {
                        let segOutput = segURL.deletingPathExtension().path
                        var args = ["--file", segURL.path, "--model", modelPath, "--language", language, "-osrt", "-of", segOutput, "--threads", "\(cpuCores)"]
                        if isTranslation { args.append("--translate") }
                        let process = Process()
                        process.executableURL = URL(fileURLWithPath: whisperPath)
                        process.arguments = args
                        let errorPipe = Pipe()
                        process.standardError = errorPipe
                        do {
                            try process.run()
                            process.waitUntilExit()
                            let srtPath = segOutput + ".srt"
                            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                            let errorStr = String(data: errorData, encoding: .utf8) ?? ""
                            let exists = FileManager.default.fileExists(atPath: srtPath)
                            print("[DEBUG] Сегмент #\(i): завершён, srt exists=\(exists), error=\(errorStr)")
                            if process.terminationStatus == 0, exists {
                                srtPaths[i] = srtPath
                            }
                        } catch {
                            print("[ERROR] Whisper-cli для сегмента #\(i) не запустился: \(error.localizedDescription)")
                        }
                        DispatchQueue.main.async {
                            completedSegments += 1
                            print("[PROGRESS] completedSegments = \(completedSegments), total = \(segmentURLs.count)")
                            transcriptionState.exportProgress = Double(completedSegments) / Double(segmentURLs.count)
                        }
                        group.leave()
                    }
                }
                group.notify(queue: .main) {
                    // Объединяем все .srt
                    let finalSRT = NSMutableString()
                    var idx = 1
                    for srtPath in srtPaths where !srtPath.isEmpty {
                        if let content = try? String(contentsOfFile: srtPath, encoding: .utf8) {
                            // Перенумеровываем субтитры
                            let lines = content.components(separatedBy: "\n\n")
                            for line in lines where !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                let replaced = line.replacingOccurrences(of: "^\\d+", with: "\(idx)", options: .regularExpression)
                                finalSRT.append(replaced + "\n\n")
                                idx += 1
                            }
                        } else {
                            print("[DEBUG] Не удалось прочитать srt-файл: \(srtPath)")
                        }
                    }
                    do {
                        try finalSRT.write(toFile: saveURL.path, atomically: true, encoding: String.Encoding.utf8.rawValue)
                        transcriptionState.exportStatus = nil
                        transcriptionState.exportProgress = 1
                        transcriptionState.exportCompleted = true
                    } catch {
                        transcriptionState.exportStatus = nil
                        transcriptionState.lastError = "Ошибка сохранения итогового файла: \(error.localizedDescription)"
                        transcriptionState.exportCompleted = false
                    }
                    // Удаляем временные файлы
                    try? FileManager.default.removeItem(at: tempWavURL)
                    for url in segmentURLs { try? FileManager.default.removeItem(at: url) }
                    for srtPath in srtPaths where !srtPath.isEmpty { try? FileManager.default.removeItem(atPath: srtPath) }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        transcriptionState.exportCompleted = false
                        transcriptionState.exportProgress = 0
                    }
                }
            }
        }
    }

    // --- Добавлено: функция поиска модели по имени ---
    private func resolveModelPath(named filename: String) -> String? {
        // 1. Application Support
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let appSupportPath = appSupport?.appendingPathComponent("SubMagic/models/").appendingPathComponent(filename).path
        if let appSupportPath, FileManager.default.fileExists(atPath: appSupportPath) {
            print("[DEBUG] Using model from Application Support: \(appSupportPath)")
            return appSupportPath
        }
        // 2. Bundle
        if let bundlePath = Bundle.main.path(forResource: filename, ofType: nil) {
            print("[DEBUG] Using model from bundle: \(bundlePath)")
            return bundlePath
        }
        // 3. bin/
        if let binURL = Bundle.main.resourceURL?.appendingPathComponent("bin/").appendingPathComponent(filename),
           FileManager.default.fileExists(atPath: binURL.path) {
            print("[DEBUG] Using model from bin: \(binURL.path)")
            return binURL.path
        }
        print("[ERROR] Model file not found: \(filename)")
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
