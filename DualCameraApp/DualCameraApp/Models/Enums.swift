
//
//  Enums.swift
//  DualCam Pro
//
//  Core enumerations for app configuration
//

import Foundation
import AVFoundation

// MARK: - Video Configuration

enum VideoResolution: String, CaseIterable, Codable {
    case hd720p = "720p"
    case fullHD = "1080p"
    case uhd4K = "4K"
    
    var dimensions: (width: Int, height: Int) {
        switch self {
        case .hd720p: return (1280, 720)
        case .fullHD: return (1920, 1080)
        case .uhd4K: return (3840, 2160)
        }
    }
    
    var displayName: String {
        rawValue
    }
}

enum FrameRate: Int, CaseIterable, Codable {
    case fps24 = 24
    case fps30 = 30
    case fps60 = 60
    
    var displayName: String {
        "\(rawValue) fps"
    }
}

enum VideoCodec: String, CaseIterable, Codable {
    case h264 = "H.264"
    case hevc = "H.265 (HEVC)"
    case proRes = "ProRes"
    
    var avCodec: AVVideoCodecType {
        switch self {
        case .h264: return .h264
        case .hevc: return .hevc
        case .proRes: return .proRes422
        }
    }
    
    var isAvailable: Bool {
        switch self {
        case .proRes:
            // ProRes only on Pro models
            return ProcessInfo.processInfo.processorCount >= 6
        default:
            return true
        }
    }
}

enum BitRate: String, CaseIterable, Codable {
    case auto = "Auto"
    case low = "Low"
    case medium = "Medium"
    case high = "High"
    case maximum = "Maximum"
    
    func value(for resolution: VideoResolution) -> Int {
        switch self {
        case .auto:
            return 0 // Let system decide
        case .low:
            return resolution == .uhd4K ? 20_000_000 : 10_000_000
        case .medium:
            return resolution == .uhd4K ? 35_000_000 : 15_000_000
        case .high:
            return resolution == .uhd4K ? 50_000_000 : 20_000_000
        case .maximum:
            return resolution == .uhd4K ? 100_000_000 : 40_000_000
        }
    }
}

// MARK: - Camera Configuration

enum CameraPosition: String, Codable {
    case front
    case back
    
    var avPosition: AVCaptureDevice.Position {
        switch self {
        case .front: return .front
        case .back: return .back
        }
    }
}

enum FocusMode: String, CaseIterable, Codable {
    case auto = "Auto"
    case continuousAuto = "Continuous"
    case manual = "Manual"
    case locked = "Locked"
    
    var avMode: AVCaptureDevice.FocusMode {
        switch self {
        case .auto: return .autoFocus
        case .continuousAuto: return .continuousAutoFocus
        case .manual, .locked: return .locked
        }
    }
}

enum ExposureMode: String, CaseIterable, Codable {
    case auto = "Auto"
    case continuousAuto = "Continuous"
    case manual = "Manual"
    case locked = "Locked"
    
    var avMode: AVCaptureDevice.ExposureMode {
        switch self {
        case .auto: return .autoExpose
        case .continuousAuto: return .continuousAutoExposure
        case .manual: return .custom
        case .locked: return .locked
        }
    }
}

enum WhiteBalanceMode: String, CaseIterable, Codable {
    case auto = "Auto"
    case continuousAuto = "Continuous"
    case locked = "Locked"
    case daylight = "Daylight"
    case cloudy = "Cloudy"
    case tungsten = "Tungsten"
    case fluorescent = "Fluorescent"
    
    var avMode: AVCaptureDevice.WhiteBalanceMode {
        switch self {
        case .auto, .daylight, .cloudy, .tungsten, .fluorescent:
            return .continuousAutoWhiteBalance
        case .continuousAuto:
            return .continuousAutoWhiteBalance
        case .locked:
            return .locked
        }
    }
    
    var temperature: Float? {
        switch self {
        case .daylight: return 5500
        case .cloudy: return 6500
        case .tungsten: return 3200
        case .fluorescent: return 4000
        default: return nil
        }
    }
}

