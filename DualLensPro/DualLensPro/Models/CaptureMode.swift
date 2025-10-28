//
//  CaptureMode.swift
//  DualLensPro
//
//  Created by DualLens Pro Team on 10/24/25.
//

import Foundation
import AVFoundation

enum CaptureMode: String, CaseIterable, Identifiable, Sendable {
    case groupPhoto = "GROUP PHOTO"
    case photo = "PHOTO"
    case video = "VIDEO"
    case action = "ACTION"
    case switchScreen = "SWITCH SCREEN"

    var id: String { rawValue }

    var displayName: String {
        rawValue
    }

    var description: String {
        switch self {
        case .groupPhoto:
            return "Wide angle photo optimized for group shots"
        case .photo:
            return "Capture photos from both cameras simultaneously"
        case .video:
            return "Record dual camera video (default mode)"
        case .action:
            return "High frame rate recording for action shots"
        case .switchScreen:
            return "Switch which camera appears on top/bottom"
        }
    }

    var systemIconName: String {
        switch self {
        case .groupPhoto:
            return "person.3.fill"
        case .photo:
            return "camera.fill"
        case .video:
            return "video.fill"
        case .action:
            return "bolt.circle.fill"
        case .switchScreen:
            return "arrow.up.arrow.down.circle.fill"
        }
    }

    var requiresPremium: Bool {
        return false
    }

    var isRecordingMode: Bool {
        switch self {
        case .video, .action:
            return true
        case .photo, .groupPhoto, .switchScreen:
            return false
        }
    }

    var isPhotoMode: Bool {
        switch self {
        case .photo, .groupPhoto:
            return true
        case .video, .action, .switchScreen:
            return false
        }
    }

    // Frame rate for video modes (preferred rate)
    var frameRate: Int {
        switch self {
        case .action:
            return 120 // High frame rate for action
        case .video:
            return 60
        default:
            return 30
        }
    }

    // ✅ FIX Issue #18: Device-specific frame rate with fallback
    func actualFrameRate(for device: AVCaptureDevice) -> Int {
        let preferred = frameRate
        let supported = device.activeFormat.videoSupportedFrameRateRanges

        // Check if preferred rate is supported
        for range in supported {
            if range.minFrameRate <= Double(preferred) &&
               range.maxFrameRate >= Double(preferred) {
                return preferred
            }
        }

        // Find highest supported rate as fallback
        let maxSupported = supported.map { Int($0.maxFrameRate) }.max() ?? 30

        print("⚠️ Device doesn't support \(preferred)fps, falling back to \(maxSupported)fps")

        return maxSupported
    }

    // Check if mode is fully supported on device
    func isSupported(on device: AVCaptureDevice) -> Bool {
        let actual = actualFrameRate(for: device)
        return actual == frameRate
    }

    // User-facing description of support
    func supportDescription(for device: AVCaptureDevice) -> String {
        if isSupported(on: device) {
            return "\(displayName) (\(frameRate)fps)"
        } else {
            let actual = actualFrameRate(for: device)
            return "\(displayName) (\(actual)fps - device limited)"
        }
    }

    // Recommended zoom for mode
    var recommendedZoom: CGFloat {
        switch self {
        case .groupPhoto:
            return 0.5 // Wide angle for groups
        case .photo, .video:
            return 1.0
        case .action:
            return 1.0
        case .switchScreen:
            return 1.0
        }
    }
}
