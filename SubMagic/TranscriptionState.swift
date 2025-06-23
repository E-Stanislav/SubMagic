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
        videoURL = url
        if let url = url {
            player = AVPlayer(url: url)
        } else {
            player = nil
        }
        reset()
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