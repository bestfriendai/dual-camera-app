
//
//  Recording.swift
//  DualCam Pro
//
//  Model for recorded videos
//

import Foundation
import SwiftData
import AVFoundation

@Model
final class Recording {
    var id: UUID
    var createdAt: Date
    var duration: TimeInterval
    var resolution: String
    var frameRate: Int
    var fileSize: Int64
    
    // File URLs (stored in app's documents directory)
    var dualViewURL: URL
    var frontOnlyURL: URL
    var backOnlyURL: URL
    
    // Metadata
    var thumbnailData: Data?
    var codec: String
    var isInPhotoLibrary: Bool
    
    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        duration: TimeInterval,
        resolution: String,
        frameRate: Int,
        fileSize: Int64,
        dualViewURL: URL,
        frontOnlyURL: URL,
        backOnlyURL: URL,
        thumbnailData: Data? = nil,
        codec: String,
        isInPhotoLibrary: Bool = false
    ) {
        self.id = id
        self.createdAt = createdAt
        self.duration = duration
        self.resolution = resolution
        self.frameRate = frameRate
        self.fileSize = fileSize
        self.dualViewURL = dualViewURL
        self.frontOnlyURL = frontOnlyURL
        self.backOnlyURL = backOnlyURL
        self.thumbnailData = thumbnailData
        self.codec = codec
        self.isInPhotoLibrary = isInPhotoLibrary
    }
    
    var formattedDuration: String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60
        
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
    
    var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSize)
    }
    
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: createdAt)
    }
}
