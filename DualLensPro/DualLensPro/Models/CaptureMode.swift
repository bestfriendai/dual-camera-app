//
//  CaptureMode.swift
//  DualLensPro
//
//  Created by DualLens Pro Team on 10/24/25.
//

import Foundation

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
        switch self {
        case .groupPhoto, .photo, .video:
            return false
        case .action, .switchScreen:
            return true
        }
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

    // Frame rate for video modes
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
