//
//  SubMagicTests.swift
//  SubMagicTests
//
//  Created by Stanislav E on 21.06.2025.
//

import Testing
@testable import SubMagic
import XCTest
import SwiftUI
import ViewInspector

struct SubMagicTests {

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
    }

}

final class SubMagicCoreTests: XCTestCase {
    func testTranscriptionStateReset() {
        let state = TranscriptionState()
        state.transcriptionResult = "abc"
        state.translationResult = "def"
        state.isTranslating = true
        state.processedSegments = [1,2,3]
        state.subtitlesHidden = true
        state.reset()
        XCTAssertNil(state.transcriptionResult)
        XCTAssertNil(state.translationResult)
        XCTAssertFalse(state.isTranslating)
        XCTAssertTrue(state.processedSegments.isEmpty)
        XCTAssertFalse(state.subtitlesHidden)
    }
    
    func testTranscriptionStateSetVideo() {
        let state = TranscriptionState()
        let url = URL(fileURLWithPath: "/dev/null/video.mp4")
        state.setVideo(url: url)
        XCTAssertEqual(state.videoURL, url)
        XCTAssertNotNil(state.player)
        state.setVideo(url: nil)
        XCTAssertNil(state.videoURL)
        XCTAssertNil(state.player)
    }
    
    func testSubtitlesHiddenFlag() {
        let state = TranscriptionState()
        state.transcriptionResult = "text"
        state.subtitlesHidden = true
        XCTAssertTrue(state.subtitlesHidden)
        state.subtitlesHidden = false
        XCTAssertFalse(state.subtitlesHidden)
    }
    
    func testProjectModelOpenAndClose() {
        let model = ProjectModel()
        let url = URL(fileURLWithPath: "/dev/null/video.mp4")
        model.videoURL = url
        XCTAssertEqual(model.videoURL, url)
        model.closeProject()
        XCTAssertNil(model.videoURL)
    }
    
    func testWhisperBinaryManagerStatus() {
        let manager = WhisperBinaryManager()
        manager.ensureWhisperBinary()
        switch manager.status {
        case .ready, .missingDependencies:
            XCTAssertTrue(true)
        default:
            XCTFail("Unexpected status")
        }
    }
    
    func testModelManagerSetModelPath() {
        let manager = WhisperModelManager()
        let path = "/tmp/test-model.bin"
        manager.setModelPath(path)
        XCTAssertEqual(manager.modelPath, path)
        XCTAssertEqual(UserDefaults.standard.string(forKey: "whisperModelPath"), path)
    }
}

extension VideoEditorView: Inspectable {}

final class SubMagicUITests: XCTestCase {
    func testSubtitlesAppearAndHide() throws {
        let project = ProjectModel()
        let state = TranscriptionState()
        state.transcriptionResult = "Test subtitle"
        let view = VideoEditorView(project: project, transcriptionState: state)
        let exp = try view.inspect().find(text: "Test subtitle")
        XCTAssertNotNil(exp)
        state.subtitlesHidden = true
        XCTAssertThrowsError(try view.inspect().find(text: "Test subtitle"))
    }
    func testTranscribeButtonShowsSubtitles() throws {
        let project = ProjectModel()
        let state = TranscriptionState()
        let view = VideoEditorView(project: project, transcriptionState: state)
        // Симулируем запуск транскрипции
        state.transcriptionResult = "Some text"
        XCTAssertNoThrow(try view.inspect().find(text: "Some text"))
    }
    func testHideButtonHidesSubtitles() throws {
        let project = ProjectModel()
        let state = TranscriptionState()
        state.transcriptionResult = "Show me"
        let view = VideoEditorView(project: project, transcriptionState: state)
        // Симулируем нажатие кнопки скрытия
        state.subtitlesHidden = true
        XCTAssertThrowsError(try view.inspect().find(text: "Show me"))
    }
    func testVideoChangeResetsState() throws {
        let state = TranscriptionState()
        let project = ProjectModel()
        let view = VideoEditorView(project: project, transcriptionState: state)
        state.transcriptionResult = "Old"
        state.setVideo(url: URL(fileURLWithPath: "/dev/null/1.mp4"))
        XCTAssertNil(state.transcriptionResult)
        XCTAssertNil(state.translationResult)
    }
}
