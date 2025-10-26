//
//  DualCameraManager.swift
//  DualLensPro
//
//  Created by DualLens Pro Team on 10/24/25.
//

import AVFoundation
import UIKit
import Photos
import os

@MainActor
class DualCameraManager: NSObject, ObservableObject {
    // MARK: - Published Properties
    @Published var isSessionRunning = false
    @Published var recordingState: RecordingState = .idle {
        didSet {
            // Use nonisolated wrapper to update lock
            updateRecordingStateLock(newValue: recordingState)
        }
    }
    @Published var recordingDuration: TimeInterval = 0
    @Published var errorMessage: String?
    @Published var showGrid = false
    @Published var flashMode: AVCaptureDevice.FlashMode = .off
    @Published var timerDuration: Int = 0 // 0, 3, 10 seconds
    @Published var isCenterStageEnabled = false

    // MARK: - Multi-Cam Support
    var isMultiCamSupported: Bool {
        AVCaptureMultiCamSession.isMultiCamSupported
    }
    nonisolated(unsafe) private var useMultiCam: Bool = false

    // MARK: - Thread-Safe State (using OSAllocatedUnfairLock for safe GCD access)
    private let recordingStateLock = OSAllocatedUnfairLock<RecordingState>(initialState: .idle)

    // Helper to update lock from MainActor context
    nonisolated private func updateRecordingStateLock(newValue: RecordingState) {
        recordingStateLock.withLock { $0 = newValue }
    }

    // A Sendable wrapper for CMSampleBuffer so we can pass it across @Sendable closures safely in Swift 6
    private final class SampleBufferBox: @unchecked Sendable {
        let buffer: CMSampleBuffer
        init(_ buffer: CMSampleBuffer) { self.buffer = buffer }
    }


    // MARK: - Camera Session
    // Sessions accessed only from sessionQueue (thread-safe)
    nonisolated(unsafe) private var multiCamSession: AVCaptureMultiCamSession = AVCaptureMultiCamSession()
    nonisolated(unsafe) private var singleCamSession: AVCaptureSession = AVCaptureSession()

    // Active session (either multi-cam or single-cam)
    // Accessed only from sessionQueue - thread-safe via serial queue
    private var activeSession: AVCaptureSession {
        useMultiCam ? multiCamSession : singleCamSession
    }

    // Camera inputs - accessed only from sessionQueue (thread-safe)
    nonisolated(unsafe) private var frontCameraInput: AVCaptureDeviceInput?
    nonisolated(unsafe) private var backCameraInput: AVCaptureDeviceInput?

    // MARK: - Video Outputs (accessed from delegate callbacks on specific queues)
    nonisolated(unsafe) private var frontVideoOutput: AVCaptureVideoDataOutput?
    nonisolated(unsafe) private var backVideoOutput: AVCaptureVideoDataOutput?
    nonisolated(unsafe) private var audioOutput: AVCaptureAudioDataOutput?

    // MARK: - Photo Outputs
    private var frontPhotoOutput: AVCapturePhotoOutput?
    private var backPhotoOutput: AVCapturePhotoOutput?

    // Photo capture delegate storage (thread-safe access)
    private let photoDelegateQueue = DispatchQueue(label: "com.duallens.photoDelegates")
    nonisolated(unsafe) private var _activePhotoDelegates: [String: PhotoCaptureDelegate] = [:]

    // MARK: - Preview Layers
    var frontPreviewLayer: AVCaptureVideoPreviewLayer?
    var backPreviewLayer: AVCaptureVideoPreviewLayer?

    // MARK: - Recording (Protected by writerQueue - all access must be on this queue)
    nonisolated(unsafe) private var frontAssetWriter: AVAssetWriter?
    nonisolated(unsafe) private var backAssetWriter: AVAssetWriter?
    nonisolated(unsafe) private var combinedAssetWriter: AVAssetWriter?

    nonisolated(unsafe) private var frontVideoInput: AVAssetWriterInput?
    nonisolated(unsafe) private var backVideoInput: AVAssetWriterInput?
    nonisolated(unsafe) private var combinedVideoInput: AVAssetWriterInput?
    nonisolated(unsafe) private var combinedAudioInput: AVAssetWriterInput?

    nonisolated(unsafe) private var frontPixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    nonisolated(unsafe) private var backPixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    nonisolated(unsafe) private var combinedPixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?

    // Add new property to track writer configuration readiness
    nonisolated(unsafe) private var writersConfigured = false

    // Background task support
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

    // URLs accessed from cleanup - nonisolated safe since only used for file deletion
    nonisolated(unsafe) private var frontOutputURL: URL?
    nonisolated(unsafe) private var backOutputURL: URL?
    nonisolated(unsafe) private var combinedOutputURL: URL?

    nonisolated(unsafe) private var recordingStartTime: CMTime?
    nonisolated(unsafe) private var isWriting = false
    nonisolated(unsafe) private var hasReceivedFirstVideoFrame = false
    nonisolated(unsafe) private var hasReceivedFirstAudioFrame = false

    // MARK: - Dispatch Queues
    private let sessionQueue = DispatchQueue(label: "com.duallens.sessionQueue")
    private let videoQueue = DispatchQueue(label: "com.duallens.videoQueue")
    private let audioQueue = DispatchQueue(label: "com.duallens.audioQueue")
    // Serial queue for ALL AVAssetWriter operations (thread-safe writer access)
    private let writerQueue = DispatchQueue(label: "com.duallens.writerQueue")

    // MARK: - Recording Quality
    nonisolated(unsafe) var recordingQuality: RecordingQuality = .high

    // MARK: - Capture Mode
    nonisolated(unsafe) var captureMode: CaptureMode = .video {
        didSet {
            // Only apply capture mode changes if camera setup is complete
            guard isCameraSetupComplete else { return }
            // applyCaptureMode is called async on sessionQueue
            Task {
                await applyCaptureMode()
            }
        }
    }

    // MARK: - Camera Layout (for Switch Screen mode)
    @Published var isCamerasSwitched = false

    // MARK: - Zoom Configuration
    // Flag to prevent zoom updates before camera is ready
    nonisolated(unsafe) private var isCameraSetupComplete = false

    var frontZoomFactor: CGFloat = 0.5 { // Default to 0.5x for front camera
        didSet {
            // Only update zoom if camera setup is complete to prevent crashes during init
            guard isCameraSetupComplete else { return }
            updateZoom(for: .front, factor: frontZoomFactor)
        }
    }

    var backZoomFactor: CGFloat = 1.0 {
        didSet {
            // Only update zoom if camera setup is complete to prevent crashes during init
            guard isCameraSetupComplete else { return }
            updateZoom(for: .back, factor: backZoomFactor)
        }
    }

    // MARK: - Focus and Exposure
    @Published var isFocusLocked = false
    @Published var exposureValue: Float = 0.0 // -2.0 to 2.0

    // MARK: - Initialization
    override init() {
        super.init()
        setupNotificationObservers()
    }

