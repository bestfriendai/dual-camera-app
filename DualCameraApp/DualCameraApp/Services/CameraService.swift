//
//  CameraService.swift
//  DualCam Pro
//
//  Core camera management with AVCaptureMultiCamSession
//

import AVFoundation
import UIKit
import os.log

private let logger = Logger(subsystem: "com.dualcamera.app", category: "CameraService")

final class CameraService {
    // MARK: - Properties

    private var multiCamSession: AVCaptureMultiCamSession?
    private var frontCamera: AVCaptureDevice?
    private var backCamera: AVCaptureDevice?
    private var frontInput: AVCaptureDeviceInput?
    private var backInput: AVCaptureDeviceInput?

    private(set) var isSessionRunning = false
    private(set) var hardwareCost: Float = 0.0
    
    // Preview outputs
    var frontPreviewConnection: AVCaptureConnection?
    var backPreviewConnection: AVCaptureConnection?
    
    // MARK: - Initialization
    
    init() {}
    
    // MARK: - Session Setup
    
    func checkMultiCamSupport() -> Bool {
        return AVCaptureMultiCamSession.isMultiCamSupported
    }
    
    func setupSession() async throws -> AVCaptureMultiCamSession {
        logger.info("Setting up multi-camera session")
        
        guard AVCaptureMultiCamSession.isMultiCamSupported else {
            logger.error("Multi-camera not supported on this device")
            throw CameraError.multiCamNotSupported
        }
        
        // Create session
        let session = AVCaptureMultiCamSession()
        session.beginConfiguration()
        
        // Discover cameras
        try await discoverCameras()
        
        guard let frontCamera = frontCamera,
              let backCamera = backCamera else {
            logger.error("Failed to discover cameras")
            throw CameraError.deviceNotFound
        }
        
        // Create inputs
        let frontInput = try AVCaptureDeviceInput(device: frontCamera)
        let backInput = try AVCaptureDeviceInput(device: backCamera)
        
        // Add inputs without automatic connections
        guard session.canAddInput(frontInput) else {
            logger.error("Cannot add front camera input")
            throw CameraError.configurationFailed
        }
        session.addInputWithNoConnections(frontInput)
        
        guard session.canAddInput(backInput) else {
            logger.error("Cannot add back camera input")
            throw CameraError.configurationFailed
        }
        session.addInputWithNoConnections(backInput)
        
        self.frontInput = frontInput
        self.backInput = backInput
        
        // Commit configuration
        session.commitConfiguration()
        
        self.multiCamSession = session
        
        // Monitor hardware cost
        updateHardwareCost()
        
        logger.info("Multi-camera session setup complete. Hardware cost: \(self.hardwareCost)")
        
        return session
    }
    
    private func discoverCameras() async throws {
        // Front camera
        if let front = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) {
            self.frontCamera = front
            logger.info("Found front camera: \(front.localizedName)")
        } else {
            throw CameraError.deviceNotFound
        }
        
