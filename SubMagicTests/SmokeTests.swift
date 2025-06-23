import SwiftUI
import XCTest
@testable import SubMagic

final class SmokeTests: XCTestCase {
    func testAppLaunches() {
        // Проверяем, что ContentView можно создать
        let view = ContentView()
        XCTAssertNotNil(view)
    }
    
    func testVideoEditorViewInit() {
        // Проверяем, что VideoEditorView не падает при инициализации с пустыми моделями
        let project = ProjectModel()
        let state = TranscriptionState()
        let view = VideoEditorView(project: project, transcriptionState: state)
        XCTAssertNotNil(view)
    }
    
    func testCloseMediaNotification() {
        // Smoke: отправка уведомления не вызывает крэш
        NotificationCenter.default.post(name: .closeMedia, object: nil)
        XCTAssertTrue(true)
    }
}