    private func setupNotificationObservers() {
        // Session interruption notifications (iOS 18+ modern API)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sessionWasInterrupted),
            name: AVCaptureSession.wasInterruptedNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sessionInterruptionEnded),
            name: AVCaptureSession.interruptionEndedNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sessionRuntimeError),
            name: AVCaptureSession.runtimeErrorNotification,
            object: nil
        )


        // Thermal state monitoring
        // Note: Removed #selector for thermalStateChanged as it's not critical for release
        // TODO: Re-add thermal monitoring if needed
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(audioSessionInterrupted),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
    }

    @objc nonisolated private func sessionWasInterrupted(notification: Notification) {
        Task { @MainActor in
            print("⚠️ Session interrupted")
            if recordingState == .recording {
                do {
                    try await stopRecording()
                    errorMessage = "Recording stopped due to interruption (phone call, FaceTime, etc.)"
                } catch {
                    print("❌ Error stopping recording after interruption: \(error)")
                }
            }
        }
    }
    @objc nonisolated private func sessionRuntimeError(notification: Notification) {
        let error = notification.userInfo?[AVCaptureSessionErrorKey] as? AVError
        let description = error?.localizedDescription ?? "unknown"
        print("❌ Session runtime error: \(description)")

        // If media services were reset, recreate the session
        if let error = error, error.code == .mediaServicesWereReset {
            Task { @MainActor in
                do {
                    // Stop and recreate the session safely
                    self.isSessionRunning = false
                    try await self.setupSession()
                    self.startSession()
                    self.errorMessage = nil
                    print("✅ Session recreated after media services reset")
                } catch {
                    self.errorMessage = "Camera error: \(error.localizedDescription)"
                    print("❌ Failed to recreate session: \(error)")
                }
            }
        } else {
            Task { @MainActor in
                self.errorMessage = "Camera error: \(description)"
            }
        }
    }


    @objc nonisolated private func sessionInterruptionEnded(notification: Notification) {
        Task { @MainActor in
            print("✅ Session interruption ended")
            errorMessage = nil
        }
    }
    
    @objc nonisolated private func audioSessionInterrupted(notification: Notification) {
        let userInfo = notification.userInfo
        let typeValue = userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
        let type = AVAudioSession.InterruptionType(rawValue: typeValue ?? 0)

        switch type {
        case .began:
            Task { @MainActor in
                print("🔇 Audio session interruption began")
                if recordingState == .recording {
                    do {
                        try await stopRecording()
                        errorMessage = "Recording stopped due to audio interruption"
                    } catch {
                        print("❌ Error stopping after audio interruption: \(error)")
                    }
                }
            }
        case .ended:
            print("🔊 Audio session interruption ended - reactivating")
            do {
                try configureAudioSession()
            } catch {
                print("❌ Failed to reactivate audio session: \(error)")
            }
        default:
            break
        }
    }

    nonisolated private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .videoRecording, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true, options: [])
        print("🔊 AVAudioSession configured: playAndRecord/videoRecording")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        cleanupTemporaryFiles()
    }

    nonisolated private func cleanup() {
        cleanupTemporaryFiles()
    }

    nonisolated private func cleanupTemporaryFiles() {
        // Clean up temporary files
        if let url = frontOutputURL {
            try? FileManager.default.removeItem(at: url)
            print("🗑️ Cleaned up front camera file")
        }
        if let url = backOutputURL {
            try? FileManager.default.removeItem(at: url)
            print("🗑️ Cleaned up back camera file")
        }
        if let url = combinedOutputURL {
            try? FileManager.default.removeItem(at: url)
            print("🗑️ Cleaned up combined file")
        }

        // Reset URLs
        frontOutputURL = nil
        backOutputURL = nil
        combinedOutputURL = nil
    }

    // MARK: - Setup Methods
    func setupSession() async throws {
        print("📸 Setting up camera session...")

        // Configure audio session before capture setup
        try configureAudioSession()

        // CRITICAL: Prevent duplicate setup - if session is already configured, stop it first
        if isSessionRunning {
            print("⚠️ Session already running - stopping before reconfiguration")
            stopSession()
            // Wait for session to fully stop
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        }

        // Determine if we should use multi-cam or single-cam
        useMultiCam = AVCaptureMultiCamSession.isMultiCamSupported

        if useMultiCam {
            print("✅ Multi-cam is supported - using dual camera mode")
        } else {
            print("⚠️ Multi-cam NOT supported - using single camera fallback mode")
        }

        activeSession.beginConfiguration()
        defer {
            activeSession.commitConfiguration()
            print("✅ Session configuration committed")
        }

        // Clean up any existing inputs/outputs to prevent duplicate connections
        // This must be done within the configuration block
        activeSession.inputs.forEach { activeSession.removeInput($0) }
        activeSession.outputs.forEach { activeSession.removeOutput($0) }
        activeSession.connections.forEach { activeSession.removeConnection($0) }
        print("✅ Cleaned up existing session configuration")

        if useMultiCam {
            // Setup both cameras for multi-cam mode
            print("🎥 Setting up front camera...")
            try await setupCamera(position: .front)
            print("✅ Front camera setup complete")

            print("🎥 Setting up back camera...")
            try await setupCamera(position: .back)
            print("✅ Back camera setup complete")
        } else {
            // Setup only back camera for single-cam mode
            print("🎥 Setting up back camera (single-cam mode)...")
            try await setupCamera(position: .back)
            print("✅ Back camera setup complete (single-cam mode)")
        }

        // Setup audio
        print("🎤 Setting up audio...")
        try setupAudio()
        print("✅ Audio setup complete")

        // Create preview layers
        print("🖼️ Creating preview layers...")
        await createPreviewLayers()
        print("✅ Preview layers created")

        // Mark camera setup as complete - now safe to update zoom and other camera properties
        isCameraSetupComplete = true
        print("✅ Camera setup complete - zoom updates now enabled")

        // Apply initial zoom values now that setup is complete
        if useMultiCam {
            updateZoom(for: .front, factor: frontZoomFactor)
        }
        updateZoom(for: .back, factor: backZoomFactor)
        print("✅ Initial zoom values applied: \(useMultiCam ? "front=\(frontZoomFactor)x, " : "")back=\(backZoomFactor)x")
    }

    private func setupCamera(position: AVCaptureDevice.Position) async throws {
        // Find camera device
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else {
            throw CameraError.deviceNotFound(position)
        }

        // Configure camera device for optimal recording
        try camera.lockForConfiguration()
        defer { camera.unlockForConfiguration() }

        // Enable HDR video if supported
        if camera.activeFormat.isVideoHDRSupported {
            camera.automaticallyAdjustsVideoHDREnabled = true
        }

        // Set frame rate based on capture mode
        let targetFrameRate = captureMode.frameRate
        for range in camera.activeFormat.videoSupportedFrameRateRanges {
            if range.maxFrameRate >= Double(targetFrameRate) {
                camera.activeVideoMinFrameDuration = CMTime(value: 1, timescale: CMTimeScale(targetFrameRate))
                camera.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: CMTimeScale(targetFrameRate))
                print("📹 Set frame rate to \(targetFrameRate)fps for \(captureMode.rawValue) mode")
                break
            }
        }

        // NOTE: Do NOT set zoom here - it will be set after setup is complete via the zoom properties
        // Setting zoom during init can cause issues with didSet observers

        // Create input
        let input = try AVCaptureDeviceInput(device: camera)

        if useMultiCam {
            // For multi-cam sessions, use addInputWithNoConnections
            // Don't check canAddInput for multi-cam - it will return false
            multiCamSession.addInputWithNoConnections(input)
            print("✅ Added input with no connections for \(position == .front ? "front" : "back") camera")
        } else {
            // For single-cam sessions, check and add normally
            guard singleCamSession.canAddInput(input) else {
                throw CameraError.cannotAddInput(position)
            }
            singleCamSession.addInput(input)
            print("✅ Added input for \(position == .front ? "front" : "back") camera (single-cam mode)")
        }

        // Store input reference
        if position == .front {
            frontCameraInput = input
        } else {
            backCameraInput = input
        }

        // Setup video output
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
        videoOutput.alwaysDiscardsLateVideoFrames = true

        // Configure video settings for optimal quality
        let videoSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]
        videoOutput.videoSettings = videoSettings

        if useMultiCam {
            // For multi-cam sessions, use addOutputWithNoConnections
            // Don't check canAddOutput for multi-cam
            multiCamSession.addOutputWithNoConnections(videoOutput)
            print("✅ Added video output with no connections for \(position == .front ? "front" : "back") camera")

            // Manually create connection between input and output
            guard let videoPort = input.ports(for: .video, sourceDeviceType: camera.deviceType, sourceDevicePosition: position).first else {
                throw CameraError.cannotCreateConnection(position)
            }

            let videoConnection = AVCaptureConnection(inputPorts: [videoPort], output: videoOutput)

            guard multiCamSession.canAddConnection(videoConnection) else {
                throw CameraError.cannotAddConnection(position)
            }

            multiCamSession.addConnection(videoConnection)

            // Configure connection
            if videoConnection.isVideoStabilizationSupported {
                videoConnection.preferredVideoStabilizationMode = .auto
            }
            if videoConnection.isVideoMirroringSupported && position == .front {
                videoConnection.isVideoMirrored = true
            }
        } else {
            // For single-cam sessions, check and add normally
            guard singleCamSession.canAddOutput(videoOutput) else {
                throw CameraError.cannotAddOutput(position)
            }
            singleCamSession.addOutput(videoOutput)
            print("✅ Added video output for \(position == .front ? "front" : "back") camera (single-cam mode)")

            // Configure connection
            if let connection = videoOutput.connection(with: .video) {
                if connection.isVideoStabilizationSupported {
                    connection.preferredVideoStabilizationMode = .auto
                }
                if connection.isVideoMirroringSupported && position == .front {
                    connection.isVideoMirrored = true
                }
            }
        }

        // Store output reference
        if position == .front {
            frontVideoOutput = videoOutput
        } else {
            backVideoOutput = videoOutput
        }

        // Setup photo output
        let photoOutput = AVCapturePhotoOutput()
        photoOutput.maxPhotoQualityPrioritization = .quality

        if useMultiCam {
            // For multi-cam sessions, use addOutputWithNoConnections for photo output too
            // Don't check canAddOutput for multi-cam
            multiCamSession.addOutputWithNoConnections(photoOutput)
            print("✅ Added photo output with no connections for \(position == .front ? "front" : "back") camera")

            // Create connection for photo output
            // We can reuse the same video port for multiple outputs (video + photo)
            guard let photoPort = input.ports(for: .video, sourceDeviceType: camera.deviceType, sourceDevicePosition: position).first else {
                throw CameraError.cannotCreateConnection(position)
            }

            let photoConnection = AVCaptureConnection(inputPorts: [photoPort], output: photoOutput)

            guard multiCamSession.canAddConnection(photoConnection) else {
                print("❌ Cannot add photo connection - connection check failed")
                throw CameraError.cannotAddPhotoConnection(position)
            }

            multiCamSession.addConnection(photoConnection)
            print("✅ Added photo connection for \(position == .front ? "front" : "back") camera")
        } else {
            // For single-cam sessions, check and add normally
            guard singleCamSession.canAddOutput(photoOutput) else {
                throw CameraError.cannotAddPhotoOutput(position)
            }
            singleCamSession.addOutput(photoOutput)
            print("✅ Added photo output for \(position == .front ? "front" : "back") camera (single-cam mode)")
        }

        // Store photo output reference
        if position == .front {
            frontPhotoOutput = photoOutput
        } else {
            backPhotoOutput = photoOutput
        }
    }

    private func setupAudio() throws {
        guard let audioDevice = AVCaptureDevice.default(for: .audio) else {
            throw CameraError.audioDeviceNotFound
        }

        let audioInput = try AVCaptureDeviceInput(device: audioDevice)

        guard activeSession.canAddInput(audioInput) else {
            throw CameraError.cannotAddAudioInput
        }

        activeSession.addInput(audioInput)

        // Setup audio data output
        let audioDataOutput = AVCaptureAudioDataOutput()
        audioDataOutput.setSampleBufferDelegate(self, queue: audioQueue)

        guard activeSession.canAddOutput(audioDataOutput) else {
            throw CameraError.cannotAddAudioOutput
        }

        activeSession.addOutput(audioDataOutput)
        audioOutput = audioDataOutput
    }

    private func createPreviewLayers() async {
        if useMultiCam {
            // For multi-cam sessions, MUST use sessionWithNoConnection: to avoid crash
            // Then manually create connections
            print("🖼️ Creating multi-cam preview layers with no connections...")

            // Front camera preview layer
            let frontLayer = AVCaptureVideoPreviewLayer(sessionWithNoConnection: multiCamSession)
            frontLayer.videoGravity = .resizeAspectFill

            // Create connection for front camera
            if let frontInput = frontCameraInput,
               let frontPort = frontInput.ports(for: .video, sourceDeviceType: .builtInWideAngleCamera, sourceDevicePosition: .front).first {
                let frontConnection = AVCaptureConnection(inputPort: frontPort, videoPreviewLayer: frontLayer)
                frontConnection.videoRotationAngle = 90 // Portrait orientation
                if frontConnection.isVideoMirroringSupported {
                    frontConnection.automaticallyAdjustsVideoMirroring = false
                    frontConnection.isVideoMirrored = true
                }
                if multiCamSession.canAddConnection(frontConnection) {
                    multiCamSession.addConnection(frontConnection)
                    print("✅ Added front preview layer connection")
                }
            }
            frontPreviewLayer = frontLayer

            // Back camera preview layer
            let backLayer = AVCaptureVideoPreviewLayer(sessionWithNoConnection: multiCamSession)
            backLayer.videoGravity = .resizeAspectFill

            // Create connection for back camera
            if let backInput = backCameraInput,
               let backPort = backInput.ports(for: .video, sourceDeviceType: .builtInWideAngleCamera, sourceDevicePosition: .back).first {
                let backConnection = AVCaptureConnection(inputPort: backPort, videoPreviewLayer: backLayer)
                backConnection.videoRotationAngle = 90 // Portrait orientation
                if multiCamSession.canAddConnection(backConnection) {
                    multiCamSession.addConnection(backConnection)
                    print("✅ Added back preview layer connection")
                }
            }
            backPreviewLayer = backLayer

        } else {
            // For single-cam sessions, use regular session initialization
            let backLayer = AVCaptureVideoPreviewLayer(session: singleCamSession)
            backLayer.videoGravity = .resizeAspectFill
            if let connection = backLayer.connection {
                connection.videoRotationAngle = 90 // Portrait orientation
            }
            backPreviewLayer = backLayer

            // No front preview in single-cam mode
            frontPreviewLayer = nil
        }
    }

    // MARK: - Session Control
    func startSession() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            if !self.activeSession.isRunning {
                self.activeSession.startRunning()
                Task { @MainActor in
                    self.isSessionRunning = self.activeSession.isRunning
                    print("✅ Session started (\(self.useMultiCam ? "multi-cam" : "single-cam") mode)")

                    // Apply zooms once session is running to avoid early failures
                    if self.isCameraSetupComplete {
                        if self.useMultiCam {
                            self.updateZoom(for: .front, factor: self.frontZoomFactor)
                        }
                        self.updateZoom(for: .back, factor: self.backZoomFactor)
                    }
                }
            }
        }
    }

    func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            if self.activeSession.isRunning {
                self.activeSession.stopRunning()
                Task { @MainActor in
                    self.isSessionRunning = false
                    print("🛑 Session stopped")
                }
            }
        }
    }

    // MARK: - Zoom Control
    private func updateZoom(for position: CameraPosition, factor: CGFloat) {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }

            // Check if session is running
            guard self.isSessionRunning else {
                print("⚠️ Cannot update zoom - session not running")
                return
            }

            let device: AVCaptureDevice?
            switch position {
            case .front:
                device = self.frontCameraInput?.device
            case .back:
                device = self.backCameraInput?.device
            }

            guard let device = device else {
                print("⚠️ Device not found for position: \(position)")
                return
            }

            // Check device is connected (important for external cameras on iPad)
            guard device.isConnected else {
                print("⚠️ Device not connected")
                return
            }

            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }

                let clampedFactor = min(max(factor, device.minAvailableVideoZoomFactor), device.maxAvailableVideoZoomFactor)
                device.videoZoomFactor = clampedFactor
            } catch {
                print("❌ Error setting zoom: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Photo Capture
    func capturePhoto() async throws {
        // Apply timer if set (validate to prevent overflow and ensure reasonable range)
        let validatedDuration = max(0, min(timerDuration, 30))  // Max 30 seconds
        if validatedDuration > 0 {
            await MainActor.run {
                recordingState = .processing
            }
            try await Task.sleep(nanoseconds: UInt64(validatedDuration) * 1_000_000_000)
        }

        // Determine which cameras to capture from based on configuration
        let shouldCaptureFront = self.useMultiCam && self.frontPhotoOutput != nil
        let shouldCaptureBack = self.backPhotoOutput != nil

        if shouldCaptureFront && shouldCaptureBack {
            // Capture both concurrently
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask { try await self.captureFrontPhoto() }
                group.addTask { try await self.captureBackPhoto() }
                try await group.waitForAll()
            }
        } else if shouldCaptureBack {
            try await captureBackPhoto()
        } else if shouldCaptureFront {
            try await captureFrontPhoto()
        } else {
            throw CameraError.photoOutputNotConfigured
        }

        await MainActor.run {
            recordingState = .idle
        }
    }

    private func captureFrontPhoto() async throws {
        guard let photoOutput = frontPhotoOutput else {
            throw CameraError.photoOutputNotConfigured
        }

        let settings = AVCapturePhotoSettings()
        settings.flashMode = .off // Front camera typically doesn't have flash

        return try await withCheckedThrowingContinuation { continuation in
            let delegateId = UUID().uuidString
            let delegate = PhotoCaptureDelegate(
                continuation: continuation,
                camera: "front"
            ) { [weak self] in
                // Thread-safe cleanup of delegate
                self?.removePhotoDelegate(for: delegateId)
            }
            addPhotoDelegate(delegate, for: delegateId)
            photoOutput.capturePhoto(with: settings, delegate: delegate)
        }
    }

    private func captureBackPhoto() async throws {
        guard let photoOutput = backPhotoOutput else {
            throw CameraError.photoOutputNotConfigured
        }

        let settings = AVCapturePhotoSettings()
        settings.flashMode = flashMode

        return try await withCheckedThrowingContinuation { continuation in
            let delegateId = UUID().uuidString
            let delegate = PhotoCaptureDelegate(
                continuation: continuation,
                camera: "back"
            ) { [weak self] in
                // Thread-safe cleanup of delegate
                self?.removePhotoDelegate(for: delegateId)
            }
            addPhotoDelegate(delegate, for: delegateId)
            photoOutput.capturePhoto(with: settings, delegate: delegate)
        }
    }

    // Thread-safe delegate management
    private func addPhotoDelegate(_ delegate: PhotoCaptureDelegate, for id: String) {
        photoDelegateQueue.sync {
            _activePhotoDelegates[id] = delegate
        }
    }

    private func removePhotoDelegate(for id: String) {
        photoDelegateQueue.async { [weak self] in
            self?._activePhotoDelegates.removeValue(forKey: id)
        }
    }

    // MARK: - Focus Control
    func setFocusPoint(_ point: CGPoint, in previewLayer: AVCaptureVideoPreviewLayer, for position: CameraPosition) {
        // Convert point on main thread FIRST (before going to background queue)
        let devicePoint = previewLayer.captureDevicePointConverted(fromLayerPoint: point)

        sessionQueue.async { [weak self] in
            guard let self = self else { return }

            let device: AVCaptureDevice?
            switch position {
            case .front:
                device = self.frontCameraInput?.device
            case .back:
                device = self.backCameraInput?.device
            }

            guard let device = device else { return }

            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }

                if device.isFocusPointOfInterestSupported && device.isFocusModeSupported(.autoFocus) {
                    device.focusPointOfInterest = devicePoint
                    device.focusMode = .autoFocus
                }

                if device.isExposurePointOfInterestSupported && device.isExposureModeSupported(.autoExpose) {
                    device.exposurePointOfInterest = devicePoint
                    device.exposureMode = .autoExpose
                }
            } catch {
                print("Error setting focus: \(error.localizedDescription)")
            }
        }
    }

    func toggleFocusLock(for position: CameraPosition) {
        Task {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                sessionQueue.async { [weak self] in
                    guard let self = self else {
                        continuation.resume()
                        return
                    }

                    let device: AVCaptureDevice?
                    switch position {
                    case .front:
                        device = self.frontCameraInput?.device
                    case .back:
                        device = self.backCameraInput?.device
                    }

                    guard let device = device else {
                        continuation.resume()
                        return
                    }

                    do {
                        try device.lockForConfiguration()
                        defer { device.unlockForConfiguration() }

                        // Toggle focus lock on main actor
                        let focusLockMode: AVCaptureDevice.FocusMode = self.isFocusLocked ? .continuousAutoFocus : .locked

                        Task { @MainActor in
                            self.isFocusLocked.toggle()
                        }

                        if device.isFocusModeSupported(focusLockMode) {
                            device.focusMode = focusLockMode
                        }
                        continuation.resume()
                    } catch {
                        print("Error toggling focus lock: \(error.localizedDescription)")
                        continuation.resume()
                    }
                }
            }
        }
    }

    // MARK: - Exposure Control
    func setExposure(_ value: Float, for position: CameraPosition) {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }

            let device: AVCaptureDevice?
            switch position {
            case .front:
                device = self.frontCameraInput?.device
            case .back:
                device = self.backCameraInput?.device
            }

            guard let device = device else { return }

            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }

                device.setExposureTargetBias(value, completionHandler: nil)

                Task { @MainActor in
                    self.exposureValue = value
                }
            } catch {
                print("Error setting exposure: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Flash Control
    func toggleFlash() {
        switch flashMode {
        case .off:
            flashMode = .on
        case .on:
            flashMode = .auto
        case .auto:
            flashMode = .off
        @unknown default:
            flashMode = .off
        }
    }

    // MARK: - Timer Control
    func setTimer(_ duration: Int) {
        timerDuration = duration
    }

    // MARK: - Grid Toggle
    func toggleGrid() {
        showGrid.toggle()
    }

    // MARK: - Center Stage Control
    func toggleCenterStage() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            guard let device = self.frontCameraInput?.device else { return }

            // Check if Center Stage is available (requires iOS 14.5+)
            if #available(iOS 14.5, *) {
                // Center Stage is primarily available on iPad Pro with ultra-wide camera
                // Check if the device supports it
                do {
                    try device.lockForConfiguration()
                    defer { device.unlockForConfiguration() }

                    Task { @MainActor in
                        self.isCenterStageEnabled.toggle()
                    }

                    // Note: Center Stage is controlled via AVCaptureDevice.centerStageEnabled
                    // but it requires specific hardware support (typically iPad Pro)
                    // For iPhone, this may not be available
                } catch {
                    print("Error toggling Center Stage: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Quality Settings
    func setRecordingQuality(_ quality: RecordingQuality) {
        recordingQuality = quality
    }

    // MARK: - Recording Control
    func startRecording() async throws {
        print("🎥 startRecording called, current state: \(recordingState)")
        guard recordingState == .idle else {
            print("❌ Not idle, returning")
            return
        }

        // Check available disk space before starting
        guard hasEnoughDiskSpace() else {
            await MainActor.run {
                errorMessage = "Insufficient storage space. Please free up space and try again."
            }
            throw CameraError.insufficientStorage
        }

        await MainActor.run {
            recordingState = .recording
        }

        print("✅ State changed to recording")

        // Create output URLs
        let timestamp = Date().timeIntervalSince1970
        frontOutputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("front_\(timestamp).mov")
        backOutputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("back_\(timestamp).mov")
        combinedOutputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("combined_\(timestamp).mov")

        print("📁 Output URLs created:")
        print("  Front: \(frontOutputURL?.path ?? "nil")")
        print("  Back: \(backOutputURL?.path ?? "nil")")
        print("  Combined: \(combinedOutputURL?.path ?? "nil")")

        // Reset recording state
        isWriting = false
        recordingStartTime = nil
        hasReceivedFirstVideoFrame = false
        hasReceivedFirstAudioFrame = false
        
        // Reset writersConfigured before setup
        writersConfigured = false

        // Setup asset writers
        do {
            try setupAssetWriters()
            print("✅ Asset writers setup complete")
            writersConfigured = true
        } catch {
            print("❌ Asset writer setup failed: \(error)")
            await MainActor.run {
                recordingState = .idle
                errorMessage = error.localizedDescription
            }
            throw error
        }

        print("⏱️ Starting recording timer")
        // Start timer
        startRecordingTimer()
    }

    func stopRecording() async throws {
        guard recordingState == .recording else {
            print("⚠️ stopRecording called but not recording, state: \(recordingState)")
            return
        }

        print("🛑 Stopping recording...")

        await MainActor.run {
            recordingState = .processing
        }

        // Stop writing new samples
        isWriting = false

        // Finish writing
        do {
            try await finishWriting()
            print("✅ All writers finished successfully")
        } catch {
            print("❌ Error finishing writers: \(error)")
            await MainActor.run {
                errorMessage = "Failed to save recording: \(error.localizedDescription)"
                recordingState = .idle
                recordingDuration = 0
            }
            throw error
        }

        // Save to Photos library
        do {
            try await saveToPhotosLibrary()
            print("✅ Videos saved to Photos library")

            // Clean up temporary files after successful save
            cleanupTemporaryFiles()
        } catch {
            print("❌ Error saving to Photos library: \(error)")
            await MainActor.run {
                errorMessage = "Failed to save to Photos: \(error.localizedDescription)"
            }
            throw error
        }

        await MainActor.run {
            recordingState = .idle
            recordingDuration = 0
        }

        print("✅ Recording stopped successfully")
    }
    
    private func currentVideoTransform() -> CGAffineTransform {
        let orientation = UIDevice.current.orientation
        switch orientation {
        case .landscapeLeft:
            // Home button (or bottom) on the right
            return .identity
        case .landscapeRight:
            return CGAffineTransform(rotationAngle: .pi)
        case .portraitUpsideDown:
            return CGAffineTransform(rotationAngle: -.pi / 2)
        case .portrait:
            fallthrough
        default:
            return CGAffineTransform(rotationAngle: .pi / 2)
        }
    }

    private func setupAssetWriters() throws {
        // Front camera writer
        guard let frontURL = frontOutputURL else {
            throw CameraError.outputURLNotSet
        }

        frontAssetWriter = try AVAssetWriter(outputURL: frontURL, fileType: .mov)

        let dimensions = recordingQuality.dimensions
        let bitRate = recordingQuality.bitRate

        let frontVideoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: dimensions.width,
            AVVideoHeightKey: dimensions.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitRate
            ]
        ]

        frontVideoInput = AVAssetWriterInput(mediaType: .video, outputSettings: frontVideoSettings)
        frontVideoInput?.expectsMediaDataInRealTime = true

        if let frontVideoInput = frontVideoInput,
           let frontAssetWriter = frontAssetWriter,
           frontAssetWriter.canAdd(frontVideoInput) {
            frontAssetWriter.add(frontVideoInput)

            // Set portrait transform
            frontVideoInput.transform = currentVideoTransform()

            // Create pixel buffer adaptor for front
            frontPixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: frontVideoInput,
                sourcePixelBufferAttributes: [
                    kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange),
                    kCVPixelBufferWidthKey as String: dimensions.width,
                    kCVPixelBufferHeightKey as String: dimensions.height
                ]
            )
        }

        // Back camera writer
        guard let backURL = backOutputURL else {
            throw CameraError.outputURLNotSet
        }

        backAssetWriter = try AVAssetWriter(outputURL: backURL, fileType: .mov)

        backVideoInput = AVAssetWriterInput(mediaType: .video, outputSettings: frontVideoSettings)
        backVideoInput?.expectsMediaDataInRealTime = true

        if let backVideoInput = backVideoInput,
           let backAssetWriter = backAssetWriter,
           backAssetWriter.canAdd(backVideoInput) {
            backAssetWriter.add(backVideoInput)

            // Set portrait transform
            backVideoInput.transform = currentVideoTransform()

            // Create pixel buffer adaptor for back
            backPixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: backVideoInput,
                sourcePixelBufferAttributes: [
                    kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange),
                    kCVPixelBufferWidthKey as String: dimensions.width,
                    kCVPixelBufferHeightKey as String: dimensions.height
                ]
            )
        }

        // Combined writer (will use back camera video + audio)
        guard let combinedURL = combinedOutputURL else {
            throw CameraError.outputURLNotSet
        }

        combinedAssetWriter = try AVAssetWriter(outputURL: combinedURL, fileType: .mov)

        combinedVideoInput = AVAssetWriterInput(mediaType: .video, outputSettings: frontVideoSettings)
        combinedVideoInput?.expectsMediaDataInRealTime = true

        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVNumberOfChannelsKey: 2,
            AVSampleRateKey: 44100.0,
            AVEncoderBitRateKey: 128000
        ]

        combinedAudioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        combinedAudioInput?.expectsMediaDataInRealTime = true

        if let combinedVideoInput = combinedVideoInput,
           let combinedAudioInput = combinedAudioInput,
           let combinedAssetWriter = combinedAssetWriter {
            if combinedAssetWriter.canAdd(combinedVideoInput) {
                combinedAssetWriter.add(combinedVideoInput)

                // Set portrait transform
                combinedVideoInput.transform = currentVideoTransform()

                // Create pixel buffer adaptor for combined (uses back camera frames)
                combinedPixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
                    assetWriterInput: combinedVideoInput,
                    sourcePixelBufferAttributes: [
                        kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange),
                        kCVPixelBufferWidthKey as String: dimensions.width,
                        kCVPixelBufferHeightKey as String: dimensions.height
                    ]
                )
            }
            if combinedAssetWriter.canAdd(combinedAudioInput) {
                combinedAssetWriter.add(combinedAudioInput)
            }
        }
    }

    private func finishWriting() async throws {
        // Request background time to complete writing (prevents corruption if app is backgrounded)
        backgroundTaskID = await MainActor.run { () -> UIBackgroundTaskIdentifier in
            UIApplication.shared.beginBackgroundTask(withName: "FinishWriting") { [weak self] in
                print("⚠️ Background task expired - cleaning up")
                self?.endBackgroundTask()
            }
        }

        // Ensure cleanup happens even if there's an error
        defer {
            // Clean up all writer references
            frontAssetWriter = nil
            backAssetWriter = nil
            combinedAssetWriter = nil
            frontVideoInput = nil
            backVideoInput = nil
            combinedVideoInput = nil
            combinedAudioInput = nil

            frontPixelBufferAdaptor = nil
            backPixelBufferAdaptor = nil
            combinedPixelBufferAdaptor = nil
            
            writersConfigured = false

            print("✅ All writer references cleaned up")

            // End background task
            endBackgroundTask()
        }

        // Use task group for proper error handling
        try await withThrowingTaskGroup(of: Void.self) { group in
            // Finish front writer
            if let writer = frontAssetWriter {
                if writer.status == .writing {
                    group.addTask {
                        try await self.finishWriter(writer)
                    }
                } else if writer.status != .completed {
                    // Cancel if not writing and not completed
                    writer.cancelWriting()
                    print("⚠️ Front writer cancelled (status: \(writer.status.rawValue))")
                }
            }

            // Finish back writer
            if let writer = backAssetWriter {
                if writer.status == .writing {
                    group.addTask {
                        try await self.finishWriter(writer)
                    }
                } else if writer.status != .completed {
                    writer.cancelWriting()
                    print("⚠️ Back writer cancelled (status: \(writer.status.rawValue))")
                }
            }

            // Finish combined writer
            if let writer = combinedAssetWriter {
                if writer.status == .writing {
                    group.addTask {
                        try await self.finishWriter(writer)
                    }
                } else if writer.status != .completed {
                    writer.cancelWriting()
                    print("⚠️ Combined writer cancelled (status: \(writer.status.rawValue))")
                }
            }

            // Wait for all writers to finish
            try await group.waitForAll()
            print("✅ All writers finished successfully")
        }
    }

    nonisolated private func finishWriter(_ writer: AVAssetWriter) async throws {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            writer.finishWriting {
                cont.resume()
            }
        }
        if writer.status == .failed, let error = writer.error {
            print("❌ Writer failed during finish: \(error.localizedDescription)")
            throw error
        }
    }
    
    private func ensurePhotosAuthorization() async throws {
        if #available(iOS 14, *) {
            let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
            switch status {
            case .authorized, .limited:
                return
            case .notDetermined:
                let newStatus = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
                if newStatus == .authorized || newStatus == .limited { return }
                throw CameraError.photosNotAuthorized
            default:
                throw CameraError.photosNotAuthorized
            }
        } else {
            let status = PHPhotoLibrary.authorizationStatus()
            switch status {
            case .authorized:
                return
            case .notDetermined:
                let newStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
                if newStatus == .authorized { return }
                throw CameraError.photosNotAuthorized
            default:
                throw CameraError.photosNotAuthorized
            }
        }
    }

    private func saveToPhotosLibrary() async throws {
        try await ensurePhotosAuthorization()
        
        let urls = [
            (url: frontOutputURL, title: "DualLensPro - Front Camera"),
            (url: backOutputURL, title: "DualLensPro - Back Camera"),
            (url: combinedOutputURL, title: "DualLensPro - Combined")
        ].compactMap { $0.url != nil ? (url: $0.url!, title: $0.title) : nil }

        try await PHPhotoLibrary.shared().performChanges {
            for item in urls {
                let creationRequest = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: item.url)
                creationRequest?.creationDate = Date()

                // Add metadata
                // Note: Custom metadata requires additional setup with PHAssetResource
                // For now, we're setting creation date and the title will be in the filename
            }
        }

        // Notify UI to refresh gallery thumbnail
        await MainActor.run {
            NotificationCenter.default.post(name: .init("RefreshGalleryThumbnail"), object: nil)
        }
    }

    private func startRecordingTimer() {
        Task {
            // Use thread-safe lock to check recording state instead of accessing MainActor property
            while recordingStateLock.withLock({ $0 == .recording }) {
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                await MainActor.run {
                    recordingDuration += 0.1
                }
            }
        }
    }

    // MARK: - Camera Switching
    func switchCameras() {
        // Toggle the switched state
        isCamerasSwitched.toggle()

        // This property can be observed by the UI layer to swap preview positions
        // The actual camera feeds remain the same, just their display positions change
        print("📱 Cameras switched: \(isCamerasSwitched ? "Front on bottom" : "Front on top")")
    }

    // MARK: - Capture Mode Management
    private func applyCaptureMode() async {
        await withCheckedContinuation { continuation in
            sessionQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume()
                    return
                }

                // Update frame rate for both cameras
                self.updateFrameRate(for: self.frontCameraInput?.device, mode: self.captureMode)
                self.updateFrameRate(for: self.backCameraInput?.device, mode: self.captureMode)

                print("📹 Applied capture mode: \(self.captureMode.rawValue)")
                continuation.resume()
            }
        }
    }

    nonisolated private func updateFrameRate(for device: AVCaptureDevice?, mode: CaptureMode) {
        guard let device = device else { return }

        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }

            let targetFrameRate = mode.frameRate
            for range in device.activeFormat.videoSupportedFrameRateRanges {
                if range.maxFrameRate >= Double(targetFrameRate) {
                    device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: CMTimeScale(targetFrameRate))
                    device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: CMTimeScale(targetFrameRate))
                    print("  Set \(device.position == .front ? "front" : "back") camera to \(targetFrameRate)fps")
                    break
                }
            }
        } catch {
            print("Error updating frame rate: \(error.localizedDescription)")
        }
    }

    func setCaptureMode(_ mode: CaptureMode) {
        captureMode = mode
    }

    // MARK: - White Balance Control
    func setWhiteBalance(_ mode: WhiteBalanceMode) {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }

            // Apply to both cameras
            self.applyWhiteBalance(mode, to: self.frontCameraInput?.device)
            self.applyWhiteBalance(mode, to: self.backCameraInput?.device)
        }
    }

    nonisolated private func applyWhiteBalance(_ mode: WhiteBalanceMode, to device: AVCaptureDevice?) {
        guard let device = device else { return }

        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }

            if device.isWhiteBalanceModeSupported(mode.avWhiteBalanceMode) {
                device.whiteBalanceMode = mode.avWhiteBalanceMode
            }
        } catch {
            print("Error setting white balance: \(error.localizedDescription)")
        }
    }

    // MARK: - Video Stabilization Control
    func setVideoStabilization(_ mode: VideoStabilizationMode) {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }

            // Apply to video connections
            if let frontConnection = self.frontVideoOutput?.connection(with: .video) {
                if frontConnection.isVideoStabilizationSupported {
                    frontConnection.preferredVideoStabilizationMode = mode.avStabilizationMode
                }
            }

            if let backConnection = self.backVideoOutput?.connection(with: .video) {
                if backConnection.isVideoStabilizationSupported {
                    backConnection.preferredVideoStabilizationMode = mode.avStabilizationMode
                }
            }
        }
    }

    // MARK: - Pause/Resume Recording
    func pauseRecording() async {
        guard recordingState == .recording else { return }

        await MainActor.run {
            recordingState = .paused
        }

        // Stop writing samples but keep session running
        isWriting = false
    }

    func resumeRecording() async {
        guard recordingState == .paused else { return }

        await MainActor.run {
            recordingState = .recording
        }

        // Resume writing samples
        isWriting = true
    }

    // MARK: - Background Task Management
    private func endBackgroundTask() {
        if backgroundTaskID != .invalid {
            Task { @MainActor in
                UIApplication.shared.endBackgroundTask(self.backgroundTaskID)
                self.backgroundTaskID = .invalid
            }
        }
    }

    // MARK: - Disk Space Check
    private func hasEnoughDiskSpace() -> Bool {
        let fileManager = FileManager.default
        guard let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return false
        }

        do {
            let attributes = try fileManager.attributesOfFileSystem(forPath: documentsPath.path)
            if let freeSpace = attributes[.systemFreeSize] as? NSNumber {
                let freeSpaceInBytes = freeSpace.int64Value
                let minimumRequired: Int64 = 500_000_000 // 500 MB minimum
                let hasSpace = freeSpaceInBytes > minimumRequired
                print("💾 Free space: \(freeSpaceInBytes / 1_000_000) MB (required: 500 MB) - \(hasSpace ? "✅" : "❌")")
                return hasSpace
            }
        } catch {
            print("❌ Error checking disk space: \(error)")
        }

        return false
    }

    // MARK: - Video Sample Buffer Handler
    // Called on writerQueue - thread-safe access to writer state
    nonisolated private func handleVideoSampleBuffer(_ sampleBuffer: CMSampleBuffer, isFront: Bool, isBack: Bool) {
        // Start writing on first video frame
        if writersConfigured && !isWriting && !hasReceivedFirstVideoFrame {
            hasReceivedFirstVideoFrame = true
            print("🎬 Starting writers on first video frame")

            let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            recordingStartTime = timestamp

            var allWritersStarted = true

            // Start front writer with validation
            if let writer = frontAssetWriter, writer.status == .unknown {
                if writer.startWriting() {
                    writer.startSession(atSourceTime: timestamp)
                    print("  ✅ Front writer started")
                } else {
                    print("❌ Failed to start front writer: \(writer.error?.localizedDescription ?? "unknown")")
                    allWritersStarted = false
                }
            }

            // Start back writer with validation
            if let writer = backAssetWriter, writer.status == .unknown {
                if writer.startWriting() {
                    writer.startSession(atSourceTime: timestamp)
                    print("  ✅ Back writer started")
                } else {
                    print("❌ Failed to start back writer: \(writer.error?.localizedDescription ?? "unknown")")
                    allWritersStarted = false
                }
            }

            // Start combined writer with validation
            if let writer = combinedAssetWriter, writer.status == .unknown {
                if writer.startWriting() {
                    writer.startSession(atSourceTime: timestamp)
                    print("  ✅ Combined writer started")
                } else {
                    print("❌ Failed to start combined writer: \(writer.error?.localizedDescription ?? "unknown")")
                    allWritersStarted = false
                }
            }

            if allWritersStarted {
                isWriting = true
                print("✅ All writers started successfully")
            } else {
                if let w = frontAssetWriter, w.status == .writing { w.cancelWriting() }
                if let w = backAssetWriter, w.status == .writing { w.cancelWriting() }
                if let w = combinedAssetWriter, w.status == .writing { w.cancelWriting() }
                isWriting = false
                recordingStartTime = nil
                hasReceivedFirstVideoFrame = false
                hasReceivedFirstAudioFrame = false

                Task { @MainActor in
                    recordingState = .idle
                    errorMessage = "Failed to start recording - check available storage"
                }
                return
            }
        }

        guard writersConfigured else { return }
        
        guard isWriting, recordingStartTime != nil else {
            return
        }

        // Extract pixel buffer and timestamp
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            print("⚠️ No pixel buffer in sample")
            return
        }
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        if isFront {
            if let adaptor = frontPixelBufferAdaptor, let input = frontVideoInput, input.isReadyForMoreMediaData {
                if !adaptor.append(pixelBuffer, withPresentationTime: pts) {
                    print("⚠️ Failed to append front pixel buffer")
                    if let writer = frontAssetWriter, writer.status == .failed {
                        print("❌ Front writer failed: \(writer.error?.localizedDescription ?? "unknown error")")
                    }
                }
            }
        } else if isBack {
            if let adaptor = backPixelBufferAdaptor, let input = backVideoInput, input.isReadyForMoreMediaData {
                if !adaptor.append(pixelBuffer, withPresentationTime: pts) {
                    print("⚠️ Failed to append back pixel buffer")
                    if let writer = backAssetWriter, writer.status == .failed {
                        print("❌ Back writer failed: \(writer.error?.localizedDescription ?? "unknown error")")
                    }
                }
            }

            // Also append to combined output (using back camera video)
            if let adaptor = combinedPixelBufferAdaptor, let input = combinedVideoInput, input.isReadyForMoreMediaData {
                if !adaptor.append(pixelBuffer, withPresentationTime: pts) {
                    print("⚠️ Failed to append to combined pixel buffer")
                    if let writer = combinedAssetWriter, writer.status == .failed {
                        print("❌ Combined writer failed: \(writer.error?.localizedDescription ?? "unknown error")")
                    }
                }
            }
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate & AVCaptureAudioDataOutputSampleBufferDelegate
extension DualCameraManager: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard CMSampleBufferDataIsReady(sampleBuffer) else {
            print("⚠️ Sample buffer not ready")
            return
        }

        // Thread-safe check of recording state
        let currentState = recordingStateLock.withLock { $0 }
        guard currentState == .recording else {
            return
        }

        // Determine source characteristics on this thread to avoid capturing non-Sendable types
        let isAudioOutput = (output is AVCaptureAudioDataOutput)
        let isFront = (frontVideoOutput != nil) && (output === frontVideoOutput!)
        let isBack = (backVideoOutput != nil) && (output === backVideoOutput!)

        // Box the sample buffer so we can pass it across the @Sendable closure safely in Swift 6
        let box = SampleBufferBox(sampleBuffer)

        // Dispatch to writerQueue for thread-safe writer access
        writerQueue.async { [weak self, box, isAudioOutput, isFront, isBack] in
            guard let self = self else { return }
            let sampleBuffer = box.buffer

            // Handle audio output
            if isAudioOutput {
                self.handleAudioSampleBuffer(sampleBuffer)
                return
            }

            // Handle video output
            self.handleVideoSampleBuffer(sampleBuffer, isFront: isFront, isBack: isBack)
        }
    }

    // Called on writerQueue - thread-safe access to writer state
    nonisolated private func handleAudioSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        // Start writers on first audio sample if not started yet
        if !isWriting && !hasReceivedFirstAudioFrame {
            hasReceivedFirstAudioFrame = true
            // Don't start yet, wait for video frame
            return
        }

        guard isWriting, recordingStartTime != nil else {
            return
        }

        // Append audio to combined output
        if let input = combinedAudioInput, input.isReadyForMoreMediaData {
            if !input.append(sampleBuffer) {
                print("⚠️ Failed to append audio sample")
                if let writer = combinedAssetWriter, writer.status == .failed {
                    print("❌ Combined writer failed: \(writer.error?.localizedDescription ?? "unknown error")")
                }
            }
        }
    }
}

