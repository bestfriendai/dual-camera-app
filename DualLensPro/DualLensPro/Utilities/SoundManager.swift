//
//  SoundManager.swift
//  DualLensPro
//
//  Created by Claude on 11/12/2025.
//  Sound effects manager using iOS system sounds
//

import AVFoundation
import UIKit

@MainActor
final class SoundManager {
    static let shared = SoundManager()

    private var soundsEnabled: Bool {
        UserDefaults.standard.bool(forKey: "settings.soundEffects")
    }

    // iOS System Sound IDs for camera-related actions
    private enum SoundID: SystemSoundID {
        case shutter = 1108        // Camera shutter
        case recordStart = 1117    // Begin recording
        case recordStop = 1118     // End recording
        case focus = 1109          // Focus/tap
        case modeChange = 1306     // Mode/setting change
        case error = 1053          // Error/warning
        case success = 1054        // Success/completion
    }

    private init() {}

    // MARK: - Public Sound Methods

    /// Play camera shutter sound (for photo capture)
    func playShutter() {
        guard soundsEnabled else { return }
        AudioServicesPlaySystemSound(SoundID.shutter.rawValue)
    }

    /// Play record start sound (when video recording begins)
    func playRecordStart() {
        guard soundsEnabled else { return }
        AudioServicesPlaySystemSound(SoundID.recordStart.rawValue)
    }

    /// Play record stop sound (when video recording ends)
    func playRecordStop() {
        guard soundsEnabled else { return }
        AudioServicesPlaySystemSound(SoundID.recordStop.rawValue)
    }

    /// Play focus sound (for tap-to-focus or focus lock)
    func playFocus() {
        guard soundsEnabled else { return }
        AudioServicesPlaySystemSound(SoundID.focus.rawValue)
    }

    /// Play mode change sound (for switching capture modes or settings)
    func playModeChange() {
        guard soundsEnabled else { return }
        AudioServicesPlaySystemSound(SoundID.modeChange.rawValue)
    }

    /// Play error sound (for warnings or errors)
    func playError() {
        guard soundsEnabled else { return }
        AudioServicesPlaySystemSound(SoundID.error.rawValue)
    }

    /// Play success sound (for successful completion of action)
    func playSuccess() {
        guard soundsEnabled else { return }
        AudioServicesPlaySystemSound(SoundID.success.rawValue)
    }
}
