import Foundation
import Combine

class WhisperBinaryManager: ObservableObject {
    enum Status {
        case idle
        case checkingDependencies
        case missingDependencies([String])
        case ready(URL)
        case failed(String)
    }
    
    @Published var status: Status = .idle
    private let fileManager = FileManager.default
    
    init() {
        // 1. Пробуем найти бинарь в Bundle
        if let bundlePath = Bundle.main.path(forResource: "whisper", ofType: nil) {
            UserDefaults.standard.set(bundlePath, forKey: "whisperPath")
        } else {
            // 2. Пробуем найти бинарь в папке bin рядом с приложением
            if let binURL = Bundle.main.resourceURL?.appendingPathComponent("bin/whisper"),
               fileManager.fileExists(atPath: binURL.path) {
                UserDefaults.standard.set(binURL.path, forKey: "whisperPath")
            }
        }
        // Проверяем и делаем бинарь исполняемым
        if let whisperPath = UserDefaults.standard.string(forKey: "whisperPath") {
            do {
                var attributes = try fileManager.attributesOfItem(atPath: whisperPath)
                if let permissions = attributes[.posixPermissions] as? NSNumber {
                    let perms = permissions.uint16Value
                    if perms & 0o111 == 0 {
                        // Нет исполняемых битов, добавим их
                        try fileManager.setAttributes([.posixPermissions: perms | 0o755], ofItemAtPath: whisperPath)
                    }
                }
            } catch {
                #if DEBUG
                print("[WhisperBinaryManager] Не удалось проверить/установить права на whisper: \(error)")
                #endif
            }
        }
    }
    
    func ensureWhisperBinary() {
        // Принудительно обновляем UserDefaults и @AppStorage на актуальный путь
        if let bundlePath = Bundle.main.path(forResource: "whisper", ofType: nil) {
            UserDefaults.standard.set(bundlePath, forKey: "whisperPath")
        } else if let binURL = Bundle.main.resourceURL?.appendingPathComponent("bin/whisper"),
                  fileManager.fileExists(atPath: binURL.path) {
            UserDefaults.standard.set(binURL.path, forKey: "whisperPath")
        }
        let whisperPath = UserDefaults.standard.string(forKey: "whisperPath") ?? ""
        #if DEBUG
        print("[WhisperBinaryManager] force-set whisperPath to: \(whisperPath)")
        #endif
        status = .checkingDependencies
        // Прямая проверка бинаря
        if fileManager.fileExists(atPath: whisperPath) && fileManager.isExecutableFile(atPath: whisperPath) {
            status = .ready(URL(fileURLWithPath: whisperPath))
        } else {
            status = .missingDependencies(["whisper binary not found or not executable"])
        }
    }
    
    private func checkWhisperBinary(completion: @escaping (URL?) -> Void) {
        let userWhisperPath = UserDefaults.standard.string(forKey: "whisperPath") ?? ""
        let url = URL(fileURLWithPath: userWhisperPath)
        let exists = fileManager.isExecutableFile(atPath: url.path)
        print("[WhisperBinaryManager] user-specified whisper: \(userWhisperPath), isExecutable: \(exists)")
        completion(exists ? url : nil)
    }
}