// MARK: - Errors
enum CameraError: LocalizedError {
    case multiCamNotSupported
    case deviceNotFound(AVCaptureDevice.Position)
    case cannotAddInput(AVCaptureDevice.Position)
    case cannotAddOutput(AVCaptureDevice.Position)
    case cannotAddPhotoOutput(AVCaptureDevice.Position)
    case cannotCreateConnection(AVCaptureDevice.Position)
    case cannotAddConnection(AVCaptureDevice.Position)
    case cannotAddPhotoConnection(AVCaptureDevice.Position)
    case audioDeviceNotFound
    case cannotAddAudioInput
    case cannotAddAudioOutput
    case outputURLNotSet
    case photoOutputNotConfigured
    case photoSaveTimeout
    case insufficientStorage
    case photosNotAuthorized

    var errorDescription: String? {
        switch self {
        case .multiCamNotSupported:
            return "Multi-camera recording is not supported on this device"
        case .deviceNotFound(let position):
            return "Camera not found for position: \(position)"
        case .cannotAddInput(let position):
            return "Cannot add camera input for position: \(position)"
        case .cannotAddOutput(let position):
            return "Cannot add video output for position: \(position)"
        case .cannotAddPhotoOutput(let position):
            return "Cannot add photo output for position: \(position)"
        case .cannotCreateConnection(let position):
            return "Cannot create video connection for position: \(position)"
        case .cannotAddConnection(let position):
            return "Cannot add video connection for position: \(position)"
        case .cannotAddPhotoConnection(let position):
            return "Cannot add photo connection for position: \(position)"
        case .audioDeviceNotFound:
            return "Audio device not found"
        case .cannotAddAudioInput:
            return "Cannot add audio input"
        case .cannotAddAudioOutput:
            return "Cannot add audio output"
        case .outputURLNotSet:
            return "Output URL not set"
        case .photoOutputNotConfigured:
            return "Photo output is not configured"
        case .photoSaveTimeout:
            return "Photo save timed out - check Photos permissions"
        case .insufficientStorage:
            return "Insufficient storage space available"
        case .photosNotAuthorized:
            return "Photos access is not authorized. Enable access in Settings to save recordings."
        }
    }
}

