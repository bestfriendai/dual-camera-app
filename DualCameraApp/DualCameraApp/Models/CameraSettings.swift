
//
//  CameraSettings.swift
//  DualCam Pro
//
//  Camera configuration settings
//

import Foundation

struct CameraSettings: Codable, Equatable {
    // Video Quality
    var resolution: VideoResolution
    var frameRate: FrameRate
    var codec: VideoCodec
    var bitRate: BitRate
    
    // Camera Controls
    var stabilization: StabilizationMode
    var focusMode: FocusMode
    var exposureMode: ExposureMode
    var whiteBalanceMode: WhiteBalanceMode
    var flashMode: FlashMode
    
    // UI Options
    var gridType: GridType
    var timerDuration: TimerDuration
    var filter: VideoFilter
    var layout: CameraLayout
    
    // Recording Behavior
    var autoSaveToPhotos: Bool
    var createSeparateAlbum: Bool
    var keepInAppCopies: Bool
    var windNoiseReduction: Bool
    
    // Manual Controls
    var manualZoomFront: Float
    var manualZoomBack: Float
    var manualFocus: Float?
    var manualISO: Float?
    var manualShutterSpeed: Double?
    var exposureCompensation: Float
    
    static let `default` = CameraSettings(
        resolution: .fullHD,
        frameRate: .fps30,
        codec: .hevc,
        bitRate: .auto,
        stabilization: .standard,
        focusMode: .continuousAuto,
        exposureMode: .continuousAuto,
        whiteBalanceMode: .continuousAuto,
        flashMode: .off,
        gridType: .none,
        timerDuration: .none,
        filter: .none,
        layout: .frontOnTop,
        autoSaveToPhotos: true,
        createSeparateAlbum: true,
        keepInAppCopies: true,
        windNoiseReduction: true,
        manualZoomFront: 1.0,
        manualZoomBack: 1.0,
        manualFocus: nil,
        manualISO: nil,
        manualShutterSpeed: nil,
        exposureCompensation: 0.0
    )
}
