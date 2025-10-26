//
//  SettingsViewModel.swift
//  DualLensPro
//
//  Created by DualLens Pro Team on 10/24/25.
//

import Foundation
import SwiftUI

@MainActor
class SettingsViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var configuration: CameraConfiguration
    @Published var showResetConfirmation = false

    // MARK: - UserDefaults Keys
    private enum Keys {
        static let hapticFeedback = "settings.hapticFeedback"
        static let soundEffects = "settings.soundEffects"
        static let autoSaveToLibrary = "settings.autoSaveToLibrary"
        static let showWatermark = "settings.showWatermark"
        static let defaultCaptureMode = "settings.defaultCaptureMode"
    }

    // MARK: - App Settings
    @Published var hapticFeedbackEnabled: Bool {
        didSet {
            UserDefaults.standard.set(hapticFeedbackEnabled, forKey: Keys.hapticFeedback)
        }
    }

    @Published var soundEffectsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(soundEffectsEnabled, forKey: Keys.soundEffects)
        }
    }

    @Published var autoSaveToLibrary: Bool {
        didSet {
            UserDefaults.standard.set(autoSaveToLibrary, forKey: Keys.autoSaveToLibrary)
        }
    }

    @Published var showWatermark: Bool {
        didSet {
            UserDefaults.standard.set(showWatermark, forKey: Keys.showWatermark)
        }
    }

    @Published var defaultCaptureMode: CaptureMode {
        didSet {
            UserDefaults.standard.set(defaultCaptureMode.rawValue, forKey: Keys.defaultCaptureMode)
        }
    }

    // MARK: - Initialization
    init(configuration: CameraConfiguration = CameraConfiguration()) {
        self.configuration = configuration

        // Load app settings
        self.hapticFeedbackEnabled = UserDefaults.standard.bool(forKey: Keys.hapticFeedback)
        self.soundEffectsEnabled = UserDefaults.standard.bool(forKey: Keys.soundEffects)
        self.autoSaveToLibrary = UserDefaults.standard.bool(forKey: Keys.autoSaveToLibrary)
        self.showWatermark = UserDefaults.standard.bool(forKey: Keys.showWatermark)

        if let modeString = UserDefaults.standard.string(forKey: Keys.defaultCaptureMode),
           let mode = CaptureMode(rawValue: modeString) {
            self.defaultCaptureMode = mode
        } else {
            self.defaultCaptureMode = .video
        }

        // Set defaults if first launch
        if !UserDefaults.standard.bool(forKey: "hasLaunchedBefore") {
            setDefaults()
        }
    }

    // MARK: - Aspect Ratio
    func setAspectRatio(_ ratio: AspectRatio) {
        configuration.setAspectRatio(ratio)
    }

    var currentAspectRatio: AspectRatio {
        configuration.aspectRatio
    }

    // MARK: - Video Stabilization
    func setVideoStabilization(_ mode: VideoStabilizationMode) {
        configuration.setVideoStabilization(mode)
    }

    var currentStabilizationMode: VideoStabilizationMode {
        configuration.videoStabilizationMode
    }

    // MARK: - Recording Quality
    func setRecordingQuality(_ quality: RecordingQuality) {
        configuration.setRecordingQuality(quality)
    }

    var currentRecordingQuality: RecordingQuality {
        configuration.recordingQuality
    }

    // MARK: - White Balance
    func setWhiteBalance(_ mode: WhiteBalanceMode) {
        configuration.setWhiteBalance(mode)
    }

    var currentWhiteBalanceMode: WhiteBalanceMode {
        configuration.whiteBalanceMode
    }

    // MARK: - Orientation Lock
    func toggleOrientationLock() {
        configuration.toggleOrientationLock()
    }

    var isOrientationLocked: Bool {
        configuration.orientationLocked
    }

    // MARK: - Grid
    func toggleGrid() {
        configuration.toggleGrid()
    }

    var isGridEnabled: Bool {
        configuration.showGrid
    }

    // MARK: - Defaults
    private func setDefaults() {
        hapticFeedbackEnabled = true
        soundEffectsEnabled = true
        autoSaveToLibrary = true
        showWatermark = false
        defaultCaptureMode = .video

        UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
    }

    // MARK: - Reset Settings
    func resetToDefaults() {
        // Reset camera configuration
        configuration = CameraConfiguration()

        // Reset app settings
        setDefaults()

        // Save
        configuration.saveToUserDefaults()
    }

    func confirmReset() {
        showResetConfirmation = true
    }

    // MARK: - Export Settings
    func exportSettings() -> [String: Any] {
        return [
            "aspectRatio": configuration.aspectRatio.rawValue,
            "recordingQuality": configuration.recordingQuality.rawValue,
            "videoStabilization": configuration.videoStabilizationMode.rawValue,
            "whiteBalance": configuration.whiteBalanceMode.rawValue,
            "showGrid": configuration.showGrid,
            "hapticFeedback": hapticFeedbackEnabled,
            "soundEffects": soundEffectsEnabled,
            "autoSave": autoSaveToLibrary,
            "watermark": showWatermark,
            "defaultMode": defaultCaptureMode.rawValue
        ]
    }

    // MARK: - Haptic Feedback
    func triggerHaptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        guard hapticFeedbackEnabled else { return }
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
    }

    func triggerSuccessHaptic() {
        guard hapticFeedbackEnabled else { return }
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }

    func triggerErrorHaptic() {
        guard hapticFeedbackEnabled else { return }
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.error)
    }

    // MARK: - App Info
    var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    var appVersionString: String {
        "Version \(appVersion) (\(buildNumber))"
    }
}
