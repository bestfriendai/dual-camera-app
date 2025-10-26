
//
//  GalleryViewModel.swift
//  DualCam Pro
//
//  ViewModel for gallery view
//

import SwiftUI
import AVFoundation
import Photos
import Combine

@MainActor
final class GalleryViewModel: ObservableObject {
    @Published var recordings: [Recording] = []
    @Published var isLoading = false
    @Published var selectedRecording: Recording?
    @Published var errorMessage: String?

    nonisolated(unsafe) private let photoLibraryService = PhotoLibraryService.shared
    
    func loadRecordings() async {
        isLoading = true
        
        // Load recordings from Documents directory
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        
        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(
                at: documentsPath,
                includingPropertiesForKeys: [.creationDateKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            )
            
            // Filter for MOV files with our naming pattern
            let dualViewURLs = fileURLs.filter { $0.lastPathComponent.hasPrefix("dualview_") }
            
            var loadedRecordings: [Recording] = []
            
            for dualViewURL in dualViewURLs {
                let timestamp = dualViewURL.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "dualview_", with: "")
                let frontURL = documentsPath.appendingPathComponent("front_\(timestamp).mov")
                let backURL = documentsPath.appendingPathComponent("back_\(timestamp).mov")
                
                // Check if all three files exist
                guard FileManager.default.fileExists(atPath: frontURL.path),
                      FileManager.default.fileExists(atPath: backURL.path) else {
                    continue
                }
                
                // Get video info
                let asset = AVAsset(url: dualViewURL)
                let duration = try await asset.load(.duration)
                let durationSeconds = CMTimeGetSeconds(duration)
                
                // Get file size
                let attributes = try FileManager.default.attributesOfItem(atPath: dualViewURL.path)
                let fileSize = attributes[.size] as? Int64 ?? 0
                
                // Get creation date
                let creationDate = (attributes[.creationDate] as? Date) ?? Date()
                
                // Get resolution
                if let track = try await asset.loadTracks(withMediaType: .video).first {
                    let size = try await track.load(.naturalSize)
                    let resolution = "\(Int(size.width))x\(Int(size.height))"
                    
                    // Get frame rate
                    let frameRate = try await track.load(.nominalFrameRate)
                    
                    // Generate thumbnail
                    let thumbnail = await photoLibraryService.generateThumbnail(for: dualViewURL)
                    
                    let recording = Recording(
                        createdAt: creationDate,
                        duration: durationSeconds,
                        resolution: resolution,
                        frameRate: Int(frameRate),
                        fileSize: fileSize * 3, // Approximate total size
                        dualViewURL: dualViewURL,
                        frontOnlyURL: frontURL,
                        backOnlyURL: backURL,
                        thumbnailData: thumbnail?.pngData(),
                        codec: "H.265"
                    )
                    
                    loadedRecordings.append(recording)
                }
            }
            
            // Sort by date (newest first)
            loadedRecordings.sort { $0.createdAt > $1.createdAt }
            
            self.recordings = loadedRecordings
            
        } catch {
            errorMessage = "Failed to load recordings: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    func deleteRecording(_ recording: Recording) async {
        do {
            // Delete files
            try FileManager.default.removeItem(at: recording.dualViewURL)
            try FileManager.default.removeItem(at: recording.frontOnlyURL)
            try FileManager.default.removeItem(at: recording.backOnlyURL)
            
            // Remove from array
            if let index = recordings.firstIndex(where: { $0.id == recording.id }) {
                recordings.remove(at: index)
            }
            
        } catch {
            errorMessage = "Failed to delete recording: \(error.localizedDescription)"
        }
    }
    
    func shareRecording(_ recording: Recording, output: OutputType) -> URL {
        switch output {
        case .dualView:
            return recording.dualViewURL
        case .frontOnly:
            return recording.frontOnlyURL
        case .backOnly:
            return recording.backOnlyURL
        }
    }
}
