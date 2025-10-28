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
class DualCameraManager: NSObject, ObservableObject /* TODO: Add DeviceMonitorDelegate after adding DeviceMonitorService.swift to Xcode project */ {
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

    // Sendable wrappers for passing media buffers safely across actor boundaries in Swift 6
    private final class SampleBufferBox: @unchecked Sendable {
        let buffer: CMSampleBuffer
        init(_ buffer: CMSampleBuffer) { self.buffer = buffer }
    }

    private final class PixelBufferBox: @unchecked Sendable {
        let buffer: CVPixelBuffer
        let time: CMTime
        init(_ buffer: CVPixelBuffer, time: CMTime) {
            self.buffer = buffer
            self.time = time
        }
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
    nonisolated(unsafe) private var frontPhotoOutput: AVCapturePhotoOutput?
    nonisolated(unsafe) private var backPhotoOutput: AVCapturePhotoOutput?

    // Photo capture delegate storage (thread-safe access)
    private let photoDelegateQueue = DispatchQueue(label: "com.duallens.photoDelegates")
    nonisolated(unsafe) private var _activePhotoDelegates: [String: PhotoCaptureDelegate] = [:]

    // Photo data cache for combined photo creation
    nonisolated(unsafe) private var lastFrontPhotoData: Data?
    nonisolated(unsafe) private var lastBackPhotoData: Data?

    // MARK: - Preview Layers
    nonisolated(unsafe) var frontPreviewLayer: AVCaptureVideoPreviewLayer?
    nonisolated(unsafe) var backPreviewLayer: AVCaptureVideoPreviewLayer?

    // MARK: - Recording (Thread-Safe Actor-Based)
    // RecordingCoordinator provides thread-safe access to all AVAssetWriter objects
    nonisolated(unsafe) private var recordingCoordinator: RecordingCoordinator?

    // Track pending frame append tasks to ensure they complete before finishing
    private let pendingTasksLock = OSAllocatedUnfairLock<Set<UUID>>(initialState: [])

    // Background task support
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

    // URLs for recording output (nonisolated for access from various contexts)
    nonisolated(unsafe) private var frontOutputURL: URL?
    nonisolated(unsafe) private var backOutputURL: URL?
    nonisolated(unsafe) private var combinedOutputURL: URL?

    // Recording state tracking (nonisolated for access from delegate callbacks)
    nonisolated(unsafe) private var recordingStartTime: CMTime?
    nonisolated(unsafe) private var isWriting = false
    nonisolated(unsafe) private var hasReceivedFirstVideoFrame = false
    nonisolated(unsafe) private var hasReceivedFirstAudioFrame = false

    nonisolated(unsafe) private var lastVideoPTS: CMTime?
    nonisolated(unsafe) private var lastAudioPTS: CMTime?
    nonisolated(unsafe) private var dropAudioDuringStop = false

    // ✅ FIX Issue #10: Frame dropping for backpressure
    nonisolated(unsafe) private var lastProcessedFrameTime: [CameraPosition: CMTime] = [:]
    private let minimumFrameInterval: Double = 1.0 / 60.0  // Max 60fps processing

    // MARK: - Dispatch Queues
    private let sessionQueue = DispatchQueue(label: "com.duallens.sessionQueue")
    private let videoQueue = DispatchQueue(label: "com.duallens.videoQueue")
    private let audioQueue = DispatchQueue(label: "com.duallens.audioQueue")
    // Serial queue for ALL AVAssetWriter operations (thread-safe writer access)
    private let writerQueue = DispatchQueue(label: "com.duallens.writerQueue")

    // MARK: - Recording Quality
    nonisolated(unsafe) var recordingQuality: RecordingQuality = .high

    // ✅ FIX Issue #13: Background audio configuration
    // Using backing storage to allow access from nonisolated contexts
    @Published var allowBackgroundAudio: Bool = false {
        didSet {
            _allowBackgroundAudioUnsafe = allowBackgroundAudio
            if isSessionRunning {
                Task {
                    try? await reconfigureAudioSession()
                }
            }
        }
    }
    private nonisolated(unsafe) var _allowBackgroundAudioUnsafe: Bool = false

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

    // MARK: - Setup Protection (Issue #5)
    // ✅ FIX Issue #1: Use OSAllocatedUnfairLock instead of NSLock (Swift 6 async-safe)
    private let setupLock = OSAllocatedUnfairLock<Bool>(initialState: false)

    // MARK: - Stop Protection (Issue #9)
    // ✅ FIX Issue #1: Use OSAllocatedUnfairLock instead of NSLock (Swift 6 async-safe)
    private let stopLock = OSAllocatedUnfairLock<Bool>(initialState: false)

    // ✅ FIX Issue #7: Use backing storage to separate internal vs external updates
    nonisolated(unsafe) private var _frontZoomFactor: CGFloat = 1.0
    nonisolated(unsafe) private var _backZoomFactor: CGFloat = 1.0

    var frontZoomFactor: CGFloat {
        get { _frontZoomFactor }
        set {
            let oldValue = _frontZoomFactor
            _frontZoomFactor = newValue

            // ✅ CRITICAL ZOOM FIX: Use centralized validation method
            // Only trigger update if session is ready and value changed
            guard isCameraSetupComplete, oldValue != newValue else { return }

            applyValidatedZoom(for: .front, factor: newValue)
        }
    }

