import SwiftUI

struct VideoEditorView: View {
    var body: some View {
        VStack {
            Text("Редактор видео и субтитров")
                .font(.title)
                .padding()
            // ...добавить waveform, предпросмотр, таймлайн...
            Spacer()
        }
    }
}

#Preview {
    VideoEditorView()
}