enum StabilizationMode: String, CaseIterable, Codable {
    case off = "Off"
    case standard = "Standard"
    case cinematic = "Cinematic"
    case cinematicExtended = "Cinematic Extended"
    
    var avMode: AVCaptureVideoStabilizationMode {
        switch self {
        case .off: return .off
        case .standard: return .standard
        case .cinematic: return .cinematic
        case .cinematicExtended: return .cinematicExtended
        }
    }
}

enum FlashMode: String, CaseIterable, Codable {
    case off = "Off"
    case on = "On"
    case auto = "Auto"
    
    var torchMode: AVCaptureDevice.TorchMode {
        switch self {
        case .off: return .off
        case .on: return .on
        case .auto: return .auto
        }
    }
}

enum GridType: String, CaseIterable, Codable {
    case none = "None"
    case ruleOfThirds = "Rule of Thirds"
    case center = "Center"
    case golden = "Golden Ratio"
}

enum TimerDuration: Int, CaseIterable, Codable {
    case none = 0
    case three = 3
    case ten = 10
    
    var displayName: String {
        switch self {
        case .none: return "Off"
        case .three: return "3s"
        case .ten: return "10s"
        }
    }
}

enum VideoFilter: String, CaseIterable, Codable {
    case none = "None"
    case vivid = "Vivid"
    case dramatic = "Dramatic"
    case mono = "Mono"
    case silvertone = "Silvertone"
    case noir = "Noir"
    
    var ciFilterName: String? {
        switch self {
        case .none: return nil
        case .vivid: return "CIColorControls"
        case .dramatic: return "CIPhotoEffectProcess"
        case .mono: return "CIPhotoEffectMono"
        case .silvertone: return "CIPhotoEffectTonal"
        case .noir: return "CIPhotoEffectNoir"
        }
    }
}

// MARK: - Recording State

enum RecordingState: Equatable {
    case idle
    case starting
    case recording
    case paused
    case stopping
    case error(String)
}

enum OutputType: String, CaseIterable {
    case dualView = "Dual View"
    case frontOnly = "Front Only"
    case backOnly = "Back Only"
}

// MARK: - Layout

enum CameraLayout: String, CaseIterable, Codable {
    case frontOnTop = "Front on Top"
    case backOnTop = "Back on Top"
    
    var splitRatio: CGFloat {
        return 0.5 // 50/50 split
    }
}

// MARK: - Error Types

enum CameraError: LocalizedError {
    case multiCamNotSupported
    case cameraUnavailable
    case permissionDenied
    case configurationFailed
    case hardwareCostExceeded
    case deviceNotFound
    case sessionSetupFailed
    
    var errorDescription: String? {
        switch self {
        case .multiCamNotSupported:
            return "Multi-camera recording is not supported on this device. iPhone XS/11 or later required."
        case .cameraUnavailable:
            return "Camera is currently unavailable. Please close other camera apps."
        case .permissionDenied:
            return "Camera access denied. Please enable in Settings."
        case .configurationFailed:
            return "Failed to configure camera. Please try again."
        case .hardwareCostExceeded:
            return "Device resources exceeded. Try lowering video quality."
        case .deviceNotFound:
            return "Camera device not found."
        case .sessionSetupFailed:
            return "Failed to setup camera session."
        }
    }
}

enum RecordingError: LocalizedError {
    case insufficientStorage
    case writerFailed(Error)
    case audioSyncLost
    case frameDrop
    case thermalThrottling
    
    var errorDescription: String? {
        switch self {
        case .insufficientStorage:
            return "Insufficient storage space. Recording stopped."
        case .writerFailed(let error):
            return "Recording failed: \(error.localizedDescription)"
        case .audioSyncLost:
            return "Audio synchronization lost. Recording may have issues."
        case .frameDrop:
            return "Frames were dropped during recording."
        case .thermalThrottling:
            return "Device overheating. Recording paused to cool down."
        }
    }
}