    var backZoomFactor: CGFloat {
        get { _backZoomFactor }
        set {
            let oldValue = _backZoomFactor
            _backZoomFactor = newValue

            // ✅ CRITICAL ZOOM FIX: Use centralized validation method
            // Only trigger update if session is ready and value changed
            guard isCameraSetupComplete, oldValue != newValue else { return }

            applyValidatedZoom(for: .back, factor: newValue)
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

        // Device orientation changes for video orientation updates
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(deviceOrientationDidChange),
            name: UIDevice.orientationDidChangeNotification,
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
        print("⚠️ Session runtime error: \(description)")

        // Only handle critical errors that require session recreation
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
            // Log non-critical errors but don't show to user or stop session
            print("⚠️ Non-critical session error (continuing): \(description)")
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

    // ✅ FIX Issue #13: Enhanced audio session configuration with background audio handling
    nonisolated private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()

        // Deactivate first to clear any previous configuration
        try? session.setActive(false, options: .notifyOthersOnDeactivation)

        // Check if other audio is playing
        let isOtherAudioPlaying = session.isOtherAudioPlaying
        print("🔊 Other audio playing: \(isOtherAudioPlaying)")

        // Build audio session options
        var options: AVAudioSession.CategoryOptions = [
            .defaultToSpeaker,
            .allowBluetoothA2DP,  // High quality Bluetooth (stereo output)
            .allowBluetoothHFP,   // Hands-Free Profile for headset mics
            .allowAirPlay
        ]

        if _allowBackgroundAudioUnsafe {
            options.insert(.mixWithOthers)  // Allow background audio to continue
            print("🔊 Audio mode: Mix with background audio")
        } else {
            options.insert(.duckOthers)     // Lower background audio volume
            print("🔊 Audio mode: Duck background audio")
        }

        // Configure for video recording
        try session.setCategory(
            .playAndRecord,
            mode: .videoRecording,
            options: options
        )

        // Set preferred sample rate and IO buffer duration for better quality
        try? session.setPreferredSampleRate(48000.0)
        try? session.setPreferredIOBufferDuration(0.005)  // 5ms latency

        // Activate the session
        try session.setActive(true, options: [.notifyOthersOnDeactivation])

        print("🔊 AVAudioSession configured:")
        print("   - Sample rate: \(session.sampleRate) Hz")
        print("   - Buffer duration: \(session.ioBufferDuration)s")
        print("   - Background audio: \(_allowBackgroundAudioUnsafe ? "allowed" : "ducked")")
    }

    // Helper to reconfigure audio session (can be called from MainActor)
    private func reconfigureAudioSession() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionQueue.async {
                do {
                    try self.configureAudioSession()
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
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
        // ✅ FIX Issue #5: Protect against concurrent setupSession() calls
        let canProceed = setupLock.withLock { isSettingUp in
            guard !isSettingUp else {
                return false
            }
            isSettingUp = true
            return true
        }

        guard canProceed else {
            print("⚠️ setupSession already in progress - skipping duplicate call")
            throw CameraError.setupInProgress
        }

        defer {
            setupLock.withLock { isSettingUp in
                isSettingUp = false
            }
        }

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

        // ✅ FIX Issue #7: Sync zoom factors with actual camera minimums (use backing storage to avoid didSet)
        if let frontDevice = frontCameraInput?.device {
            _frontZoomFactor = frontDevice.minAvailableVideoZoomFactor
            print("📸 Front camera zoom synced to min: \(_frontZoomFactor)x for widest FOV")
        }
        if let backDevice = backCameraInput?.device {
            _backZoomFactor = backDevice.minAvailableVideoZoomFactor
            print("📸 Back camera zoom synced to min: \(_backZoomFactor)x")
        }

        // ✅ CRITICAL ZOOM FIX: Device zoom ranges are now available - log them for debugging
        if let fd = frontCameraInput?.device, let bd = backCameraInput?.device {
            print("📊 Device zoom capabilities ready - front: \(fd.minAvailableVideoZoomFactor)x-\(fd.maxAvailableVideoZoomFactor)x, back: \(bd.minAvailableVideoZoomFactor)x-\(bd.maxAvailableVideoZoomFactor)x")
        }

        // Mark camera setup as complete - now safe to update zoom and other camera properties
        isCameraSetupComplete = true
        print("✅ Camera setup complete - zoom updates now enabled (will apply after session starts)")
    }

    private func setupCamera(position: AVCaptureDevice.Position) async throws {
        // Find camera device
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else {
            throw CameraError.deviceNotFound(position)
        }

        // Configure camera device for optimal recording
        try camera.lockForConfiguration()
        defer { camera.unlockForConfiguration() }

        // For front camera, set to minimum zoom for widest field of view
        if position == .front {
            camera.videoZoomFactor = camera.minAvailableVideoZoomFactor
            print("📸 Front camera set to \(camera.minAvailableVideoZoomFactor)x (min zoom for widest FOV)")
        }

        // Enable HDR video if supported
        if camera.activeFormat.isVideoHDRSupported {
            camera.automaticallyAdjustsVideoHDREnabled = true
        }

        // ✅ FIX Issue #8: Set frame rate with device capability verification
        try await configureFrameRate(for: camera, mode: captureMode)

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

        // ✅ FIX Issue #6: Query device capabilities for pixel format instead of hardcoding
        configureVideoOutput(videoOutput)

        if useMultiCam {
            // For multi-cam sessions, use addOutputWithNoConnections
            // Don't check canAddOutput for multi-cam
            multiCamSession.addOutputWithNoConnections(videoOutput)
            print("✅ Added video output with no connections for \(position == .front ? "front" : "back") camera")
            print("📸 Using device type: \(camera.deviceType.rawValue) for video output")

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
            let angle = videoRotationAngle()
            if videoConnection.isVideoRotationAngleSupported(angle) {
                videoConnection.videoRotationAngle = angle
            }
            if videoConnection.isVideoStabilizationSupported {
                videoConnection.preferredVideoStabilizationMode = .auto
            }
            if videoConnection.isVideoMirroringSupported && position == .front {
                videoConnection.isVideoMirrored = true
            }
            let positionName = position == .front ? "front" : "back"
            print("✅ Set video rotation angle to \(angle)° for \(positionName) camera")
        } else {
            // For single-cam sessions, check and add normally
            guard singleCamSession.canAddOutput(videoOutput) else {
                throw CameraError.cannotAddOutput(position)
            }
            singleCamSession.addOutput(videoOutput)
            print("✅ Added video output for \(position == .front ? "front" : "back") camera (single-cam mode)")

            // Configure connection
            if let connection = videoOutput.connection(with: .video) {
                let angle = videoRotationAngle()
                if connection.isVideoRotationAngleSupported(angle) {
                    connection.videoRotationAngle = angle
                }
                if connection.isVideoStabilizationSupported {
                    connection.preferredVideoStabilizationMode = .auto
                }
                if connection.isVideoMirroringSupported && position == .front {
                    connection.isVideoMirrored = true
                }
                let positionName = position == .front ? "front" : "back"
                print("✅ Set video rotation angle to \(angle)° for \(positionName) camera (single-cam)")
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

    // ✅ FIX Issue #6: Configure video output with device capability query
    private func configureVideoOutput(_ output: AVCaptureVideoDataOutput) {
        let availableFormats = output.availableVideoPixelFormatTypes

        // Preferred formats in priority order
        let preferredFormats: [OSType] = [
            kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,  // Most efficient for video
            kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
            kCVPixelFormatType_32BGRA  // Fallback
        ]

        // Find first supported format
        let selectedFormat = preferredFormats.first { format in
            availableFormats.contains(format)
        } ?? availableFormats.first ?? kCVPixelFormatType_32BGRA

        let videoSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: selectedFormat
        ]

        output.videoSettings = videoSettings

        print("📹 Selected pixel format: \(selectedFormat) (0x\(String(format: "%X", selectedFormat)))")
        print("📹 Available formats: \(availableFormats.map { "0x\(String(format: "%X", $0))" })")
    }

    // ✅ FIX Issue #8: Configure frame rate with device capability verification
    private func configureFrameRate(for camera: AVCaptureDevice, mode: CaptureMode) async throws {
        let targetFrameRate = mode.frameRate
        var actualFrameRate = 30  // Safe default
        var foundSupport = false

        // Try to find exact match or best alternative
        for range in camera.activeFormat.videoSupportedFrameRateRanges {
            if range.maxFrameRate >= Double(targetFrameRate) &&
               range.minFrameRate <= Double(targetFrameRate) {
                // Exact support found
                actualFrameRate = targetFrameRate
                foundSupport = true
                break
            } else if range.maxFrameRate > Double(actualFrameRate) {
                // Track highest supported rate as fallback
                actualFrameRate = Int(range.maxFrameRate)
            }
        }

        // Configure with actual supported frame rate
        camera.activeVideoMinFrameDuration = CMTime(value: 1, timescale: CMTimeScale(actualFrameRate))
        camera.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: CMTimeScale(actualFrameRate))

        if !foundSupport {
            print("⚠️ \(mode.displayName) requested \(targetFrameRate)fps but device max is \(actualFrameRate)fps")

            // Update error message for user
            await MainActor.run {
                errorMessage = "This device supports up to \(actualFrameRate)fps"
            }
        } else {
            print("✅ Frame rate set to \(actualFrameRate)fps for \(mode.displayName)")
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

    // Removed: duplicate videoRotationAngle() - see nonisolated version in Orientation Helpers section

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
                // ✅ FIX Issue #12: Use dynamic rotation angle based on current orientation
                let angle = videoRotationAngle()
                if frontConnection.isVideoRotationAngleSupported(angle) {
                    frontConnection.videoRotationAngle = angle
                }
                if frontConnection.isVideoMirroringSupported {
                    frontConnection.automaticallyAdjustsVideoMirroring = false
                    frontConnection.isVideoMirrored = true
                }
                if multiCamSession.canAddConnection(frontConnection) {
                    multiCamSession.addConnection(frontConnection)
                    print("✅ Added front preview layer connection with rotation: \(angle)°")
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
                // ✅ FIX Issue #12: Use dynamic rotation angle based on current orientation
                let angle = videoRotationAngle()
                if backConnection.isVideoRotationAngleSupported(angle) {
                    backConnection.videoRotationAngle = angle
                }
                if multiCamSession.canAddConnection(backConnection) {
                    multiCamSession.addConnection(backConnection)
                    print("✅ Added back preview layer connection with rotation: \(angle)°")
                }
            }
            backPreviewLayer = backLayer

        } else {
            // For single-cam sessions, use regular session initialization
            let backLayer = AVCaptureVideoPreviewLayer(session: singleCamSession)
            backLayer.videoGravity = .resizeAspectFill
            if let connection = backLayer.connection {
                // ✅ FIX Issue #12: Use dynamic rotation angle based on current orientation
                let angle = videoRotationAngle()
                if connection.isVideoRotationAngleSupported(angle) {
                    connection.videoRotationAngle = angle
                }
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

            Task { @MainActor in
                if !self.activeSession.isRunning {
                    self.activeSession.startRunning()
                    self.isSessionRunning = self.activeSession.isRunning
                    print("✅ Session started (\(self.useMultiCam ? "multi-cam" : "single-cam") mode)")

                    // ✅ CRITICAL ZOOM FIX: Use state-based zoom application instead of arbitrary delay
                    // This waits for session to actually be running before applying zoom
                    if self.isCameraSetupComplete {
                        self.applyInitialZoom()
                    }
                }
            }
        }
    }

    func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }

            Task { @MainActor in
                if self.activeSession.isRunning {
                    self.activeSession.stopRunning()
                    self.isSessionRunning = false
                    print("🛑 Session stopped")
                }
            }
        }
    }

    // MARK: - Zoom Control
    // Helper to apply zoom when already on sessionQueue
    nonisolated private func applyZoomDirectly(for position: CameraPosition, factor: CGFloat) {
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

        guard device.isConnected else {
            print("⚠️ Device not connected")
            return
        }

        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }

            let clampedFactor = min(max(factor, device.minAvailableVideoZoomFactor), device.maxAvailableVideoZoomFactor)
            device.videoZoomFactor = clampedFactor
            print("✅ Applied zoom \(clampedFactor)x to \(position == .front ? "front" : "back") camera")
        } catch {
            print("❌ Error setting zoom: \(error.localizedDescription)")
        }
    }

