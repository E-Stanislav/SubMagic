import SwiftUI
import AVKit

struct VideoEditorView: View {
    var videoURL: URL?
    @State private var showFullScreen = false
    @FocusState private var isVideoFocused: Bool
    @State private var fullScreenWindowController: FullScreenWindowController? = nil
    
    var body: some View {
        VStack {
            Text("Редактор видео и субтитров")
                .font(.title)
                .padding()
            if let url = videoURL {
                VideoPlayer(player: AVPlayer(url: url))
                    .aspectRatio(16/9, contentMode: .fit)
                    .frame(minHeight: 300)
                    .padding()
                    .contextMenu {
                        Button("Открыть в полном экране") {
                            openFullScreen(url: url)
                        }
                        .keyboardShortcut("f", modifiers: .command)
                    }
                    .background(KeyboardShortcutCatcher(openFullScreen: { openFullScreen(url: url) }))
                    .focusable()
                    .focused($isVideoFocused)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            isVideoFocused = true
                        }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                        isVideoFocused = true
                    }
            } else {
                Text("Нет выбранного видео")
                    .foregroundColor(.secondary)
                    .padding()
            }
            Spacer()
        }
        .onReceive(NotificationCenter.default.publisher(for: .closeMedia)) { _ in
            // Закрываем полноэкранное окно, если оно открыто
            fullScreenWindowController?.close()
            fullScreenWindowController = nil
        }
    }
    
    private func openFullScreen(url: URL) {
        guard videoURL != nil else { return }
        // Закрываем предыдущее окно, если оно есть
        fullScreenWindowController?.close()
        let controller = FullScreenWindowController(url: url) {
            // callback при закрытии окна
            self.fullScreenWindowController = nil
        }
        fullScreenWindowController = controller
        controller.showWindow(nil)
        controller.window?.toggleFullScreen(nil)
    }
}

// --- ВНИЗУ ФАЙЛА ---

import AppKit
class FullScreenWindowController: NSWindowController {
    private var onClose: (() -> Void)?
    init(url: URL, onClose: (() -> Void)? = nil) {
        let hosting = NSHostingController(rootView: FullScreenVideoPlayerStandalone(url: url, onClose: onClose))
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
    let url: URL
    var onClose: (() -> Void)?
    @State private var player: AVPlayer? = nil
    @Environment(\.presentationMode) private var presentationMode
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            if let player = player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
                    .onAppear { player.play() }
            }
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
        .onAppear {
            player = AVPlayer(url: url)
        }
        .onDisappear {
            player?.pause()
            player = nil
            onClose?() // Гарантированно сбрасываем контроллер при любом закрытии
        }
        .background(FullScreenKeyboardCatcher(onClose: {
            NSApp.keyWindow?.close()
            // onClose вызывается в onDisappear
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
    VideoEditorView(videoURL: nil)
}
