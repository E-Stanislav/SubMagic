import SwiftUI
import XCTest
@testable import SubMagic

final class SmokeTests: XCTestCase {
    func testAppLaunches() {
        // Проверяем, что ContentView можно создать
        let showFileImporter = Binding.constant(false)
        let view = ContentView(showFileImporter: showFileImporter)
        XCTAssertNotNil(view)
    }
    
    func testVideoEditorViewWithNilURL() {
        // Проверяем, что VideoEditorView не падает без видео
        let view = VideoEditorView(videoURL: nil)
        XCTAssertNotNil(view)
    }
    
    func testVideoEditorViewWithDummyURL() {
        // Проверяем, что VideoEditorView не падает с несуществующим URL
        let dummyURL = URL(fileURLWithPath: "/dev/null/video.mp4")
        let view = VideoEditorView(videoURL: dummyURL)
        XCTAssertNotNil(view)
    }
    
    func testCloseMediaNotification() {
        // Smoke: отправка уведомления не вызывает крэш
        NotificationCenter.default.post(name: .closeMedia, object: nil)
        XCTAssertTrue(true)
    }
}
