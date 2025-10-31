//
//  StorageManager.swift
//  DualLensPro
//
//  Created by DualLens Pro Team on 10/30/25.
//

import Foundation

struct StorageManager {
    enum StorageLevel {
        case critical  // < 500MB
        case low       // < 1GB
        case warning   // < 2GB
        case adequate  // >= 2GB
    }

    // MARK: - Storage Calculations

    static func availableStorageBytes() -> Int64 {
        let fileURL = URL(fileURLWithPath: NSHomeDirectory())

        // Use volumeAvailableCapacityForImportantUsageKey for more accurate reading
        guard let values = try? fileURL.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        ),
        let capacity = values.volumeAvailableCapacityForImportantUsage else {
            return 0
        }

        return Int64(capacity)
    }

    static func storageLevel() -> StorageLevel {
        let available = availableStorageBytes()

        if available < 500_000_000 {  // < 500MB
            return .critical
        } else if available < 1_000_000_000 {  // < 1GB
            return .low
        } else if available < 2_000_000_000 {  // < 2GB
            return .warning
        } else {
            return .adequate
        }
    }

    // MARK: - Recording Duration Estimation

    static func estimatedRecordingDuration(quality: RecordingQuality) -> TimeInterval {
        let available = availableStorageBytes()

        // Dual camera = 2x bitrate (front + back + combined = ~3x total)
        // Adding 50% overhead for safety
        let bytesPerSecond = (quality.bitRate * 3) / 8
        let estimatedSeconds = Double(available) / Double(bytesPerSecond)

        // Leave 500MB buffer for system
        let safeSeconds = estimatedSeconds - (500_000_000 / Double(bytesPerSecond))

        return max(0, safeSeconds)
    }

    static func estimatedFileSize(duration: TimeInterval, quality: RecordingQuality) -> Int64 {
        // Dual camera = 3x bitrate (front + back + combined)
        let bytesPerSecond = (quality.bitRate * 3) / 8
        return Int64(duration * Double(bytesPerSecond))
    }

    // MARK: - Formatted Output

    static func formattedAvailableStorage() -> String {
        let bytes = availableStorageBytes()
        return formatBytes(bytes)
    }

    static func formattedDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "\(minutes)m"
        } else {
            let seconds = Int(duration) % 60
            return "\(seconds)s"
        }
    }

    static func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: bytes)
    }

    // MARK: - Validation

    static func canStartRecording() -> Bool {
        let level = storageLevel()
        return level != .critical
    }

    static func shouldShowWarning() -> Bool {
        let level = storageLevel()
        return level == .low || level == .warning
    }

    // MARK: - User-Friendly Messages

    static func storageWarningMessage(quality: RecordingQuality) -> String? {
        let level = storageLevel()

        switch level {
        case .critical:
            return "Insufficient storage. You need at least 500MB free to start recording. Available: \(formattedAvailableStorage())"

        case .low:
            let duration = estimatedRecordingDuration(quality: quality)
            return "Low storage warning. Estimated recording time: \(formattedDuration(duration)). Available: \(formattedAvailableStorage())"

        case .warning:
            return "Storage is getting low: \(formattedAvailableStorage()) remaining"

        case .adequate:
            return nil
        }
    }
}