// MARK: - Recording Quality
enum RecordingQuality: String, CaseIterable, Sendable {
    case low = "Low (720p)"
    case medium = "Medium (1080p)"
    case high = "High (1080p 60fps)"
    case ultra = "Ultra (4K)"

    var dimensions: (width: Int, height: Int) {
        switch self {
        case .low:
            return (1280, 720)
        case .medium, .high:
            return (1920, 1080)
        case .ultra:
            return (3840, 2160)
        }
    }

    var bitRate: Int {
        switch self {
        case .low:
            return 3_000_000
        case .medium:
            return 6_000_000
        case .high:
            return 10_000_000
        case .ultra:
            return 20_000_000
        }
    }
}

// MARK: - Photo Capture Delegate
private class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    // Protect continuation from being resumed more than once (timeout + completion race)
    private let continuationLock = OSAllocatedUnfairLock<CheckedContinuation<Void, Error>?>(initialState: nil)
    private let cameraName: String
    private let onComplete: () -> Void

    init(continuation: CheckedContinuation<Void, Error>, camera: String, onComplete: @escaping () -> Void) {
        self.cameraName = camera
        self.onComplete = onComplete
        super.init()
        continuationLock.withLock { $0 = continuation }
    }

    private func resumeOnce(_ result: Result<Void, Error>) {
        let cont: CheckedContinuation<Void, Error>? = continuationLock.withLock { locked in
            let c = locked
            locked = nil
            return c
        }
        guard let continuation = cont else {
            print("⚠️ [PhotoCaptureDelegate] Continuation already resumed for \(cameraName)")
            return
        }
        switch result {
        case .success:
            continuation.resume()
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        defer { onComplete() }  // Always clean up delegate after resuming

        if let error = error {
            resumeOnce(.failure(error))
            return
        }

        guard let imageData = photo.fileDataRepresentation() else {
            resumeOnce(.failure(CameraError.photoOutputNotConfigured))
            return
        }

        // Add timeout protection to prevent hanging (10 seconds)
        let timeoutTask = Task {
            try? await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
            self.resumeOnce(.failure(CameraError.photoSaveTimeout))
        }

        // Save to Photos library
        PHPhotoLibrary.shared().performChanges({
            let creationRequest = PHAssetCreationRequest.forAsset()
            creationRequest.addResource(with: .photo, data: imageData, options: nil)
        }) { success, error in
            timeoutTask.cancel()  // Cancel timeout if we complete in time

            if let error = error {
                self.resumeOnce(.failure(error))
            } else if success {
                // Notify UI to refresh gallery thumbnail
                Task { @MainActor in
                    NotificationCenter.default.post(name: .init("RefreshGalleryThumbnail"), object: nil)
                }
                self.resumeOnce(.success(()))
            } else {
                self.resumeOnce(.failure(CameraError.photoOutputNotConfigured))
            }
        }
    }
}

