import SwiftUI
import AVKit

struct VideoEditorView: View {
    @ObservedObject var playerHolder: PlayerHolder
    @State private var showFullScreen = false
    @FocusState private var isVideoFocused: Bool
    @State private var fullScreenWindowController: FullScreenWindowController? = nil
    
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
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Button(action: transcribeWithWhisper) {
                                Label("Транскрибировать (Whisper)", systemImage: "waveform")
                            }
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.15)))
                            .padding()
                        }
                    }
                }
                .contextMenu {
                    Button("Открыть в полном экране") {
                        openFullScreen(player: player)
                    }
                    .keyboardShortcut("f", modifiers: .command)
                }
                .background(KeyboardShortcutCatcher(openFullScreen: { openFullScreen(player: player) }))
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
        // 1. Извлечь аудио во временный файл
        let audioURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        extractAudio(from: videoURL, to: audioURL) { success in
            if success {
                // 2. Запустить whisper.cpp через subprocess
                runWhisperTranscription(audioURL: audioURL)
            } else {
                showTranscriptionResult("Ошибка извлечения аудио")
            }
        }
    }
    
    func extractAudio(from videoURL: URL, to audioURL: URL, completion: @escaping (Bool) -> Void) {
        let asset = AVAsset(url: videoURL)
        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            completion(false)
            return
        }
        exporter.outputURL = audioURL
        exporter.outputFileType = .wav
        exporter.timeRange = CMTimeRange(start: .zero, duration: asset.duration)
        exporter.exportAsynchronously {
            DispatchQueue.main.async {
                completion(exporter.status == .completed)
            }
        }
    }
    
    func runWhisperTranscription(audioURL: URL) {
        // Получаем путь к whisper.cpp и модели из UserDefaults/менеджера
        let whisperPath = "/usr/local/bin/whisper" // Можно вынести в настройки
        let modelPath = UserDefaults.standard.string(forKey: "whisperModelPath") ?? "/usr/local/models/ggml-base.bin"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: whisperPath)
        process.arguments = [audioURL.path, "--model", modelPath, "--language", "ru"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            showTranscriptionResult("Ошибка запуска whisper.cpp: \(error.localizedDescription)")
            return
        }
        DispatchQueue.global().async {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            DispatchQueue.main.async {
                self.showTranscriptionResult(output)
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
