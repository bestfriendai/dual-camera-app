
//
//  CameraConfiguration.swift
//  DualLensPro
//
//  Created by DualLens Pro Team on 10/24/25.
//

import Foundation
import AVFoundation

struct CameraConfiguration: Sendable {
    // MARK: - Camera State
    var frontZoomFactor: CGFloat = 0.5  // Default to 0.5x for front camera
    var backZoomFactor: CGFloat = 1.0
    var isFrontCameraActive: Bool = true
    var isBackCameraActive: Bool = true
    var showGrid: Bool = false
    var timerDuration: Int = 0

    // MARK: - Capture Mode
    var captureMode: CaptureMode = .video

    // MARK: - Aspect Ratio
    var aspectRatio: AspectRatio = .ratio16_9

    // MARK: - Orientation
    var orientationLocked: Bool = false
    var lockedOrientation: DeviceOrientation = .portrait

    // MARK: - Recording Quality
    var recordingQuality: RecordingQuality = .high

    // MARK: - Video Stabilization
    var videoStabilizationMode: VideoStabilizationMode = .auto

    // MARK: - Advanced Settings
    var whiteBalanceMode: WhiteBalanceMode = .auto
    var exposureMode: ExposureMode = .auto
    var focusMode: FocusMode = .continuousAutoFocus

    // ✅ FIX Issue #17: Query actual device zoom ranges instead of hardcoding
    var minZoom: CGFloat = 1.0
    var maxZoom: CGFloat = 5.0
    var frontMinZoom: CGFloat = 1.0
    var frontMaxZoom: CGFloat = 5.0
    var backMinZoom: CGFloat = 1.0
    var backMaxZoom: CGFloat = 5.0

    // MARK: - Zoom Presets
    var availableZoomLevels: [CGFloat] {
        [0.5, 1.0, 2.0, 5.0]
    }

    // MARK: - UserDefaults Keys
    private enum Keys {
        static let aspectRatio = "cameraConfig.aspectRatio"
        static let orientationLocked = "cameraConfig.orientationLocked"
        static let recordingQuality = "cameraConfig.recordingQuality"
        static let videoStabilization = "cameraConfig.videoStabilization"
        static let whiteBalance = "cameraConfig.whiteBalance"
        static let showGrid = "cameraConfig.showGrid"
        static let captureMode = "cameraConfig.captureMode"
    }

    // MARK: - Initialization
    init() {
        loadFromUserDefaults()
    }

    // MARK: - Zoom Control
    // ✅ FIX Issue #17: Update zoom ranges from actual device capabilities
    mutating func updateZoomRanges(
        frontCamera: AVCaptureDevice?,
        backCamera: AVCaptureDevice?
    ) {
        if let front = frontCamera {
            frontMinZoom = front.minAvailableVideoZoomFactor
            frontMaxZoom = min(front.maxAvailableVideoZoomFactor, 10.0)  // Cap at 10x for UI
            print("📸 Front camera zoom range: \(frontMinZoom)x - \(frontMaxZoom)x")
        }

        if let back = backCamera {
            backMinZoom = back.minAvailableVideoZoomFactor
            backMaxZoom = min(back.maxAvailableVideoZoomFactor, 10.0)  // Cap at 10x for UI
            print("📸 Back camera zoom range: \(backMinZoom)x - \(backMaxZoom)x")
        }

        // Set overall ranges
        minZoom = min(frontMinZoom, backMinZoom)
        maxZoom = max(frontMaxZoom, backMaxZoom)
    }

    mutating func updateFrontZoom(_ factor: CGFloat) {
        frontZoomFactor = min(max(factor, frontMinZoom), frontMaxZoom)
    }

    mutating func updateBackZoom(_ factor: CGFloat) {
        backZoomFactor = min(max(factor, backMinZoom), backMaxZoom)
    }

    mutating func setZoomToPreset(_ preset: CGFloat) {
        frontZoomFactor = preset
        backZoomFactor = preset
    }

    // MARK: - Grid Control
    mutating func toggleGrid() {
        showGrid.toggle()
        saveToUserDefaults()
    }

    // MARK: - Timer Control
    mutating func setTimer(_ duration: Int) {
        timerDuration = duration
    }

    // MARK: - Capture Mode
    mutating func setCaptureMode(_ mode: CaptureMode) {
        captureMode = mode

        // Apply mode-specific settings
        switch mode {
        case .groupPhoto:
            frontZoomFactor = 0.5
            backZoomFactor = 0.5
        case .action:
            recordingQuality = .high // Ensure high quality for action
        default:
            break
        }

        saveToUserDefaults()
    }

    // MARK: - Aspect Ratio
    mutating func setAspectRatio(_ ratio: AspectRatio) {
        aspectRatio = ratio
        saveToUserDefaults()
    }

    // MARK: - Orientation Lock
    mutating func toggleOrientationLock() {
        orientationLocked.toggle()
        saveToUserDefaults()
    }

    mutating func setOrientationLock(_ orientation: DeviceOrientation) {
        orientationLocked = true
        lockedOrientation = orientation
        saveToUserDefaults()
    }

    // MARK: - Recording Quality
    mutating func setRecordingQuality(_ quality: RecordingQuality) {
        recordingQuality = quality
        saveToUserDefaults()
    }

    // MARK: - Video Stabilization
    mutating func setVideoStabilization(_ mode: VideoStabilizationMode) {
        videoStabilizationMode = mode
        saveToUserDefaults()
    }

    // MARK: - White Balance
    mutating func setWhiteBalance(_ mode: WhiteBalanceMode) {
        whiteBalanceMode = mode
        saveToUserDefaults()
    }