    // ✅ CRITICAL ZOOM FIX: Wait for session to ACTUALLY be running instead of guessing with arbitrary delay
    // This replaces the buggy 0.5s delay approach that caused zoom to be stuck at 1.0x
    @MainActor
    private func applyInitialZoom() {
        let frontZoom = self.frontZoomFactor
        let backZoom = self.backZoomFactor
        let useMulti = self.useMultiCam

        Task {
            // Wait for session to confirm it's running (max 3 seconds)
            var iterations = 0
            var isRunning = await MainActor.run { self.activeSession.isRunning }
            while !isRunning && iterations < 300 {
                try? await Task.sleep(nanoseconds: 10_000_000)  // 10ms
                iterations += 1
                isRunning = await MainActor.run { self.activeSession.isRunning }
            }

            if isRunning {
                print("✅ Session confirmed running after \(iterations * 10)ms, applying initial zoom")
                await MainActor.run {
                    self.applyZoomDirectly(for: .front, factor: frontZoom)
                    if useMulti {
                        self.applyZoomDirectly(for: .back, factor: backZoom)
                    }
                }
            } else {
                print("❌ Session did not start within 3 second timeout, zoom not applied")
            }
        }
    }

    // ✅ CRITICAL ZOOM FIX: Centralized zoom validation - single source of truth for zoom application
    // This method includes comprehensive validation: session running, device availability, connection, and range clamping
    // Replaces multiple inconsistent zoom code paths (updateZoomSafely, updateZoom, applyZoomDirectly)
    private func applyValidatedZoom(for position: CameraPosition, factor: CGFloat) {
        Task { @MainActor in
            let isRunning = self.activeSession.isRunning

            self.sessionQueue.async { [weak self] in
                guard let self = self else { return }

                // Validation 1: Session running
                guard isRunning else {
                    print("⚠️ Cannot zoom \(position): session not running")
                    return
                }

                // Validation 2: Get device
                let device: AVCaptureDevice?
                switch position {
                case .front:
                    device = self.frontCameraInput?.device
                case .back:
                    device = self.backCameraInput?.device
                }

                guard let device = device else {
                    print("⚠️ Cannot zoom \(position): device not available")
                    return
                }

                // Validation 3: Device connected
                guard device.isConnected else {
                    print("⚠️ Cannot zoom \(position): device not connected")
                    return
                }

                // Validation 4: Clamp to device capabilities
                let minZoom = device.minAvailableVideoZoomFactor
                let maxZoom = device.maxAvailableVideoZoomFactor
                let clampedFactor = min(max(factor, minZoom), maxZoom)

                // Apply zoom with device lock
                do {
                    try device.lockForConfiguration()
                    device.videoZoomFactor = clampedFactor
                    device.unlockForConfiguration()

                    print("✅ Zoom applied: \(position) = \(String(format: "%.2f", clampedFactor))x (requested: \(String(format: "%.2f", factor))x)")
                } catch {
                    print("❌ Failed to apply zoom to \(position): \(error.localizedDescription)")
                }
            }
        }
    }

