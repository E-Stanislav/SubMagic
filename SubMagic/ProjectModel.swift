//
//  ProjectModel.swift
//  SubMagic
//
//  Created by Stanislav Seryi on 25.06.2024.
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers

class ProjectModel: ObservableObject {
    @Published var videoURL: URL? {
        didSet {
            if let previousURL = oldValue, securityScoped {
                previousURL.stopAccessingSecurityScopedResource()
            }
        }
    }
    
    private var securityScoped = false

    deinit {
        if let url = videoURL, securityScoped {
            url.stopAccessingSecurityScopedResource()
        }
    }

    func openVideo() {
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [UTType.movie, UTType.audio]
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        
        if openPanel.runModal() == .OK {
            if let url = openPanel.url {
                if url.startAccessingSecurityScopedResource() {
                    self.securityScoped = true
                    self.videoURL = url
                } else {
                    print("[ERROR] Failed to get security access to \(url.path)")
                }
            }
        }
    }

    func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { (item, error) in
            guard let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) else {
                return
            }
            
            DispatchQueue.main.async {
                if url.startAccessingSecurityScopedResource() {
                    self.securityScoped = true
                    self.videoURL = url
                } else {
                    self.videoURL = url
                }
            }
        }
        return true
    }

    func closeProject() {
        if let url = videoURL, securityScoped {
            url.stopAccessingSecurityScopedResource()
        }
        videoURL = nil
        securityScoped = false
    }
}
