
//
//  SettingsManager.swift
//  DualCam Pro
//
//  Central settings management with persistence
//

import Foundation
import Combine

@MainActor
final class SettingsManager: ObservableObject {
    @Published var settings: CameraSettings {
        didSet {
            saveSettings()
        }
    }
    
    // Computed properties for easy access
    var resolution: VideoResolution {
        get { settings.resolution }
        set { settings.resolution = newValue }
    }
    
    var frameRate: FrameRate {
        get { settings.frameRate }
        set { settings.frameRate = newValue }
    }
    
    var codec: VideoCodec {
        get { settings.codec }
        set { settings.codec = newValue }
    }
    
    var stabilization: StabilizationMode {
        get { settings.stabilization }
        set { settings.stabilization = newValue }
    }
    
    var focusMode: FocusMode {
        get { settings.focusMode }
        set { settings.focusMode = newValue }
    }
    
    var exposureMode: ExposureMode {
        get { settings.exposureMode }
        set { settings.exposureMode = newValue }
    }
    
    var whiteBalanceMode: WhiteBalanceMode {
        get { settings.whiteBalanceMode }
        set { settings.whiteBalanceMode = newValue }
    }
    
    var gridType: GridType {
        get { settings.gridType }
        set { settings.gridType = newValue }
    }
    
    var layout: CameraLayout {
        get { settings.layout }
        set { settings.layout = newValue }
    }
    
    private let settingsKey = "DualCameraAppSettings"
    
    init() {
        if let data = UserDefaults.standard.data(forKey: settingsKey),
           let decoded = try? JSONDecoder().decode(CameraSettings.self, from: data) {
            self.settings = decoded
        } else {
            self.settings = .default
        }
    }
    
    private func saveSettings() {
        if let encoded = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(encoded, forKey: settingsKey)
        }
    }
    
    func resetToDefaults() {
        settings = .default
    }
    
    func validateConfiguration() -> Bool {
        // Check if codec is available
        guard settings.codec.isAvailable else {
            return false
        }
        
        // Validate resolution/framerate combo doesn't exceed hardware cost
        // This is a simplified check - actual validation happens in CameraService
        if settings.resolution == .uhd4K && settings.frameRate == .fps60 {
            // Only newer devices can handle 4K60
            return ProcessInfo.processInfo.processorCount >= 6
        }
        
        return true
    }
}