        // Back camera
        if let back = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
            self.backCamera = back
            logger.info("Found back camera: \(back.localizedName)")
        } else {
            throw CameraError.deviceNotFound
        }
    }
    
    // MARK: - Session Control
    
    func startSession() async {
        guard let session = multiCamSession else { return }
        guard !session.isRunning else { return }
        
        logger.info("Starting camera session")
        session.startRunning()
        isSessionRunning = true
    }
    
    func stopSession() async {
        guard let session = multiCamSession else { return }
        guard session.isRunning else { return }
        
        logger.info("Stopping camera session")
        session.stopRunning()
        isSessionRunning = false
    }
    
    // MARK: - Camera Configuration
    
    func configureCamera(
        position: CameraPosition,
        resolution: VideoResolution,
        frameRate: FrameRate
    ) async throws {
        let device = position == .front ? frontCamera : backCamera
        
        guard let device = device else {
            throw CameraError.deviceNotFound
        }
        
        try device.lockForConfiguration()
        
        // Find optimal format
        if let format = findOptimalFormat(for: device, resolution: resolution, frameRate: frameRate) {
            device.activeFormat = format
            
            // Set frame rate
            let frameDuration = CMTime(value: 1, timescale: CMTimeScale(frameRate.rawValue))
            device.activeVideoMinFrameDuration = frameDuration
            device.activeVideoMaxFrameDuration = frameDuration
            
            logger.info("Configured \(position.rawValue) camera: \(resolution.rawValue) @ \(frameRate.rawValue)fps")
        } else {
            logger.warning("Could not find optimal format for \(resolution.rawValue) @ \(frameRate.rawValue)fps")
        }
        
        device.unlockForConfiguration()
        
        // Update hardware cost after configuration change
        updateHardwareCost()

        if self.hardwareCost > 0.95 {
            logger.warning("Hardware cost exceeded: \(self.hardwareCost)")
        }
    }
    
    private func findOptimalFormat(
        for device: AVCaptureDevice,
        resolution: VideoResolution,
        frameRate: FrameRate
    ) -> AVCaptureDevice.Format? {
        let targetWidth = resolution.dimensions.width
        let targetHeight = resolution.dimensions.height
        let targetFrameRate = frameRate.rawValue
        
        return device.formats.first { format in
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            let ranges = format.videoSupportedFrameRateRanges
            
            let matchesDimensions = dimensions.width == targetWidth && dimensions.height == targetHeight
            let supportsFrameRate = ranges.contains { range in
                Double(targetFrameRate) >= range.minFrameRate &&
                Double(targetFrameRate) <= range.maxFrameRate
            }
            
            return matchesDimensions && supportsFrameRate
        }
    }
    
    // MARK: - Focus Control
    
    func setFocusMode(_ mode: FocusMode, at point: CGPoint? = nil) async throws {
        try await configureCameraControl(frontCamera, mode: mode, point: point)
        try await configureCameraControl(backCamera, mode: mode, point: point)
    }
    
    private func configureCameraControl(
        _ device: AVCaptureDevice?,
        mode: FocusMode,
        point: CGPoint?
    ) async throws {
        guard let device = device else { return }
        
        try device.lockForConfiguration()
        
        if let point = point {
            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = point
            }
        }
        
        if device.isFocusModeSupported(mode.avMode) {
            device.focusMode = mode.avMode
        }
        
        device.unlockForConfiguration()
    }
    
    func setManualFocus(_ value: Float, for position: CameraPosition) async throws {
        let device = position == .front ? frontCamera : backCamera
        guard let device = device else { return }
        
        try device.lockForConfiguration()
        device.setFocusModeLocked(lensPosition: value) { _ in }
        device.unlockForConfiguration()
    }
    
    // MARK: - Exposure Control
    
    func setExposureMode(_ mode: ExposureMode, at point: CGPoint? = nil) async throws {
        try await configureExposure(frontCamera, mode: mode, point: point)
        try await configureExposure(backCamera, mode: mode, point: point)
    }
    
    private func configureExposure(
        _ device: AVCaptureDevice?,
        mode: ExposureMode,
        point: CGPoint?
    ) async throws {
        guard let device = device else { return }
        
        try device.lockForConfiguration()
        
        if let point = point {
            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = point
            }
        }
        
        if device.isExposureModeSupported(mode.avMode) {
            device.exposureMode = mode.avMode
        }
        
        device.unlockForConfiguration()
    }
    
    func setExposureCompensation(_ value: Float) async throws {
        try await setExposureComp(frontCamera, value: value)
        try await setExposureComp(backCamera, value: value)
    }
    
    private func setExposureComp(_ device: AVCaptureDevice?, value: Float) async throws {
        guard let device = device else { return }
        
        try device.lockForConfiguration()
        device.setExposureTargetBias(value) { _ in }
        device.unlockForConfiguration()
    }
    
    func setManualExposure(iso: Float, shutterSpeed: Double, for position: CameraPosition) async throws {
        let device = position == .front ? frontCamera : backCamera
        guard let device = device else { return }
        
        try device.lockForConfiguration()
        let duration = CMTime(seconds: shutterSpeed, preferredTimescale: 1000000)
        device.setExposureModeCustom(duration: duration, iso: iso) { _ in }
        device.unlockForConfiguration()
    }
    
    // MARK: - White Balance
    
    func setWhiteBalanceMode(_ mode: WhiteBalanceMode) async throws {
        try await configureWhiteBalance(frontCamera, mode: mode)
        try await configureWhiteBalance(backCamera, mode: mode)
    }
    
    private func configureWhiteBalance(_ device: AVCaptureDevice?, mode: WhiteBalanceMode) async throws {
        guard let device = device else { return }
        
        try device.lockForConfiguration()
        
        if device.isWhiteBalanceModeSupported(mode.avMode) {
            device.whiteBalanceMode = mode.avMode
        }
        
        // Apply temperature if specified
        if let temperature = mode.temperature {
            let gains = device.deviceWhiteBalanceGains(for: .init(temperature: temperature, tint: 0))
            device.setWhiteBalanceModeLocked(with: gains) { _ in }
        }
        
        device.unlockForConfiguration()
    }
    
    // MARK: - Zoom Control
    
    func setZoom(_ factor: CGFloat, for position: CameraPosition, animated: Bool = true) async throws {
        let device = position == .front ? frontCamera : backCamera
        guard let device = device else { return }
        
        let maxZoom = min(device.activeFormat.videoMaxZoomFactor, 10.0)
        let clampedFactor = max(1.0, min(maxZoom, factor))
        
        try device.lockForConfiguration()
        
        if animated {
            device.ramp(toVideoZoomFactor: clampedFactor, withRate: 4.0)
        } else {
            device.videoZoomFactor = clampedFactor
        }
        
        device.unlockForConfiguration()
    }
    
    // MARK: - Flash/Torch
    
    func setTorchMode(_ mode: FlashMode) async throws {
        guard let backCamera = backCamera else { return }
        guard backCamera.hasTorch else { return }
        
        try backCamera.lockForConfiguration()
        
        if backCamera.isTorchModeSupported(mode.torchMode) {
            backCamera.torchMode = mode.torchMode
        }
        
        backCamera.unlockForConfiguration()
    }
    
    // MARK: - Stabilization
    
    func configureStabilization(_ mode: StabilizationMode, for connection: AVCaptureConnection?) {
        guard let connection = connection else { return }
        
        if connection.isVideoStabilizationSupported {
            connection.preferredVideoStabilizationMode = mode.avMode
        }
    }
    
    // MARK: - Hardware Cost Monitoring
    
    private func updateHardwareCost() {
        if let session = multiCamSession {
            hardwareCost = session.hardwareCost
        }
    }
    
    func monitorHardwareCost() -> AsyncStream<Float> {
        let session = isSessionRunning
        let cost = hardwareCost
        return AsyncStream { continuation in
            Task { [weak self] in
                while self?.isSessionRunning == true {
                    self?.updateHardwareCost()
                    if let currentCost = self?.hardwareCost {
                        continuation.yield(currentCost)
                    }
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
                continuation.finish()
            }
        }
    }
    
    // MARK: - Cleanup
    
    func cleanup() async {
        await stopSession()
        multiCamSession = nil
        frontCamera = nil
        backCamera = nil
        frontInput = nil
        backInput = nil
    }
    
    // MARK: - Device Info
    
    func getDeviceInfo() -> (front: String, back: String)? {
        guard let front = frontCamera, let back = backCamera else {
            return nil
        }
        return (front.localizedName, back.localizedName)
    }
}
