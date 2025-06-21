import Foundation

struct ProjectModel: Identifiable, Codable {
    let id: UUID
    var name: String
    var videoPath: String?
    var subtitlePath: String?
    var modelId: String?
    var settings: [String: String]?
    // ...можно расширять по мере необходимости...
    
    init(name: String) {
        self.id = UUID()
        self.name = name
    }
}
