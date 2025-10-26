
//
//  CameraViewModel.swift
//  DualCam Pro
//
//  ViewModel for camera view
//

import SwiftUI
import AVFoundation
import Combine
import os.log

private let logger = Logger(subsystem: "com.dualcamera.app", category: "CameraViewModel")

@MainActor
final class CameraViewModel: NSObject, ObservableObject {
    // Services
    private let cameraService = CameraService()
    nonisolated(unsafe) private let recordingService = RecordingService()
    nonisolated(unsafe) private let photoLibraryService = PhotoLibraryService.shared

    // State
    @Published var isSessionReady = false
    @Published var recordingState: RecordingState = .idle
    @Published var recordingDuration: TimeInterval = 0
    @Published var hardwareCost: Float = 0.0
    @Published var errorMessage: String?
    
    // Camera session
    nonisolated(unsafe) var multiCamSession: AVCaptureMultiCamSession?
    
    // Data outputs for capture
    nonisolated(unsafe) var frontVideoDataOutput: AVCaptureVideoDataOutput?
    nonisolated(unsafe) var backVideoDataOutput: AVCaptureVideoDataOutput?
    nonisolated(unsafe) var audioDataOutput: AVCaptureAudioDataOutput?
    
    // Recording info
    var lastRecordingURLs: (dualView: URL, front: URL, back: URL)?
    
    // Timer for duration updates
    private var durationTimer: Timer?

    override init() {
        super.init()
    }
    
    // MARK: - Setup
    
    func setupCamera(settings: CameraSettings) async {
        do {
            // Check multi-cam support
            guard await cameraService.checkMultiCamSupport() else {
                errorMessage = CameraError.multiCamNotSupported.errorDescription
                return
            }
            
            // Setup session
            let session = try await cameraService.setupSession()
            self.multiCamSession = session
            
            // Configure cameras
            try await cameraService.configureCamera(
                position: .front,
                resolution: settings.resolution,
                frameRate: settings.frameRate
            )
            
            try await cameraService.configureCamera(
                position: .back,
                resolution: settings.resolution,
                frameRate: settings.frameRate
            )
            
            // Setup data outputs
            await setupDataOutputs(session: session, settings: settings)
            
            // Start session
            await cameraService.startSession()
            
            isSessionReady = true
            
            // Monitor hardware cost
            Task {
                await monitorHardwareCost()
            }
            
            logger.info("Camera setup complete")
            
        } catch {
            errorMessage = error.localizedDescription
            logger.error("Camera setup failed: \(error.localizedDescription)")
        }
    }
    
