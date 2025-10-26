# WARP.md

This file provides guidance to WARP (warp.dev) when working with code in this repository.

- Primary app: DualLensPro (Swift 6, SwiftUI, AVFoundation). DualCameraApp is an earlier concept; prioritize DualLensPro for changes.

Common terminal commands
- List targets/schemes for DualLensPro
```bash path=null start=null
xcodebuild -list -project DualLensPro/DualLensPro.xcodeproj
```
- Build for Simulator (useful for compiling and unit tests; camera features won’t work on Simulator)
```bash path=null start=null
xcodebuild build \
  -project DualLensPro/DualLensPro.xcodeproj \
  -scheme DualLensPro \
  -destination 'platform=iOS Simulator,name=iPhone 15,OS=latest'
```
- Open in Xcode (recommended for running on device and code signing)
```bash path=null start=null
open DualLensPro/DualLensPro.xcodeproj
```
- Run all unit tests (ensure a test target exists; see “Tests” note below)
```bash path=null start=null
xcodebuild test \
  -project DualLensPro/DualLensPro.xcodeproj \
  -scheme DualLensPro \
  -destination 'platform=iOS Simulator,name=iPhone 15,OS=latest'
```
- Run a single test (example)
```bash path=null start=null
xcodebuild test \
  -project DualLensPro/DualLensPro.xcodeproj \
  -scheme DualLensPro \
  -destination 'platform=iOS Simulator,name=iPhone 15,OS=latest' \
  -only-testing:DualLensProTests/SubscriptionManagerTests/testFreeUserRecordingLimit
```
- Check device multi‑cam support (standalone script)
```bash path=null start=null
swift DualLensPro/test_multicam.swift
```
- Lint/format
```text path=null start=null
No SwiftLint/SwiftFormat config found in this repo.
```

High‑level architecture (DualLensPro)
- UI (SwiftUI)
  - Views: DualCameraView, CameraPreviewView (UIKit preview bridge), control panel components, overlays, settings.
  - Design: glassmorphism via Extensions/GlassEffect.
- ViewModels (MVVM)
  - CameraViewModel orchestrates authorization, session lifecycle, capture mode changes, recording, premium gating, and UI state.
  - SettingsViewModel, GalleryViewModel support their respective views.
- Managers and Services
  - DualCameraManager: configures AVCaptureSession/AVCaptureMultiCamSession, manages inputs/outputs, zoom/focus/exposure/flash/grid/timer, Center Stage, Photos save, and session threading. Uses dedicated queues (session/video/audio/writer) and an unfair lock to expose safe state.
  - SubscriptionManager: free vs premium gating (3‑minute limit for free), product IDs, simple persistence, upgrade prompts.
  - HapticManager: tactile feedback for mode/zoom/recording events.
  - PhotoLibraryService: latest thumbnail/fetch for gallery entry points.
- Actor for recording pipeline
  - RecordingCoordinator (Swift 6 actor): thread‑safe AVAssetWriter coordination for three outputs (front.mov, back.mov, combined.mov), HEVC video, AAC audio. Starts sessions at source timestamps and finishes writers concurrently.
- Models / Config
  - CameraConfiguration, CaptureMode, RecordingQuality, CameraPosition, RecordingState, VideoOutput, white balance and stabilization enums.
- Concurrency and threading
  - UI on MainActor; capture setup on a serial sessionQueue; sample processing on video/audio queues; writing serialized via writerQueue and actor isolation.

Repo‑specific operational facts
- Requirements (from DualLensPro/README.md): iOS 18+, Xcode 16+, Swift 6. Physical device required for camera features; Simulator has no camera.
- Outputs: each recording produces three videos (front, back, combined). Saving to Photos copies temp files to Documents first to satisfy Photos sandboxing.
- StoreKit testing: DualLensPro/Configuration.storekit exists. Select it in the scheme for purchase testing.
- Privacy manifest: DualLensPro/PrivacyInfo.xcprivacy exists and must be included in the app target to meet App Store privacy requirements.
- Deployment target and toolchain: project sets iOS 18.0 and Swift 6 in build settings.
- Tests: DualLensProTests/SubscriptionManagerTests.swift exists with multiple test methods (e.g., testFreeUserRecordingLimit). The project file currently lists only the app target; create a “DualLensProTests” unit test target in Xcode and add this file to it before running xcodebuild test.
- Secondary project: DualCameraApp/ contains an earlier concept (similar MVVM structure with Services/ViewModels/Views). Treat DualLensPro as the production app.

Gotchas (repo‑specific)
- Simulator vs device: compile and run tests on Simulator, but all camera behavior must be validated on a physical iPhone (XS or later for multi‑cam).
- Multi‑cam fallback: DualCameraManager will fall back to single‑cam if AVCaptureMultiCamSession isn’t supported; UI still renders a back camera preview in that mode.
- Threading: do not block writerQueue or call long‑running work on capture delegate callbacks; the RecordingCoordinator actor expects timely feeding of pixel/audio buffers.
- Photos permissions: saving uses PHPhotoLibrary (add‑only on iOS 14+). If permissions are denied, recordings won’t be persisted.

Key docs to consult in this repo
- START_HERE.md: integration order, added production files (Actors/RecordingCoordinator.swift, PrivacyInfo.xcprivacy, Configuration.storekit, tests), and action plan.
- DualLensPro/README.md: requirements, features, project structure, and troubleshooting that affect build/run.
- CRITICAL_FIXES_IMPLEMENTED.md, DUALLENS_PRO_PRODUCTION_ANALYSIS.md, README_PRODUCTION_FIXES.md: background on concurrency, AVFoundation, and monetization details referenced by the code.