    // MARK: - Persistence
    mutating func loadFromUserDefaults() {
        let defaults = UserDefaults.standard

        if let aspectRatioString = defaults.string(forKey: Keys.aspectRatio),
           let ratio = AspectRatio(rawValue: aspectRatioString) {
            aspectRatio = ratio
        }

        orientationLocked = defaults.bool(forKey: Keys.orientationLocked)

        if let qualityString = defaults.string(forKey: Keys.recordingQuality),
           let quality = RecordingQuality(rawValue: qualityString) {
            recordingQuality = quality
        }

        if let stabilizationString = defaults.string(forKey: Keys.videoStabilization),
           let stabilization = VideoStabilizationMode(rawValue: stabilizationString) {
            videoStabilizationMode = stabilization
        }

        if let whiteBalanceString = defaults.string(forKey: Keys.whiteBalance),
           let whiteBalance = WhiteBalanceMode(rawValue: whiteBalanceString) {
            whiteBalanceMode = whiteBalance
        }

        showGrid = defaults.bool(forKey: Keys.showGrid)

        if let captureModeString = defaults.string(forKey: Keys.captureMode),
           let mode = CaptureMode(rawValue: captureModeString) {
            captureMode = mode
        }
    }

    func saveToUserDefaults() {
        let defaults = UserDefaults.standard
        defaults.set(aspectRatio.rawValue, forKey: Keys.aspectRatio)
        defaults.set(orientationLocked, forKey: Keys.orientationLocked)
        defaults.set(recordingQuality.rawValue, forKey: Keys.recordingQuality)
        defaults.set(videoStabilizationMode.rawValue, forKey: Keys.videoStabilization)
        defaults.set(whiteBalanceMode.rawValue, forKey: Keys.whiteBalance)
        defaults.set(showGrid, forKey: Keys.showGrid)
        defaults.set(captureMode.rawValue, forKey: Keys.captureMode)
    }
}

// MARK: - Aspect Ratio
enum AspectRatio: String, CaseIterable, Identifiable, Sendable {
    case ratio16_9 = "16:9"
    case ratio4_3 = "4:3"
    case ratio1_1 = "1:1"

    var id: String { rawValue }

    var displayName: String { rawValue }

    var ratio: CGFloat {
        switch self {
        case .ratio16_9:
            return 16.0 / 9.0
        case .ratio4_3:
            return 4.0 / 3.0
        case .ratio1_1:
            return 1.0
        }
    }
}

// MARK: - Device Orientation
enum DeviceOrientation: String, CaseIterable, Sendable {
    case portrait
    case landscape
    case portraitUpsideDown
    case landscapeLeft
    case landscapeRight

    var displayName: String {
        switch self {
        case .portrait:
            return "Portrait"
        case .landscape:
            return "Landscape"
        case .portraitUpsideDown:
            return "Portrait Upside Down"
        case .landscapeLeft:
            return "Landscape Left"
        case .landscapeRight:
            return "Landscape Right"
        }
    }
}

// MARK: - Video Stabilization Mode
enum VideoStabilizationMode: String, CaseIterable, Identifiable, Sendable {
    case off = "Off"
    case auto = "Auto"
    case standard = "Standard"
    case cinematic = "Cinematic"

    var id: String { rawValue }

    var displayName: String { rawValue }

    var avStabilizationMode: AVCaptureVideoStabilizationMode {
        switch self {
        case .off:
            return .off
        case .auto:
            return .auto
        case .standard:
            return .standard
        case .cinematic:
            return .cinematic
        }
    }
}

// MARK: - White Balance Mode
enum WhiteBalanceMode: String, CaseIterable, Identifiable, Sendable {
    case auto = "Auto"
    case locked = "Locked"
    case sunny = "Sunny"
    case cloudy = "Cloudy"
    case incandescent = "Incandescent"
    case fluorescent = "Fluorescent"

    var id: String { rawValue }

    var displayName: String { rawValue }

    var avWhiteBalanceMode: AVCaptureDevice.WhiteBalanceMode {
        switch self {
        case .auto, .sunny, .cloudy, .incandescent, .fluorescent:
            return .continuousAutoWhiteBalance
        case .locked:
            return .locked
        }
    }

    // Color temperature for manual white balance
    var temperature: Float {
        switch self {
        case .sunny:
            return 5500
        case .cloudy:
            return 6500
        case .incandescent:
            return 3200
        case .fluorescent:
            return 4000
        default:
            return 5000
        }
    }
}

// MARK: - Exposure Mode
enum ExposureMode: String, CaseIterable, Identifiable, Sendable {
    case auto = "Auto"
    case locked = "Locked"
    case custom = "Custom"

    var id: String { rawValue }

    var displayName: String { rawValue }

    var avExposureMode: AVCaptureDevice.ExposureMode {
        switch self {
        case .auto:
            return .continuousAutoExposure
        case .locked:
            return .locked
        case .custom:
            return .custom
        }
    }
}

// MARK: - Focus Mode
enum FocusMode: String, CaseIterable, Identifiable, Sendable {
    case continuousAutoFocus = "Continuous Auto"
    case autoFocus = "Auto Focus"
    case locked = "Locked"

    var id: String { rawValue }

    var displayName: String { rawValue }

    var avFocusMode: AVCaptureDevice.FocusMode {
        switch self {
        case .continuousAutoFocus:
            return .continuousAutoFocus
        case .autoFocus:
            return .autoFocus
        case .locked:
            return .locked
        }
    }
}