    // ✅ FIX Issue #7: Safe async zoom update
    private func updateZoomSafely(for position: CameraPosition, factor: CGFloat) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            sessionQueue.async { [weak self] in
                defer { continuation.resume() }

                guard let self = self else { return }

                let device: AVCaptureDevice?
                switch position {
                case .front:
                    device = self.frontCameraInput?.device
                case .back:
                    device = self.backCameraInput?.device
                }

                guard let device = device else {
                    print("⚠️ No device for \(position) camera")
                    return
                }

                do {
                    try device.lockForConfiguration()
                    defer { device.unlockForConfiguration() }

                    let clampedFactor = min(max(factor, device.minAvailableVideoZoomFactor),
                                           device.maxAvailableVideoZoomFactor)
                    device.videoZoomFactor = clampedFactor

                    print("✅ \(position) zoom set to \(clampedFactor)x")
                } catch {
                    print("❌ Failed to set \(position) zoom: \(error)")
                }
            }
        }
    }

    private func updateZoom(for position: CameraPosition, factor: CGFloat) {
        Task { @MainActor in
            let isRunning = self.activeSession.isRunning

            self.sessionQueue.async { [weak self] in
                guard let self = self else { return }

                // Check if session is running
                guard isRunning else {
                    print("⚠️ Cannot update zoom - session not running")
                    return
                }

                self.applyZoomDirectly(for: position, factor: factor)
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
            ) { [weak self] data in
                // Cache photo data for combined photo
                self?.lastFrontPhotoData = data
                // Try to create combined photo if we have both
                Task {
                    await self?.trySaveCombinedPhotoIfReady()
                }
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
            ) { [weak self] data in
                // Cache photo data for combined photo
                self?.lastBackPhotoData = data
                // Try to create combined photo if we have both
                Task {
                    await self?.trySaveCombinedPhotoIfReady()
                }
                // Thread-safe cleanup of delegate
                self?.removePhotoDelegate(for: delegateId)
            }
            addPhotoDelegate(delegate, for: delegateId)
            photoOutput.capturePhoto(with: settings, delegate: delegate)
        }
    }

    // MARK: - Combined Photo

    @MainActor
    private func trySaveCombinedPhotoIfReady() async {
        guard let frontData = lastFrontPhotoData,
              let backData = lastBackPhotoData else {
            return  // Wait for both photos
        }

        print("📸 Both photos captured - creating combined photo...")

        do {
            try await saveCombinedPhoto(frontData: frontData, backData: backData)
            print("✅ Combined photo saved successfully")
        } catch {
            print("❌ Failed to save combined photo: \(error.localizedDescription)")
            errorMessage = "Failed to save combined photo: \(error.localizedDescription)"
        }

        // Clear cached data
        lastFrontPhotoData = nil
        lastBackPhotoData = nil
    }

    private func saveCombinedPhoto(frontData: Data, backData: Data) async throws {
        print("📸 Creating stacked combined photo...")

        guard let frontImage = CIImage(data: frontData),
              let backImage = CIImage(data: backData) else {
            throw CameraError.photoOutputNotConfigured
        }

        // Calculate dimensions for stacking
        let frontExtent = frontImage.extent
        let backExtent = backImage.extent
        let maxWidth = max(frontExtent.width, backExtent.width)
        let totalHeight = frontExtent.height + backExtent.height

        // Position front on top, back on bottom
        let frontPositioned = frontImage.transformed(by: CGAffineTransform(translationX: 0, y: backExtent.height))
        let backPositioned = backImage

        // Composite: front over back
        let composed = frontPositioned.composited(over: backPositioned)

        // Render to HEIF data
        let context = CIContext()
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let heifData = context.heifRepresentation(of: composed, format: .RGBA8, colorSpace: colorSpace) else {
            throw CameraError.photoOutputNotConfigured
        }

        print("📸 Composed image size: \(maxWidth)x\(totalHeight), data size: \(heifData.count) bytes")

        // Save to Photos library
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges({
                let req = PHAssetCreationRequest.forAsset()
                req.addResource(with: .photo, data: heifData, options: nil)
            }) { success, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if success {
                    print("✅ Combined photo saved to Photos library")
                    // Notify UI to refresh gallery
                    Task { @MainActor in
                        NotificationCenter.default.post(name: .init("RefreshGalleryThumbnail"), object: nil)
                    }
                    continuation.resume()
                } else {
                    continuation.resume(throwing: CameraError.failedToSaveToPhotos)
                }
            }
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
        Task { @MainActor in
            let currentLockState = self.isFocusLocked

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

                        // Use captured focus lock state
                        let focusLockMode: AVCaptureDevice.FocusMode = currentLockState ? .continuousAutoFocus : .locked

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

        // Clear any pending tasks from previous recording
        pendingTasksLock.withLock { $0.removeAll() }

        // Check available disk space before starting
        guard hasEnoughDiskSpace() else {
            await MainActor.run {
                errorMessage = "Insufficient storage space. Please free up space and try again."
            }
            throw CameraError.insufficientStorage
        }

        await MainActor.run {
            recordingState = .recording
            recordingDuration = 0  // ✅ Reset timer to 0 when starting
        }

        print("✅ State changed to recording, timer reset to 0")

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
        
        lastVideoPTS = nil
        lastAudioPTS = nil
        dropAudioDuringStop = false

        // Setup asset writers (async with coordinator)
        do {
            try await setupAssetWriters()
            print("✅ Asset writers setup complete")
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
        // ✅ FIX Issue #9: Atomic check-and-set for stopping state
        // Check recording state first (MainActor property)
        guard recordingState == .recording else {
            print("⚠️ stopRecording called but not recording")
            return
        }

        // Then check stopping flag with lock
        let canProceed = stopLock.withLock { isStopping in
            guard !isStopping else {
                return false
            }
            isStopping = true
            return true
        }

        guard canProceed else {
            print("⚠️ stopRecording already in progress")
            return
        }

        defer {
            stopLock.withLock { isStopping in
                isStopping = false
            }
        }

        print("🛑 Stopping recording...")

        // ✅ CRITICAL FIX: Stop accepting NEW frames immediately to prevent buffer buildup
        isWriting = false
        print("✅ Stopped accepting new frames immediately")

        // ✅ Keep recording state as .recording during flush window so pending frames can still append
        // ✅ INCREASED from 0.5s to 1.0s for more reliable frame flushing (especially for 4K, thermal throttling)
        print("⏳ Flushing pending frames for 1.0s...")
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1.0 seconds

        // ✅ CRITICAL: Wait for ALL pending frame append tasks to complete BEFORE stopping audio
        print("⏳ Waiting for pending frame tasks to complete...")
        var pendingCount = pendingTasksLock.withLock { $0.count }
        var iterations = 0

        while pendingCount > 0 && iterations < 200 { // Max 2 seconds wait (200 * 10ms)
            try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
            pendingCount = pendingTasksLock.withLock { $0.count }
            iterations += 1

            if iterations % 20 == 0 { // Log every 200ms
                print("   Still waiting... \(pendingCount) tasks pending (iteration \(iterations))")
            }
        }

        if pendingCount > 0 {
            print("⚠️ Timeout waiting for tasks - \(pendingCount) tasks still pending")
        } else {
            print("✅ All frame append tasks completed (\(iterations) iterations)")
        }

        // ✅ Now stop audio to prevent PTS desync
        print("⏳ Stopping audio to prevent desync...")
        dropAudioDuringStop = true
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

        // Optional: log PTS difference for diagnostics
        if let v = lastVideoPTS, let a = lastAudioPTS {
            let delta = CMTimeSubtract(a, v)
            let ms = (Double(delta.value) / Double(delta.timescale)) * 1000.0
            print("🧪 Final PTS delta (audio - video): \(String(format: "%.2f", ms)) ms")
        }

        // Now transition UI/state to processing
        await MainActor.run {
            recordingState = .processing
        }

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

        // Reset audio drop flag for next recording
        dropAudioDuringStop = false

        await MainActor.run {
            recordingState = .idle
            recordingDuration = 0
        }

        print("✅ Recording stopped successfully")
    }
    
    // MARK: - Orientation Helpers

    /// Get current video rotation angle for AVCaptureConnection (iOS 17+)
    /// Returns rotation angle in degrees (0, 90, 180, 270)
    nonisolated private func videoRotationAngle() -> CGFloat {
        // Access UIDevice.current.orientation in a thread-safe way
        let orientation = MainActor.assumeIsolated {
            UIDevice.current.orientation
        }
        switch orientation {
        case .landscapeLeft:
            return 180  // landscapeRight in old API
        case .landscapeRight:
            return 0    // landscapeLeft in old API
        case .portraitUpsideDown:
            return 270
        default:  // portrait
            return 90
        }
    }

    /// Get current video orientation for AVCaptureConnection (deprecated iOS 17+)
    /// Maps device orientation to camera space (note the inversion for landscape)
    @available(*, deprecated, message: "Use videoRotationAngle() instead")
    nonisolated private func currentVideoOrientation() -> AVCaptureVideoOrientation {
        let orientation = MainActor.assumeIsolated {
            UIDevice.current.orientation
        }
        switch orientation {
        case .landscapeLeft:
            return .landscapeRight  // Camera space vs UI space inversion
        case .landscapeRight:
            return .landscapeLeft
        case .portraitUpsideDown:
            return .portraitUpsideDown
        default:
            return .portrait
        }
    }

    /// Get current video transform for AVAssetWriterInput
    /// Camera sensor captures in landscape (1920x1080), so we need to rotate based on device orientation
    private func currentVideoTransform() -> CGAffineTransform {
        let orientation = UIDevice.current.orientation
        print("📱 Current device orientation: \(orientation.rawValue) (\(orientationName(orientation)))")

        // ✅ CRITICAL FIX: videoRotationAngle on AVCaptureConnection sets METADATA only
        // The actual pixel buffers are STILL in landscape (1920x1080)
        // We need to apply transform to rotate them for proper playback
        let transform: CGAffineTransform
        switch orientation {
        case .portrait, .unknown, .faceUp, .faceDown:
            // Portrait mode - rotate 90° counter-clockwise
            // This rotates 1920x1080 landscape buffer to display as portrait
            transform = CGAffineTransform(rotationAngle: .pi / 2)
            print("🔄 Using 90° transform for portrait")
        case .portraitUpsideDown:
            // Portrait upside down - rotate 90° clockwise
            transform = CGAffineTransform(rotationAngle: -.pi / 2)
            print("🔄 Using -90° transform for portrait upside down")
        case .landscapeLeft:
            // Landscape left - no rotation needed
            transform = .identity
            print("🔄 Using identity transform for landscape left")
        case .landscapeRight:
            // Landscape right - rotate 180°
            transform = CGAffineTransform(rotationAngle: .pi)
            print("🔄 Using 180° transform for landscape right")
        @unknown default:
            // Default to 90° for unknown orientations (assume portrait)
            transform = CGAffineTransform(rotationAngle: .pi / 2)
            print("🔄 Using 90° transform for unknown orientation")
        }

        return transform
    }

    private func orientationName(_ orientation: UIDeviceOrientation) -> String {
        switch orientation {
        case .portrait: return "portrait"
        case .portraitUpsideDown: return "portraitUpsideDown"
        case .landscapeLeft: return "landscapeLeft"
        case .landscapeRight: return "landscapeRight"
        case .faceUp: return "faceUp"
        case .faceDown: return "faceDown"
        case .unknown: return "unknown"
        @unknown default: return "unknown"
        }
    }

    /// Update video orientation on all active connections
    @objc nonisolated private func deviceOrientationDidChange() {
        print("📱 Device orientation changed - updating video connections")

        // Capture session running state on MainActor before async work
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            let isRunning = self.activeSession.isRunning

            // Now do the work on sessionQueue
            self.sessionQueue.async { [weak self] in
                guard let self = self else { return }

                // ✅ FIX: Don't update orientation if session isn't running yet
                // This prevents crashes during initialization
                guard isRunning else {
                    print("⚠️ Session not running yet - skipping orientation update")
                    return
                }

                let angle = self.videoRotationAngle()

                // Update front video output connection
                if let frontOutput = self.frontVideoOutput,
                   let connection = frontOutput.connection(with: .video) {
                    if connection.isVideoRotationAngleSupported(angle) {
                        connection.videoRotationAngle = angle
                    }
                    print("✅ Updated front video rotation to \(angle)°")
                }

                // Update back video output connection
                if let backOutput = self.backVideoOutput,
                   let connection = backOutput.connection(with: .video) {
                    if connection.isVideoRotationAngleSupported(angle) {
                        connection.videoRotationAngle = angle
                    }
                    print("✅ Updated back video rotation to \(angle)°")
                }

                // Update front photo output connection
                if let frontPhoto = self.frontPhotoOutput,
                   let connection = frontPhoto.connection(with: .video) {
                    if connection.isVideoRotationAngleSupported(angle) {
                        connection.videoRotationAngle = angle
                    }
                    print("✅ Updated front photo rotation to \(angle)°")
                }

                // Update back photo output connection
                if let backPhoto = self.backPhotoOutput,
                   let connection = backPhoto.connection(with: .video) {
                    if connection.isVideoRotationAngleSupported(angle) {
                        connection.videoRotationAngle = angle
                    }
                    print("✅ Updated back photo rotation to \(angle)°")
                }

                // ✅ FIX Issue #12: Update preview layer connections
                if let frontConnection = self.frontPreviewLayer?.connection,
                   frontConnection.isVideoRotationAngleSupported(angle) {
                    frontConnection.videoRotationAngle = angle
                    print("✅ Updated front preview rotation to \(angle)°")
                }

                if let backConnection = self.backPreviewLayer?.connection,
                   backConnection.isVideoRotationAngleSupported(angle) {
                    backConnection.videoRotationAngle = angle
                    print("✅ Updated back preview rotation to \(angle)°")
                }
            }
        }
    }

    private func setupAssetWriters() async throws {
        // Verify URLs are set
        guard let frontURL = frontOutputURL,
              let backURL = backOutputURL,
              let combinedURL = combinedOutputURL else {
            throw CameraError.outputURLNotSet
        }

        // Get recording parameters
        let baseDimensions = recordingQuality.dimensions
        let bitRate = recordingQuality.bitRate
        let frameRate = captureMode.frameRate  // ✅ Get dynamic frame rate from capture mode

        // ✅ CRITICAL FIX: Camera buffers are ALWAYS in landscape (1920x1080)
        // videoRotationAngle on AVCaptureConnection only sets metadata, doesn't rotate pixels
        // We use the actual buffer dimensions and apply transform to rotate for playback
        let dimensions = (width: baseDimensions.width, height: baseDimensions.height)
        print("📱 Using buffer dimensions: \(dimensions.width)x\(dimensions.height)")

        // ✅ FIX: Calculate proper transform for video orientation
        // This rotates the landscape buffer to display correctly in portrait/landscape
        let transform = currentVideoTransform()
        print("🔄 Using transform: \(transform)")

        print("🎬 Setting up writers with \(frameRate)fps, dimensions: \(dimensions.width)x\(dimensions.height)")

        // Create the RecordingCoordinator actor
        let coordinator = RecordingCoordinator()
        self.recordingCoordinator = coordinator

        // Configure the coordinator (thread-safe setup) with correct dimensions and transform
        try await coordinator.configure(
            frontURL: frontURL,
            backURL: backURL,
            combinedURL: combinedURL,
            dimensions: dimensions,
            bitRate: bitRate,
            frameRate: frameRate,  // ✅ Pass dynamic frame rate
            videoTransform: transform  // ✅ Proper orientation transform
        )

        print("✅ RecordingCoordinator configured and ready")
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
            // Clean up coordinator reference
            recordingCoordinator = nil
            print("✅ RecordingCoordinator cleaned up")

            // End background task
            endBackgroundTask()
        }

        // Use the coordinator to finish all writers (thread-safe)
        guard let coordinator = recordingCoordinator else {
            print("⚠️ No coordinator to finish")
            return
        }

        // Stop writing and finish all writers concurrently
        let _ = try await coordinator.stopWriting()
        print("✅ All writers finished successfully via coordinator")
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
        print("📸 saveToPhotosLibrary called")

        do {
            try await ensurePhotosAuthorization()
            print("✅ Photos authorization granted")
        } catch {
            print("❌ Photos authorization failed: \(error)")
            throw error
        }

        // Capture URLs in a Sendable-safe way
        guard let frontURL = frontOutputURL,
              let backURL = backOutputURL,
              let combinedURL = combinedOutputURL else {
            print("❌ Missing output URLs")
            throw CameraError.outputURLNotSet
        }

        print("📸 Saving 3 videos to Photos library...")
        print("   Front: \(frontURL.lastPathComponent)")
        print("   Back: \(backURL.lastPathComponent)")
        print("   Combined: \(combinedURL.lastPathComponent)")

        // Save videos one at a time with delays to avoid threading issues
        do {
            print("📸 [1/3] Saving front video...")
            try await saveVideoToPhotos(url: frontURL, title: "DualLensPro - Front Camera")
            print("✅ [1/3] Front video saved successfully")

            // Small delay between saves
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

            print("📸 [2/3] Saving back video...")
            try await saveVideoToPhotos(url: backURL, title: "DualLensPro - Back Camera")
            print("✅ [2/3] Back video saved successfully")

            // Small delay between saves
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

            print("📸 [3/3] Saving combined video...")
            try await saveVideoToPhotos(url: combinedURL, title: "DualLensPro - Combined")
            print("✅ [3/3] Combined video saved successfully")
        } catch {
            print("❌ Error saving video to Photos: \(error)")
            throw error
        }

        // Notify UI to refresh gallery thumbnail
        await MainActor.run {
            NotificationCenter.default.post(name: .init("RefreshGalleryThumbnail"), object: nil)
        }

        print("✅ All videos saved to Photos library")
    }

    // ✅ FIX Issue #11: Save directly from temp directory - NO intermediate copy needed
    private func saveVideoToPhotos(url: URL, title: String) async throws {
        print("📸 Saving \(title) video to Photos: \(url.lastPathComponent)")

        // Verify file exists
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("❌ Video file doesn't exist at: \(url.path)")
            throw CameraError.failedToSaveToPhotos
        }

        let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        print("📸 File size: \(fileSize) bytes (\(String(format: "%.2f", Double(fileSize) / 1_048_576)) MB)")

        // Save directly from temp directory - PHPhotoLibrary CAN access temp files
        return try await Task.detached {
            do {
                try PHPhotoLibrary.shared().performChangesAndWait {
                    let request = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
                    request?.creationDate = Date()
                }
                print("✅ \(title) video saved to Photos")
            } catch {
                print("❌ Failed to save \(title) video: \(error)")
                throw error
            }

            // Clean up temp file after successful save
            do {
                try FileManager.default.removeItem(at: url)
                print("✅ Cleaned up temp file: \(url.lastPathComponent)")
            } catch {
                print("⚠️ Failed to clean up temp file: \(error)")
            }
        }.value
    }

    private func savePhotoToLibrary(_ data: Data) async throws {
        print("📸 Saving photo to library...")

        // Copy to Documents first (sandbox requirement)
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let tempURL = documentsPath.appendingPathComponent("temp_photo_\(UUID().uuidString).jpg")

        try data.write(to: tempURL)
        print("✅ Wrote photo to temp location: \(tempURL.path)")

        // ✅ Use performChangesAndWait on a background thread
        return try await Task.detached {
            var saveError: Error?

            do {
                try PHPhotoLibrary.shared().performChangesAndWait {
                    let creationRequest = PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: tempURL)
                    creationRequest?.creationDate = Date()
                }
                print("✅ Photo saved successfully")
            } catch {
                print("❌ Failed to save photo: \(error)")
                saveError = error
            }

            // Clean up temp file
            defer {
                try? FileManager.default.removeItem(at: tempURL)
                print("✅ Cleaned up temp photo file")
            }

            if let error = saveError {
                throw error
            }
        }.value
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
        // ✅ FIX: Toggle the switched state with haptic feedback
        isCamerasSwitched.toggle()

        // Trigger haptic feedback for the switch
        HapticManager.shared.modeChange()

        // This property can be observed by the UI layer to swap preview positions
        // The actual camera feeds remain the same, just their display positions change
        print("🔄 Cameras switched: \(isCamerasSwitched ? "Front on bottom, Back on top" : "Front on top, Back on bottom")")

        // Update the UI on main thread
        Task { @MainActor in
            // Force UI update by toggling a published property
            self.objectWillChange.send()
        }
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
        if !isWriting && !hasReceivedFirstVideoFrame {
            hasReceivedFirstVideoFrame = true
            print("🎬 Starting session on first video frame")

            let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            recordingStartTime = timestamp

            // Start the coordinator's writers
            guard let coordinator = recordingCoordinator else { return }
            Task {
                do {
                    try await coordinator.startWriting(at: timestamp)
                    isWriting = true
                    print("✅ Writers started and ready to accept samples")
                } catch {
                    print("❌ Failed to start writing: \(error)")
                }
            }
            return // Skip this frame since we're starting
        }

        guard isWriting, recordingStartTime != nil else {
            return
        }

        // Extract pixel buffer and timestamp
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            print("⚠️ No pixel buffer in sample")
            return
        }
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let position: CameraPosition = isFront ? .front : .back

        // ✅ FIX Issue #10: Implement frame dropping if we're falling behind
        if let lastTime = lastProcessedFrameTime[position] {
            let timeSinceLastFrame = CMTimeSubtract(pts, lastTime).seconds

            if timeSinceLastFrame < minimumFrameInterval * 0.9 {  // Allow 10% tolerance
                // Too soon, drop this frame
                return
            }
        }

        lastProcessedFrameTime[position] = pts
        lastVideoPTS = pts

        // Use the coordinator to append pixel buffers (thread-safe via actor)
        guard let coordinator = recordingCoordinator else { return }

        // Box the pixel buffer for safe transfer across actor boundary
        let box = PixelBufferBox(pixelBuffer, time: pts)

        // ✅ FIX: Track each append task so we can wait for all to complete
        let taskID = UUID()
        let _ = pendingTasksLock.withLock { $0.insert(taskID) }

        // ✅ FIX Issue #10: Process on writer queue for natural backpressure
        writerQueue.async { [weak self] in
            Task { [box, isFront, isBack, coordinator, taskID] in
                defer {
                    // Remove from pending tasks when done
                    let _ = self?.pendingTasksLock.withLock { $0.remove(taskID) }
                }

                do {
                    if isFront {
                        try await coordinator.appendFrontPixelBuffer(box.buffer, time: box.time)
                    } else if isBack {
                        // appendBackPixelBuffer also appends to combined writer
                        try await coordinator.appendBackPixelBuffer(box.buffer, time: box.time)
                    }
                } catch {
                    print("❌ Error appending pixel buffer: \(error)")
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
        // Mark that we've received audio
        if !hasReceivedFirstAudioFrame {
            hasReceivedFirstAudioFrame = true
            print("🎤 First audio frame received")
        }
        
        // If we're in the stop sequence and dropping audio, ignore further audio samples
        if dropAudioDuringStop {
            return
        }

        // Wait for writing to start (video frame triggers this)
        guard isWriting, recordingStartTime != nil else {
            // print("⏸️ Audio sample received but not writing yet")
            return
        }
        
        // Track last audio timestamp
        let audioPTS = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        lastAudioPTS = audioPTS

        // Use the coordinator to append audio samples (thread-safe via actor)
        guard let coordinator = recordingCoordinator else { return }

        // Box the sample buffer for safe transfer across actor boundary
        let box = SampleBufferBox(sampleBuffer)

        Task { [box] in
            do {
                try await coordinator.appendAudioSample(box.buffer)
            } catch {
                print("❌ Error appending audio sample: \(error)")
            }
        }
    }
}

// MARK: - Errors
enum CameraError: LocalizedError {
    case setupInProgress
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
    case failedToSaveToPhotos

    var errorDescription: String? {
        switch self {
        case .setupInProgress:
            return "Camera setup is already in progress"
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
        case .failedToSaveToPhotos:
            return "Failed to save video to Photos library"
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
    private let onComplete: (Data?) -> Void

    init(continuation: CheckedContinuation<Void, Error>, camera: String, onComplete: @escaping (Data?) -> Void) {
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
        defer { onComplete(nil) }  // Always clean up delegate after resuming

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
                // Pass photo data to completion handler for combined photo
                self.onComplete(imageData)

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

    /* TODO: Uncomment after adding DeviceMonitorService.swift to Xcode project
    // MARK: - Device Monitor Delegate (Issues #4.6, #4.7, #4.8)

    nonisolated func deviceMonitor(_ monitor: DeviceMonitorService, didUpdateThermalState state: ProcessInfo.ThermalState) {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            print("🌡️ Thermal state changed: \(state)")

            // Check if recording should be stopped
            let (shouldStop, reason) = monitor.shouldStopRecording()
            if shouldStop, self.recordingState == .recording {
                if let reason = reason.first {
                    self.errorMessage = reason
                }
                do {
                    try await self.stopRecording()
                    print("⚠️ Recording stopped due to thermal state: \(state)")
                } catch {
                    print("❌ Failed to stop recording after thermal warning: \(error)")
                }
            }
        }
    }

    nonisolated func deviceMonitor(_ monitor: DeviceMonitorService, didUpdateBatteryLevel level: Float, state: UIDevice.BatteryState) {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            let percentage = Int(level * 100)
            print("🔋 Battery level: \(percentage)% (\(state))")

            // Check if recording should be stopped or warned
            let (shouldStop, reasons, warnings) = monitor.shouldStopRecording()

            if shouldStop, self.recordingState == .recording {
                if let reason = reasons.first {
                    self.errorMessage = reason
                }
                do {
                    try await self.stopRecording()
                    print("⚠️ Recording stopped due to low battery: \(percentage)%")
                } catch {
                    print("❌ Failed to stop recording after battery warning: \(error)")
                }
            } else if let warning = warnings.first {
                // Show warning but don't stop
                self.errorMessage = warning
            }
        }
    }

    nonisolated func deviceMonitor(_ monitor: DeviceMonitorService, didReceiveMemoryWarning: Void) {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            print("⚠️ Memory warning received")

            // Perform cleanup
            monitor.performMemoryCleanup()

            // Check if recording should be stopped
            let (shouldStop, reasons, warnings) = monitor.shouldStopRecording()

            if shouldStop, self.recordingState == .recording {
                if let reason = reasons.first {
                    self.errorMessage = reason
                }
                do {
                    try await self.stopRecording()
                    print("⚠️ Recording stopped due to memory pressure")
                } catch {
                    print("❌ Failed to stop recording after memory warning: \(error)")
                }
            } else if let warning = warnings.first {
                // Show warning but don't stop
                self.errorMessage = warning
            }
        }
    }
    */
}

