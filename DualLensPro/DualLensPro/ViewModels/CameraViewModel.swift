//
//  CameraViewModel.swift
//  DualLensPro
//
//  Created by DualLens Pro Team on 10/24/25.
//

import SwiftUI
import AVFoundation
import Combine
import Photos

@MainActor
class CameraViewModel: ObservableObject {
    @Published var isAuthorized = false
    @Published var isCameraReady = false // New flag to track if camera is fully initialized
    var cameraManager = DualCameraManager() // Removed @Published - updates are handled via Combine subscriptions
    var configuration = CameraConfiguration() // Removed @Published - internal state only
    @Published var showError = false
    @Published var errorMessage: String = ""

    // UI State
    @Published var controlsVisible = true
    @Published var showSettings = false
    @Published var showGallery = false
    @Published var showPremiumUpgrade = false
    @Published var showSaveSuccessToast = false
    @Published var saveSuccessMessage = ""

    // Managers & Services (removed @Published - these don't need UI updates)
    var subscriptionManager = SubscriptionManager()
    var photoLibraryService = PhotoLibraryService()
    // TODO: Add DeviceMonitorService.swift to Xcode project and uncomment
    // private let deviceMonitor = DeviceMonitorService.shared
    // TODO: Add AnalyticsService to Xcode project and uncomment
    // private let analytics = AnalyticsService.shared
    lazy var settingsViewModel: SettingsViewModel = {
        SettingsViewModel(configuration: configuration)
    }()

    // Capture Mode
    @Published var currentCaptureMode: CaptureMode = .video {
        didSet {
            handleCaptureModeChange()
        }
    }

    // Timer countdown
    @Published var showTimerCountdown = false
    @Published var timerCountdownDuration = 0

    // Advanced Controls
    @Published var showAdvancedControls = false
    @Published var selectedZoomPreset: CGFloat = 1.0
    @Published var showModeSelector = false

    // Camera switching state (mirrored from cameraManager for SwiftUI updates)
    @Published var isCamerasSwitched = false

    // Recording state passthrough
    var isRecording: Bool {
        cameraManager.recordingState.isRecording
    }

    var recordingDuration: TimeInterval {
        cameraManager.recordingDuration
    }

    // Premium features
    var isPremium: Bool {
        subscriptionManager.isPremium
    }

    var canRecord: Bool {
        subscriptionManager.canRecord
    }

    var remainingRecordingTime: TimeInterval {
        subscriptionManager.remainingRecordingTime
    }

    var shouldShowTimeWarning: Bool {
        subscriptionManager.showTimeWarning
    }

    // MARK: - Initialization
    private var recordingMonitorTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private var isSettingUpCamera = false // Prevent duplicate setup calls

    init() {
        // FORCE video mode for now to prevent crashes
        // TODO: Re-enable UserDefaults loading after fixing mode switching
        currentCaptureMode = .video
        print("📱 Forced VIDEO mode on init to prevent crashes")

        // Check authorization status synchronously to avoid flashing permission view
        let cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
        let audioStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        self.isAuthorized = (cameraStatus == .authorized && audioStatus == .authorized)

        print("🔐 Init - Camera: \(cameraStatus.rawValue), Audio: \(audioStatus.rawValue)")
        print("🔐 Init - isAuthorized set to: \(self.isAuthorized)")
        print("🔐 Init - currentCaptureMode: \(currentCaptureMode), isPhotoMode: \(currentCaptureMode.isPhotoMode), isRecordingMode: \(currentCaptureMode.isRecordingMode)")

        // Bridge manager errors to VM so UI can display them
        // ✅ FIX Issue #3: Use DispatchQueue.main instead of RunLoop.main for proper MainActor isolation
        cameraManager.$errorMessage
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in
                Task { @MainActor in
                    self?.setError(message)
                }
            }
            .store(in: &cancellables)

