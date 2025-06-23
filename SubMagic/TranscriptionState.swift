import Foundation
import AVFoundation

class TranscriptionState: ObservableObject {
    @Published var transcriptionResult: String? = nil
    @Published var translationResult: String? = nil
    @Published var isTranslating: Bool = false
    @Published var processedSegments = Set<Int>()
    @Published var selectedLanguage: String = "en"
    @Published var selectedTargetLanguage: String = "en"
    @Published var subtitlesHidden: Bool = false
    @Published var lastError: String? = nil
    @Published var exportStatus: String? = nil
    var videoURL: URL? = nil
    var player: AVPlayer? = nil
    var timeObserverToken: Any?
    
    func setVideo(url: URL?) {
        if let player = player, let token = timeObserverToken {
            print("[AVPLAYER] Removing time observer from player: \(player)")
            player.removeTimeObserver(token)
            timeObserverToken = nil
        }
        if let player = player {
            print("[AVPLAYER] Pausing player: \(player)")
            player.pause()
            print("[AVPLAYER] Replacing current item with nil for player: \(player)")
            player.replaceCurrentItem(with: nil)
            print("[AVPLAYER] Setting player to nil")
        }
        transcriptionResult = nil
        translationResult = nil
        isTranslating = false
        processedSegments.removeAll()
        videoURL = url
        if let url = url {
            print("[AVPLAYER] Creating new AVPlayer for url: \(url)")
            player = AVPlayer(url: url)
        } else {
            player = nil
        }
    }
    
    func reset() {
        transcriptionResult = nil
        translationResult = nil
        isTranslating = false
        processedSegments.removeAll()
        if let player = player, let token = timeObserverToken {
            player.removeTimeObserver(token)
            timeObserverToken = nil
        }
    }
} 