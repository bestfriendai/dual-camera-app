//
//  CameraViewModel.swift
//  DualLensPro
//
//  Created by DualLens Pro Team on 10/24/25.
//

import SwiftUI
import AVFoundation
import Combine

@MainActor
class CameraViewModel: ObservableObject {
    @Published var isAuthorized = false
    @Published var cameraManager = DualCameraManager()
    @Published var configuration = CameraConfiguration()
    @Published var showError = false
    @Published var errorMessage: String = ""

    // UI State
    @Published var controlsVisible = true
    @Published var showSettings = false
    @Published var showGallery = false
    @Published var showPremiumUpgrade = false

    // Managers & Services
    @Published var subscriptionManager = SubscriptionManager()
    @Published var photoLibraryService = PhotoLibraryService()
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

    init() {
        // Load default capture mode from settings
        if let modeString = UserDefaults.standard.string(forKey: "settings.defaultCaptureMode"),
           let mode = CaptureMode(rawValue: modeString) {
            currentCaptureMode = mode
        }

        // Bridge manager errors to VM so UI can display them
        cameraManager.$errorMessage
            .compactMap { $0 }
            .receive(on: RunLoop.main)
            .sink { [weak self] message in
                self?.setError(message)
            }
            .store(in: &cancellables)

        // NOTE: Do NOT call setupRecordingMonitor() here - it will be called after camera setup
        // Calling async operations in init can cause crashes
    }

    deinit {
        recordingMonitorTask?.cancel()
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
        let cameraGranted = await AVCaptureDevice.requestAccess(for: .video)
        let audioGranted = await AVCaptureDevice.requestAccess(for: .audio)

        isAuthorized = cameraGranted && audioGranted

        if isAuthorized {
            await setupCamera()
        }
    }

    // MARK: - Camera Setup
    private func setupCamera() async {
        do {
            print("🎥 setupCamera - Starting camera setup...")
            try await cameraManager.setupSession()
            print("✅ setupCamera - Session setup complete")
            cameraManager.startSession()
            print("✅ setupCamera - Session started")

            // NOW it's safe to start the recording monitor after camera is fully set up
            if recordingMonitorTask == nil {
                setupRecordingMonitor()
                print("✅ setupCamera - Recording monitor started")
            }
            print("✅ setupCamera - All setup complete!")
        } catch {
            print("❌ setupCamera ERROR: \(error.localizedDescription)")
            print("❌ Error type: \(type(of: error))")
            print("❌ Error details: \(error)")

            // Set specific error message based on error type
            let errorText: String
            if let cameraError = error as? CameraError {
                errorText = cameraError.localizedDescription
            } else {
                errorText = "Camera setup failed: \(error.localizedDescription)"
            }

            setError(errorText)

            // CRITICAL: Set isAuthorized to false so ContentView shows error
            isAuthorized = false
        }
    }

    // MARK: - Capture Mode Management
    private func handleCaptureModeChange() {
        // Trigger haptic feedback
        HapticManager.shared.modeChange()

        // Check if mode requires premium
        if currentCaptureMode.requiresPremium && !isPremium {
            HapticManager.shared.premiumLocked()
            showPremiumUpgrade = true
            // Revert to previous mode
            currentCaptureMode = .video
            return
        }

        // Update configuration
        configuration.setCaptureMode(currentCaptureMode)

        // Update camera manager mode
        cameraManager.setCaptureMode(currentCaptureMode)

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
            // Ensure high quality for action mode
            setRecordingQuality(.high)
        case .switchScreen:
            // Trigger camera switch animation
            switchCameras()
        default:
            break
        }
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
        Task {
            do {
                if isRecording {
                    try await stopRecording()
                } else {
                    try await startRecording()
                }
            } catch {
                setError(error.localizedDescription)
            }
        }
    }

    private func startRecording() async throws {
        // Check if user can record (premium check)
        guard canRecord else {
            HapticManager.shared.premiumLocked()
            showPremiumUpgrade = true
            throw RecordingError.recordingLimitReached
        }

        // Check that we're in a recording mode
        guard currentCaptureMode.isRecordingMode else {
            HapticManager.shared.error()
            throw RecordingError.invalidModeForRecording
        }

        // Trigger haptic feedback
        HapticManager.shared.recordingStart()

        try await cameraManager.startRecording()
    }

    private func stopRecording() async throws {
        // Trigger haptic feedback
        HapticManager.shared.recordingStop()

        try await cameraManager.stopRecording()
        subscriptionManager.resetRecordingDuration()

        // Success haptic
        HapticManager.shared.success()
    }

    // MARK: - Photo Capture
    func capturePhoto() {
        Task {
            do {
                // Check that we're in a photo mode
                guard currentCaptureMode.isPhotoMode else {
                    HapticManager.shared.error()
                    setError("Switch to PHOTO or GROUP PHOTO mode to capture photos")
                    return
                }

                // If timer is set, show countdown
                if timerDuration > 0 {
                    await MainActor.run {
                        timerCountdownDuration = timerDuration
                        showTimerCountdown = true
                    }
                } else {
                    // Immediate capture with haptic
                    HapticManager.shared.photoCapture()
                    try await cameraManager.capturePhoto()
                    HapticManager.shared.success()
                }
            } catch {
                HapticManager.shared.error()
                setError(error.localizedDescription)
            }
        }
    }

    func executePhotoCapture() {
        Task {
            do {
                HapticManager.shared.photoCapture()
                try await cameraManager.capturePhoto()
                HapticManager.shared.success()
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
    }

    func toggleControlsVisibility() {
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
            var hasShownWarning = false

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

                if self.isRecording {
                    self.subscriptionManager.updateRecordingDuration(self.recordingDuration)

                    // Show warning haptic at 2:30 for free users
                    if self.subscriptionManager.showTimeWarning && !hasShownWarning {
                        HapticManager.shared.timeLimitWarning()
                        hasShownWarning = true
                    }

                    // Auto-stop recording when limit reached for free users
                    if self.subscriptionManager.recordingLimitReached && !self.isPremium {
                        HapticManager.shared.timeLimitReached()
                        try? await self.stopRecording()
                        await MainActor.run {
                            self.showPremiumUpgrade = true
                        }
                        hasShownWarning = false
                    }
                } else {
                    // Reset warning flag when not recording
                    hasShownWarning = false
                }

                // Check if we need to show the upgrade prompt
                if self.subscriptionManager.showUpgradePrompt {
                    await MainActor.run {
                        self.showPremiumUpgrade = true
                    }
                }
            }
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

    // MARK: - Error Handling
    private func setError(_ message: String) {
        errorMessage = message
        showError = true
    }
}

// MARK: - Recording Error
enum RecordingError: LocalizedError {
    case recordingLimitReached
    case invalidModeForRecording

    var errorDescription: String? {
        switch self {
        case .recordingLimitReached:
            return "Recording limit reached. Upgrade to Premium for unlimited recording."
        case .invalidModeForRecording:
            return "This capture mode does not support recording."
        }
    }
}
