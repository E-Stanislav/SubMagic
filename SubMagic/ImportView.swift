//
//  ImportView.swift
//  SubMagic
//
//  Created by Stanislav Seryi on 25.06.2024.
//

import SwiftUI

struct ImportView: View {
    @ObservedObject var project: ProjectModel
    @StateObject private var transcriptionState = TranscriptionState()
    
    var body: some View {
        Group {
            if project.videoURL != nil {
                VideoEditorView(project: project, transcriptionState: transcriptionState)
            } else {
                VStack(spacing: 20) {
                    Text("SubMagic")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("Перетащите видеофайл сюда или нажмите, чтобы выбрать")
                        .font(.title2)
                        .foregroundColor(.secondary)
                        .padding()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [10]))
                                .foregroundColor(.gray)
                        )
                        .onTapGesture {
                            project.openVideo()
                        }
                }
                .padding(40)
            }
        }
        .onChange(of: project.videoURL) { _, newURL in
            transcriptionState.setVideo(url: newURL)
        }
        .onDrop(of: ["public.file-url"], isTargeted: nil) { providers in
            project.handleDrop(providers: providers)
        }
        .frame(minWidth: 600, minHeight: 400)
    }
}

#Preview {
    ImportView(project: ProjectModel())
}