    private func setupDataOutputs(session: AVCaptureMultiCamSession, settings: CameraSettings) async {
        session.beginConfiguration()
        
        // Front video output
        let frontOutput = AVCaptureVideoDataOutput()
        frontOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        frontOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "com.dualcam.front"))
        
        if session.canAddOutput(frontOutput) {
            session.addOutputWithNoConnections(frontOutput)
            self.frontVideoDataOutput = frontOutput
        }
        
        // Back video output
        let backOutput = AVCaptureVideoDataOutput()
        backOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        backOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "com.dualcam.back"))
        
        if session.canAddOutput(backOutput) {
            session.addOutputWithNoConnections(backOutput)
            self.backVideoDataOutput = backOutput
        }
        
        // Audio output
        let audioOutput = AVCaptureAudioDataOutput()
        audioOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "com.dualcam.audio"))
        
        // Add microphone
        if let audioDevice = AVCaptureDevice.default(for: .audio) {
            if let audioInput = try? AVCaptureDeviceInput(device: audioDevice) {
                if session.canAddInput(audioInput) {
                    session.addInputWithNoConnections(audioInput)
                }
                
                if session.canAddOutput(audioOutput) {
                    session.addOutputWithNoConnections(audioOutput)
                    self.audioDataOutput = audioOutput
                    
                    // Connect audio
                    if let audioPort = audioInput.ports.first {
                        let audioConnection = AVCaptureConnection(inputPorts: [audioPort], output: audioOutput)
                        if session.canAddConnection(audioConnection) {
                            session.addConnection(audioConnection)
                        }
                    }
                }
            }
        }
        
        // Manual connections for video
        // (This would require getting the ports from inputs, simplified here)
        
        session.commitConfiguration()
    }
    
    private func monitorHardwareCost() async {
        for await cost in await cameraService.monitorHardwareCost() {
            await MainActor.run {
                self.hardwareCost = cost
            }
        }
    }
    
    // MARK: - Recording Control
    
    func startRecording(settings: CameraSettings) async {
        guard recordingState == .idle else { return }
        
        recordingState = .starting
        
        do {
            let urls = try await recordingService.startRecording(settings: settings)
            lastRecordingURLs = urls
            
            recordingState = .recording
            recordingDuration = 0
            
            // Start duration timer
            startDurationTimer()
            
            logger.info("Recording started")
            
        } catch {
            recordingState = .error(error.localizedDescription)
            logger.error("Failed to start recording: \(error.localizedDescription)")
        }
    }
    
    func pauseRecording() async {
        guard recordingState == .recording else { return }
        
        await recordingService.pauseRecording()
        recordingState = .paused
        
        stopDurationTimer()
        
        logger.info("Recording paused")
    }
    
    func resumeRecording() async {
        guard recordingState == .paused else { return }
        
        await recordingService.resumeRecording()
        recordingState = .recording
        
        startDurationTimer()
        
        logger.info("Recording resumed")
    }
    
    func stopRecording(settings: CameraSettings) async {
        guard recordingState == .recording || recordingState == .paused else { return }
        
        recordingState = .stopping
        stopDurationTimer()
        
        do {
            if let urls = try await recordingService.stopRecording() {
                lastRecordingURLs = urls
                
                // Save to photo library if enabled
                if settings.autoSaveToPhotos {
                    try await photoLibraryService.saveThreeVideos(
                        dualView: urls.dualView,
                        front: urls.front,
                        back: urls.back,
                        createAlbum: settings.createSeparateAlbum
                    )
                }
                
                logger.info("Recording stopped and saved")
            }
            
            recordingState = .idle
            recordingDuration = 0
            
        } catch {
            recordingState = .error(error.localizedDescription)
            logger.error("Failed to stop recording: \(error.localizedDescription)")
        }
    }

    func toggleRecording(settings: CameraSettings) async {
        switch recordingState {
        case .idle:
            await startRecording(settings: settings)
        case .recording, .paused:
            await stopRecording(settings: settings)
        default:
            break
        }
    }

    private func startDurationTimer() {
        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                if let info = await self?.recordingService.getRecordingInfo() {
                    self?.recordingDuration = info.duration
                }
            }
        }
    }
    
    private func stopDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = nil
    }
    
    // MARK: - Camera Controls
    
    func setZoom(_ factor: CGFloat, for position: CameraPosition) async {
        do {
            try await cameraService.setZoom(factor, for: position)
        } catch {
            logger.error("Failed to set zoom: \(error.localizedDescription)")
        }
    }
    
    func setFocusMode(_ mode: FocusMode, at point: CGPoint? = nil) async {
        do {
            try await cameraService.setFocusMode(mode, at: point)
        } catch {
            logger.error("Failed to set focus: \(error.localizedDescription)")
        }
    }
    
    func setExposureMode(_ mode: ExposureMode, at point: CGPoint? = nil) async {
        do {
            try await cameraService.setExposureMode(mode, at: point)
        } catch {
            logger.error("Failed to set exposure: \(error.localizedDescription)")
        }
    }
    
    func setWhiteBalance(_ mode: WhiteBalanceMode) async {
        do {
            try await cameraService.setWhiteBalanceMode(mode)
        } catch {
            logger.error("Failed to set white balance: \(error.localizedDescription)")
        }
    }
    
    func setTorch(_ mode: FlashMode) async {
        do {
            try await cameraService.setTorchMode(mode)
        } catch {
            logger.error("Failed to set torch: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Cleanup
    
    func cleanup() async {
        stopDurationTimer()
        await cameraService.cleanup()
        multiCamSession = nil
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraViewModel: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    nonisolated(unsafe) func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        // Process samples - using Task.detached to avoid actor isolation issues
        _ = Task.detached { [recordingService, frontVideoDataOutput, backVideoDataOutput, audioDataOutput] in
            if output == frontVideoDataOutput {
                await recordingService.processFrontSample(sampleBuffer)
            } else if output == backVideoDataOutput {
                await recordingService.processBackSample(sampleBuffer)
            } else if output == audioDataOutput {
                await recordingService.processAudioSample(sampleBuffer)
            }
        }
    }
}
