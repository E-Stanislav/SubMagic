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
        // Устанавливаем путь к whisper всегда на актуальный
        let defaultPath = "/Users/stanislave/Documents/Projects/SubMagic/SubMagic/bin/whisper"
        UserDefaults.standard.set(defaultPath, forKey: "whisperPath")
        // Проверяем и делаем бинарь исполняемым
        do {
            var attributes = try fileManager.attributesOfItem(atPath: defaultPath)
            if let permissions = attributes[.posixPermissions] as? NSNumber {
                let perms = permissions.uint16Value
                if perms & 0o111 == 0 {
                    // Нет исполняемых битов, добавим их
                    try fileManager.setAttributes([.posixPermissions: perms | 0o755], ofItemAtPath: defaultPath)
                }
            }
        } catch {
            #if DEBUG
            print("[WhisperBinaryManager] Не удалось проверить/установить права на whisper: \(error)")
            #endif
        }
    }
    
    func ensureWhisperBinary() {
        // Принудительно обновляем UserDefaults и @AppStorage на актуальный путь
        let correctPath = "/Users/stanislave/Documents/Projects/SubMagic/SubMagic/bin/whisper"
        UserDefaults.standard.set(correctPath, forKey: "whisperPath")
        #if DEBUG
        print("[WhisperBinaryManager] force-set whisperPath to: \(correctPath)")
        #endif
        status = .checkingDependencies
        // Прямая проверка бинаря
        if fileManager.fileExists(atPath: correctPath) && fileManager.isExecutableFile(atPath: correctPath) {
            status = .ready(URL(fileURLWithPath: correctPath))
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
