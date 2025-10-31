//
//  VideoExporter.swift
//  DualLensPro
//
//  Created by DualLens Pro Team on 10/30/25.
//

import Foundation
import AVFoundation
import UIKit

@MainActor
class VideoExporter: ObservableObject {
    @Published var exportProgress: Double = 0.0
    @Published var isExporting: Bool = false
    @Published var exportError: Error?

    /// Export a .mov file to .mp4 format
    /// - Parameter movURL: The source .mov file URL
    /// - Returns: The exported .mp4 file URL
    /// - Throws: Export errors
    /// - Note: Uses AVAssetExportSession APIs deprecated in iOS 18. The new export(to:as:) API doesn't
    ///         provide comparable progress monitoring. Migration pending better progress API from Apple.
    @available(iOS 16.0, *)
    func exportAsMP4(movURL: URL) async throws -> URL {
        print("📦 Starting MP4 export from: \(movURL.lastPathComponent)")

        isExporting = true
        exportProgress = 0.0
        defer {
            isExporting = false
            exportProgress = 0.0
        }

        // Create asset from source file
        let asset = AVURLAsset(url: movURL)

        // Verify the asset is readable
        guard try await asset.load(.isReadable) else {
            print("❌ Source video is not readable")
            throw VideoExportError.sourceNotReadable
        }

        // Check if the asset has video tracks
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard !videoTracks.isEmpty else {
            print("❌ No video tracks found in source")
            throw VideoExportError.noVideoTracks
        }

        // Create output URL
        let outputURL = createOutputURL(from: movURL)

        // Remove existing file if it exists
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
            print("🗑️ Removed existing file at output path")
        }

        // Create export session
        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            print("❌ Failed to create export session")
            throw VideoExportError.exportSessionCreationFailed
        }

        // Configure export session
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true

        // Monitor export progress
        let progressTimer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
        let progressCancellable = progressTimer.sink { [weak self, weak exportSession] _ in
            guard let self = self, let session = exportSession else { return }
            Task { @MainActor in
                self.exportProgress = Double(session.progress)
            }
        }

        print("📦 Exporting to: \(outputURL.lastPathComponent)")

        // Start export - using deprecated API to maintain progress monitoring functionality
        // TODO: Migrate when Apple provides better progress monitoring for export(to:as:)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            Task {
                await exportSession.export()
                continuation.resume()
            }
        }

        // Clean up timer
        progressCancellable.cancel()

        // Check export status
        let status = exportSession.status
        switch status {
        case .completed:
            print("✅ Export completed successfully")
            print("📦 Output file: \(outputURL.path)")

            // Verify the output file exists
            guard FileManager.default.fileExists(atPath: outputURL.path) else {
                print("❌ Output file was not created")
                throw VideoExportError.outputFileNotCreated
            }

            // Get file size
            if let attributes = try? FileManager.default.attributesOfItem(atPath: outputURL.path),
               let fileSize = attributes[.size] as? Int64 {
                let fileSizeMB = Double(fileSize) / 1_000_000
                print("📦 Output file size: \(String(format: "%.2f MB", fileSizeMB))")
            }

            return outputURL

        case .failed:
            let error = exportSession.error ?? VideoExportError.exportFailed
            print("❌ Export failed: \(error.localizedDescription)")
            throw error

        case .cancelled:
            print("⚠️ Export was cancelled")
            throw VideoExportError.exportCancelled

        default:
            print("❌ Export ended with unexpected status: \(status.rawValue)")
            throw VideoExportError.unexpectedStatus
        }
    }

    /// Create output URL for MP4 file
    private func createOutputURL(from sourceURL: URL) -> URL {
        let documentsDirectory = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first!

        let filename = sourceURL.deletingPathExtension().lastPathComponent
        let timestamp = Int(Date().timeIntervalSince1970)
        let outputFilename = "\(filename)_exported_\(timestamp).mp4"

        return documentsDirectory.appendingPathComponent(outputFilename)
    }

    /// Cancel ongoing export
    func cancelExport() {
        // Note: Export session cancellation would need to be implemented
        // by keeping a reference to the active export session
        print("⚠️ Export cancellation requested")
    }
}

// MARK: - Video Export Errors
enum VideoExportError: LocalizedError {
    case sourceNotReadable
    case noVideoTracks
    case exportSessionCreationFailed
    case outputFileNotCreated
    case exportFailed
    case exportCancelled
    case unexpectedStatus

    var errorDescription: String? {
        switch self {
        case .sourceNotReadable:
            return "The source video file is not readable."
        case .noVideoTracks:
            return "The source video has no video tracks."
        case .exportSessionCreationFailed:
            return "Failed to create video export session."
        case .outputFileNotCreated:
            return "The exported file was not created."
        case .exportFailed:
            return "Video export failed."
        case .exportCancelled:
            return "Video export was cancelled."
        case .unexpectedStatus:
            return "Export ended with an unexpected status."
        }
    }
}