        // ✅ CRITICAL: Observe recordingState changes to update UI
        // ✅ FIX Issue #3: Use DispatchQueue.main instead of RunLoop.main for proper MainActor isolation
        cameraManager.$recordingState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newState in
                print("🎬 Recording state changed to: \(newState) (isRecording: \(newState.isRecording))")
                Task { @MainActor in
                    self?.objectWillChange.send()
                }
            }
            .store(in: &cancellables)

        // ✅ CRITICAL FIX: Manually sync mode since didSet doesn't fire in init
        // This ensures cameraManager and configuration are properly initialized
        configuration.setCaptureMode(.video)
        cameraManager.setCaptureMode(.video)
        print("✅ Manually synchronized capture mode to VIDEO")

        // Start device monitoring
        // TODO: Uncomment after adding DeviceMonitorService.swift to Xcode project
        // deviceMonitor.startMonitoring()
        // deviceMonitor.delegate = cameraManager
        // print("✅ Device monitoring started")

        // NOTE: Do NOT call setupRecordingMonitor() here - it will be called after camera setup
        // Calling async operations in init can cause crashes
    }

    deinit {
        recordingMonitorTask?.cancel()
        // TODO: Uncomment after adding DeviceMonitorService.swift to Xcode project
        // deviceMonitor.stopMonitoring()
    }

    // MARK: - Authorization
    func checkAuthorization() {
        Task { @MainActor in
            let cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
            let audioStatus = AVCaptureDevice.authorizationStatus(for: .audio)

            print("🔐 checkAuthorization - Camera: \(cameraStatus.rawValue), Audio: \(audioStatus.rawValue)")
            print("🔐 Camera authorized: \(cameraStatus == .authorized), Audio authorized: \(audioStatus == .authorized)")
            print("🔐 Current isAuthorized BEFORE: \(isAuthorized)")

            if cameraStatus == .authorized && audioStatus == .authorized {
                print("✅ Both permissions authorized!")

                // Force update isAuthorized on MainActor
                self.isAuthorized = true
                print("✅ isAuthorized AFTER setting: \(self.isAuthorized)")

                // Force a UI refresh
                self.objectWillChange.send()

                print("🎥 About to call setupCamera()")
                await setupCamera()
                print("🎥 setupCamera() completed")

            } else if cameraStatus == .notDetermined || audioStatus == .notDetermined {
                print("❓ Permissions not determined - requesting")
                await requestPermissions()
            } else {
                print("❌ Permissions denied - setting isAuthorized = false")
                self.isAuthorized = false
            }
        }
    }

    private func requestPermissions() async {
        print("🔐 Requesting camera and microphone permissions...")

        let cameraGranted = await AVCaptureDevice.requestAccess(for: .video)
        print("🔐 Camera permission: \(cameraGranted ? "✅ GRANTED" : "❌ DENIED")")

        let audioGranted = await AVCaptureDevice.requestAccess(for: .audio)
        print("🔐 Microphone permission: \(audioGranted ? "✅ GRANTED" : "❌ DENIED")")

        isAuthorized = cameraGranted && audioGranted
        print("🔐 Overall authorization: \(isAuthorized ? "✅ AUTHORIZED" : "❌ NOT AUTHORIZED")")

        if isAuthorized {
            print("🔐 Proceeding to camera setup...")
            await setupCamera()
        } else {
            print("❌ Cannot proceed - missing required permissions")
            if !cameraGranted {
                print("   - Camera access denied")
            }
            if !audioGranted {
                print("   - Microphone access denied")
            }
        }
    }

    // MARK: - Camera Setup
    private func setupCamera() async {
        // Prevent duplicate setup calls
        guard !isSettingUpCamera else {
            print("⚠️ setupCamera already in progress - skipping duplicate call")
            return
        }

        let _ = Date()  // Track setup start time.timeIntervalSince1970
        isSettingUpCamera = true
        defer { isSettingUpCamera = false }

        print("🎥 setupCamera - Starting camera setup...")
        print("🎥 Multi-cam supported: \(cameraManager.isMultiCamSupported)")
        print("🎥 Session running: \(cameraManager.isSessionRunning)")

        do {
            print("🎥 Calling cameraManager.setupSession()...")
            try await cameraManager.setupSession()
            print("✅ setupCamera - Session setup complete")

            print("🎥 Calling cameraManager.startSession()...")
            cameraManager.startSession()
            print("✅ setupCamera - Session started")

            // Wait for session to actually start using proper state checking
            var attempts = 0
            while !cameraManager.isSessionRunning && attempts < 20 {
                try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
                attempts += 1
            }

            print("🎥 Session running after \(attempts * 50)ms: \(cameraManager.isSessionRunning)")

            // Wait a tiny bit for preview layers to render first frame
            // This is needed because session.isRunning = true doesn't mean frames are rendering yet
            try? await Task.sleep(nanoseconds: 200_000_000) // 200ms for preview to start

            // Mark camera as ready for UI
            self.isCameraReady = true
            print("✅ Camera ready flag set to true (total time: ~\((attempts * 50) + 200)ms)")

            // NOW it's safe to start the recording monitor after camera is fully set up
            if recordingMonitorTask == nil {
                setupRecordingMonitor()
                print("✅ setupCamera - Recording monitor started")
            }
            print("✅ setupCamera - All setup complete!")

            // TODO: Re-enable analytics when AnalyticsService is added to project
            // analytics.trackCameraSetupCompleted(
            //     multiCamSupported: cameraManager.isMultiCamSupported,
            //     duration: Date().timeIntervalSince1970 - setupStartTime
            // )
        } catch {
            print("❌ ========== CAMERA SETUP ERROR ==========")
            print("❌ Error description: \(error.localizedDescription)")
            print("❌ Error type: \(type(of: error))")
            print("❌ Full error: \(error)")

            // Print stack trace if available
            if let nsError = error as NSError? {
                print("❌ Domain: \(nsError.domain)")
                print("❌ Code: \(nsError.code)")
                print("❌ UserInfo: \(nsError.userInfo)")
            }
            print("❌ ========================================")

            // Set specific error message based on error type
            let errorText: String
            if let cameraError = error as? CameraError {
                errorText = "Camera Error: \(cameraError.localizedDescription)"
            } else {
                errorText = "Camera setup failed: \(error.localizedDescription)"
            }

            setError(errorText)

            // CRITICAL: Reset states so user can retry
            isCameraReady = false
            isAuthorized = false
        }
    }

    // MARK: - Capture Mode Management
    private func handleCaptureModeChange() {
        print("🎯 handleCaptureModeChange called - new mode: \(currentCaptureMode.rawValue)")
        print("   isPhotoMode: \(currentCaptureMode.isPhotoMode), isRecordingMode: \(currentCaptureMode.isRecordingMode)")

        // Trigger haptic feedback
        HapticManager.shared.modeChange()

        // Check if mode requires premium
        // Premium gating disabled for all modes


        // Update configuration
        configuration.setCaptureMode(currentCaptureMode)
        print("✅ Configuration updated to: \(currentCaptureMode.rawValue)")

        // Update camera manager mode
        cameraManager.setCaptureMode(currentCaptureMode)
        print("✅ Camera manager updated to: \(currentCaptureMode.rawValue)")

        // Apply mode-specific settings
        switch currentCaptureMode {
        case .groupPhoto:
            // Set to wide angle
            updateFrontZoom(0.5)
            updateBackZoom(0.5)
            // Enable timer by default for group photos
            if timerDuration == 0 {
                setTimer(10)
            }
        case .action:
            // ✅ FIX: Action mode is a recording mode, ensure high quality
            setRecordingQuality(.high)
            print("🎬 Action mode enabled - 120fps high-speed recording ready")
        case .switchScreen:
            // ✅ FIX: Switch Screen mode swaps camera positions
            switchCameras()
            print("🔄 Switch Screen mode - camera positions swapped")
            // After swapping, return to previous mode (video or photo)
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second delay
                // Return to video mode after switching
                self.currentCaptureMode = .video
            }
        default:
            break
        }

        print("✅ handleCaptureModeChange complete for mode: \(currentCaptureMode.rawValue)")
    }

    func setCaptureMode(_ mode: CaptureMode) {
        currentCaptureMode = mode
    }

    // MARK: - Zoom Control
    func updateFrontZoom(_ factor: CGFloat) {
        HapticManager.shared.zoomChange()
        configuration.updateFrontZoom(factor)
        cameraManager.frontZoomFactor = factor
    }

    func updateBackZoom(_ factor: CGFloat) {
        HapticManager.shared.zoomChange()
        configuration.updateBackZoom(factor)
        cameraManager.backZoomFactor = factor
    }

    func setZoomPreset(_ preset: CGFloat) {
        HapticManager.shared.selection()
        selectedZoomPreset = preset
        updateFrontZoom(preset)
        updateBackZoom(preset)
    }

    // MARK: - Recording Control
    func toggleRecording() {
        print("🎬 toggleRecording called - current isRecording: \(isRecording)")
        print("🎬 currentCaptureMode: \(currentCaptureMode)")
        print("🎬 canRecord: \(canRecord)")
        print("🎬 isRecordingMode: \(currentCaptureMode.isRecordingMode)")

        Task {
            do {
                if isRecording {
                    print("🛑 Calling stopRecording...")
                    try await stopRecording()
                } else {
                    print("▶️ Calling startRecording...")
                    try await startRecording()
                }
            } catch {
                print("❌ Recording error: \(error.localizedDescription)")
                setError(error.localizedDescription)
            }
        }
    }

    private func startRecording() async throws {
        print("📹 ========== START RECORDING CALLED ==========")
        print("📹 Current mode: \(currentCaptureMode.rawValue)")
        print("📹 isPhotoMode: \(currentCaptureMode.isPhotoMode)")
        print("📹 isRecordingMode: \(currentCaptureMode.isRecordingMode)")
        print("📹 canRecord: \(canRecord)")
        print("📹 isPremium: \(isPremium)")
        print("📹 isCameraReady: \(isCameraReady)")
        print("📹 Current isRecording state: \(isRecording)")

        // ✅ CRITICAL FIX: Check Photos permission BEFORE recording starts
        let photosStatus = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        print("📸 Photos authorization status: \(photosStatus.rawValue)")

        if photosStatus != .authorized && photosStatus != .limited {
            print("❌ Photos permission not granted - requesting...")
            let newStatus = await PHPhotoLibrary.requestAuthorization(for: .addOnly)

            guard newStatus == .authorized || newStatus == .limited else {
                print("❌ Photos permission denied - cannot save videos")
                HapticManager.shared.error()
                throw CameraRecordingError.photosNotAuthorized
            }
            print("✅ Photos permission granted")
        }

        // ✅ FIX Issue #19: Check available storage space with dynamic calculation
        try checkStorageSpace()

        // ✅ FIX Issue #4.6-4.8: Check device monitoring conditions
        // TODO: Uncomment after adding DeviceMonitorService.swift to Xcode project
        /*
        let deviceCheck = deviceMonitor.canStartRecording()
        guard deviceCheck.allowed else {
            print("❌ Cannot record - device conditions not met")
            HapticManager.shared.error()
            let errorMsg = deviceCheck.reasons.joined(separator: "\n")
            throw CameraRecordingError.deviceConditionsNotMet(errorMsg)
        }
        print("✅ Device conditions check passed")
        */

        // Check if user can record (premium check)
        // Premium gating disabled - allow recording without limits
        print("✅ Premium gating disabled - allowing recording")

        // Check that we're in a recording mode
        guard currentCaptureMode.isRecordingMode else {
            print("❌ NOT IN RECORDING MODE!")
            print("   Current mode: \(currentCaptureMode.rawValue)")
            print("   Expected: video or action")
            HapticManager.shared.error()
            throw CameraRecordingError.invalidModeForRecording
        }
        print("✅ In recording mode: \(currentCaptureMode.rawValue)")

        // Trigger haptic feedback
        HapticManager.shared.recordingStart()

        print("📹 About to call cameraManager.startRecording()...")

        // TODO: Re-enable analytics when AnalyticsService is added to project
        // analytics.trackRecordingStarted(
        //     mode: currentCaptureMode.rawValue,
        //     quality: recordingQuality.rawValue
        // )

        try await cameraManager.startRecording()
        print("✅ cameraManager.startRecording() completed")
        print("📹 New isRecording state: \(isRecording)")
        print("📹 ========== START RECORDING COMPLETE ==========")
    }

    private func stopRecording() async throws {
        // ✅ FIX Issue #4: Cancel recording monitor task when stopping recording
        recordingMonitorTask?.cancel()

        // Trigger haptic feedback
        HapticManager.shared.recordingStop()

        try await cameraManager.stopRecording()

        // TODO: Re-enable analytics when AnalyticsService is added to project
        // analytics.trackRecordingCompleted(
        //     duration: recordingDuration,
        //     mode: currentCaptureMode.rawValue,
        //     quality: recordingQuality.rawValue
        // )

        subscriptionManager.resetRecordingDuration()

        // Success haptic
        HapticManager.shared.success()

        // Show success toast
        saveSuccessMessage = "Videos saved to library"
        showSaveSuccessToast = true

        // Auto-hide after 2 seconds
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            showSaveSuccessToast = false
        }
    }

    // MARK: - Photo Capture
    func capturePhoto() {
        print("📸 capturePhoto() called")
        print("📸 currentCaptureMode: \(currentCaptureMode)")
        print("📸 isPhotoMode: \(currentCaptureMode.isPhotoMode)")
        print("📸 isCameraReady: \(isCameraReady)")

        Task {
            do {
                // Check that camera is ready
                guard isCameraReady else {
                    print("❌ Camera not ready yet")
                    HapticManager.shared.error()
                    setError("Camera is still initializing. Please wait...")
                    return
                }

                // Check that we're in a photo mode
                guard currentCaptureMode.isPhotoMode else {
                    print("❌ Not in photo mode: \(currentCaptureMode)")
                    HapticManager.shared.error()
                    setError("Switch to PHOTO or GROUP PHOTO mode to capture photos")
                    return
                }

                print("✅ Starting photo capture...")
                // If timer is set, show countdown
                if timerDuration > 0 {
                    print("⏱️ Timer set to \(timerDuration) seconds")
                    await MainActor.run {
                        timerCountdownDuration = timerDuration
                        showTimerCountdown = true
                    }
                } else {
                    // Immediate capture with haptic
                    print("📸 Immediate capture (no timer)")
                    HapticManager.shared.photoCapture()
                    try await cameraManager.capturePhoto()
                    HapticManager.shared.success()
                    print("✅ Photo captured successfully")
                }
            } catch {
                print("❌ Photo capture error: \(error)")
                HapticManager.shared.error()
                setError("Photo capture failed: \(error.localizedDescription)")
            }
        }
    }

    func executePhotoCapture() {
        Task {
            do {
                HapticManager.shared.photoCapture()
                try await cameraManager.capturePhoto()
                HapticManager.shared.success()

                // Show success toast
                saveSuccessMessage = "Photos saved to library"
                showSaveSuccessToast = true

                // Auto-hide after 2 seconds
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                showSaveSuccessToast = false
            } catch {
                HapticManager.shared.error()
                setError(error.localizedDescription)
            }
        }
    }

    func cancelTimerCountdown() {
        showTimerCountdown = false
    }

    // MARK: - Focus Control
    func setFocusPoint(_ point: CGPoint, in previewLayer: AVCaptureVideoPreviewLayer, for position: CameraPosition) {
        cameraManager.setFocusPoint(point, in: previewLayer, for: position)
    }

    func toggleFocusLock(for position: CameraPosition) {
        cameraManager.toggleFocusLock(for: position)
    }

    // MARK: - Exposure Control
    func setExposure(_ value: Float, for position: CameraPosition) {
        cameraManager.setExposure(value, for: position)
    }

    // MARK: - White Balance Control
    func setWhiteBalance(_ mode: WhiteBalanceMode) {
        configuration.setWhiteBalance(mode)
        cameraManager.setWhiteBalance(mode)
    }

    var whiteBalanceMode: WhiteBalanceMode {
        configuration.whiteBalanceMode
    }

    // MARK: - Flash Control
    func toggleFlash() {
        cameraManager.toggleFlash()
    }

    var flashMode: AVCaptureDevice.FlashMode {
        cameraManager.flashMode
    }

    // MARK: - Timer Control
    func setTimer(_ duration: Int) {
        configuration.setTimer(duration)
        cameraManager.setTimer(duration)
    }

    var timerDuration: Int {
        cameraManager.timerDuration
    }

    // MARK: - Grid Control
    func toggleGrid() {
        configuration.toggleGrid()
        cameraManager.toggleGrid()
    }

    var showGrid: Bool {
        cameraManager.showGrid
    }

    // MARK: - Center Stage Control
    func toggleCenterStage() {
        cameraManager.toggleCenterStage()
    }

    var isCenterStageEnabled: Bool {
        cameraManager.isCenterStageEnabled
    }

    // MARK: - Quality Control
    func setRecordingQuality(_ quality: RecordingQuality) {
        configuration.setRecordingQuality(quality)
        cameraManager.setRecordingQuality(quality)
    }

    var recordingQuality: RecordingQuality {
        configuration.recordingQuality
    }

    // MARK: - Aspect Ratio
    func setAspectRatio(_ ratio: AspectRatio) {
        configuration.setAspectRatio(ratio)
    }

    var aspectRatio: AspectRatio {
        configuration.aspectRatio
    }

    // MARK: - Video Stabilization
    func setVideoStabilization(_ mode: VideoStabilizationMode) {
        configuration.setVideoStabilization(mode)
        cameraManager.setVideoStabilization(mode)
    }

    var videoStabilization: VideoStabilizationMode {
        configuration.videoStabilizationMode
    }

    // MARK: - Camera Control
    func switchCameras() {
        cameraManager.switchCameras()
        // ✅ FIX: Update local @Published property to trigger SwiftUI re-render
        isCamerasSwitched = cameraManager.isCamerasSwitched
    }

    func toggleControlsVisibility() {
        // ✅ FIX: Don't hide controls if advanced menu or mode selector is open
        // This prevents accidentally closing menus when tapping on them
        guard !showAdvancedControls && !showModeSelector else {
            print("⚠️ Advanced controls or mode selector is open - ignoring tap")
            return
        }

        withAnimation(.spring(response: 0.3)) {
            controlsVisible.toggle()
        }
    }

    func toggleModeSelector() {
        showModeSelector.toggle()
    }

    func toggleAdvancedControls() {
        showAdvancedControls.toggle()
    }

    // MARK: - Premium Features
    func showPremiumPrompt() {
        showPremiumUpgrade = true
    }

    func purchasePremium(_ productType: PremiumProductType) async {
        do {
            try await subscriptionManager.purchasePremium(productType: productType)
        } catch {
            setError("Purchase failed: \(error.localizedDescription)")
        }
    }

    func restorePurchases() async {
        do {
            try await subscriptionManager.restorePurchases()
        } catch {
            setError("Restore failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Recording Monitor
    private func setupRecordingMonitor() {
        // Store the task so we can cancel it if needed
        recordingMonitorTask = Task { [weak self] in
            guard let self = self else { return }
            while !Task.isCancelled {
                // ✅ FIX Issue #2: Debounce to 0.5s instead of 0.1s to reduce UI updates
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

                // ✅ FIX Issue #4: Check cancellation after sleep
                guard !Task.isCancelled else { break }

                if self.isRecording {
                    self.subscriptionManager.updateRecordingDuration(self.recordingDuration)
                    // Premium gating disabled: no time warning or auto-stop
                }
            }
            // Premium gating disabled: never show upgrade prompt
        }
    }

    // MARK: - Gallery Integration
    func loadLatestPhoto() {
        Task {
            await photoLibraryService.fetchLatestAsset()
        }
    }

    var latestPhotoThumbnail: UIImage? {
        photoLibraryService.latestThumbnail
    }

    func openGallery() {
        showGallery = true
    }

    // MARK: - Storage Management (Issue #19)
    private func checkStorageSpace() throws {
        let tempDir = FileManager.default.temporaryDirectory.path

        guard let attributes = try? FileManager.default.attributesOfFileSystem(forPath: tempDir),
              let availableSpace = attributes[.systemFreeSize] as? Int64 else {
            print("⚠️ Cannot check storage space")
            return  // Don't block recording if we can't check
        }

        // Calculate required space based on recording settings
        let requiredBytes = calculateRequiredSpace(
            quality: cameraManager.recordingQuality,
            mode: currentCaptureMode,
            isPremium: subscriptionManager.isPremium
        )

        let availableMB = Double(availableSpace) / 1_000_000
        let requiredMB = Double(requiredBytes) / 1_000_000

        guard availableSpace > requiredBytes else {
            let message = String(format: "Insufficient storage. Need %.0fMB, have %.0fMB available",
                               requiredMB, availableMB)
            print("❌ \(message)")
            HapticManager.shared.error()
            throw CameraRecordingError.insufficientStorage
        }

        print("✅ Storage check passed: \(String(format: "%.0fMB", availableMB)) available, \(String(format: "%.0fMB", requiredMB)) required")
    }

    private func calculateRequiredSpace(
        quality: RecordingQuality,
        mode: CaptureMode,
        isPremium: Bool
    ) -> Int64 {
        // Estimate bitrate based on quality and mode
        let bitrate: Double = {
            switch (quality, mode) {
            case (.ultra, .action):
                return 100_000_000  // 100 Mbps for 4K 120fps
            case (.ultra, _):
                return 50_000_000   // 50 Mbps for 4K 60fps
            case (.high, _):
                return 25_000_000   // 25 Mbps for 1080p
            case (.medium, _):
                return 10_000_000   // 10 Mbps for 720p
            case (.low, _):
                return 5_000_000    // 5 Mbps for 720p low
            }
        }()

        // Estimate recording duration
        let maxDurationSeconds: Double = isPremium ? 600 : 30  // 10min vs 30s

        // Calculate size with 20% safety margin
        let estimatedBytes = (bitrate / 8) * maxDurationSeconds * 1.2

        // Triple for 3 simultaneous outputs (front, back, combined)
        let totalBytes = Int64(estimatedBytes * 3)

        return max(totalBytes, 500_000_000)  // Minimum 500MB
    }

    // MARK: - Error Handling
    private func setError(_ message: String) {
        errorMessage = message
        showError = true
    }
}

// MARK: - Recording Error
enum CameraRecordingError: LocalizedError {
    case recordingLimitReached
    case invalidModeForRecording
    case photosNotAuthorized
    case insufficientStorage
    case deviceConditionsNotMet(String)

    var errorDescription: String? {
        switch self {
        case .recordingLimitReached:
            return "Recording limit reached. Upgrade to Premium for unlimited recording."
        case .invalidModeForRecording:
            return "This capture mode does not support recording."
        case .photosNotAuthorized:
            return "Photos access is required to save videos. Please grant permission in Settings."
        case .insufficientStorage:
            return "Not enough storage space. Please free up at least 500 MB to record."
        case .deviceConditionsNotMet(let message):
            return message
        }
    }
}
