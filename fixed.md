# DualLensPro Swift 6 / iOS 26 Audit (2025-02-15)

## 1. Executive summary
- Multi-camera capture is misconfigured: we never select multi-cam–capable formats, orientation handling runs off the main actor, and 4K/120fps presets exceed the hardware combinations Apple documents for dual capture [1][2][3][4].
- The combined photo/video pipeline cannot currently produce all advertised assets because continuation delegates clear buffers before compositing and asset writers silently ignore concurrent starts.
- Several UI buttons wire through to incomplete logic (e.g. premium gating, switch-screen mode) resulting in confusing state changes instead of the professional workflow described in README.
- Only a single unit test exists, covering subscription defaults; there is no validation protecting capture, multi-output saves, or permission flows.
- The sections below describe blocked features, code fixes (with before/after), and a prioritized backlog grounded in Apple’s Swift 6 + AVFoundation guidance.

## 2. Critical blockers (must fix before shipping)

### 2.1 `DeviceMonitorService` recursion will crash the app
Observed at `DualLensPro/DualLensPro/Services/DeviceMonitorService.swift:390-437`. The high-level `canStartRecording()` and `shouldStopRecording()` helpers call themselves recursively instead of delegating to the thermal/battery/memory variants. As soon as the TODO in `CameraViewModel` is re-enabled, touching these methods will produce an infinite recursion and a crash.

```swift
// Before — DeviceMonitorService.swift:390-405
func canStartRecording() -> (allowed: Bool, reasons: [String]) {
    var reasons: [String] = []

    let thermal = canStartRecording()
    if !thermal.allowed, let reason = thermal.reason {
        reasons.append(reason)
    }
    …
}
```

```swift
// After (conceptual)
func canStartRecording() -> (allowed: Bool, reasons: [String]) {
    var reasons: [String] = []

    let thermal = canStartRecordingThermal()
    if !thermal.allowed, let reason = thermal.reason {
        reasons.append(reason)
    }

    let battery = canStartRecordingBattery()
    …
}

private func canStartRecordingThermal() -> (allowed: Bool, reason: String?) { … }
```

Apply the same rename for `shouldStopRecording*`. This restores the intended aggregation and protects the app once device monitoring is switched on again.

### 2.2 Combined photo pipeline clears the buffers before compositing
`PhotoCaptureDelegate` (`DualLensPro/DualLensPro/Managers/DualCameraManager.swift:2453-2524`) always calls `onComplete(nil)` in a `defer` block. The capture closures in `captureFrontPhoto()` and `captureBackPhoto()` treat `nil` as “clear the cache”, so the dual-photo compositor never sees both camera frames before they are reset. Result: the advertised PiP photo is never written.

```swift
// Before — defer wipes the cache immediately
func photoOutput(_:didFinishProcessingPhoto:) {
    defer { onComplete(nil) }
    …
    self.onComplete(imageData)
    self.resumeOnce(.success(()))
}
```

```swift
// After (conceptual)
func photoOutput(_:didFinishProcessingPhoto:) {
    let cleanup: () -> Void = { self.onCleanup() }   // only removes delegate
    defer { cleanup() }

    guard let data = photo.fileDataRepresentation() else {
        resumeOnce(.failure(CameraError.photoOutputNotConfigured))
        return
    }

    onCapture(data)                                  // store buffer for compositing
    resumeOnce(.success(()))
}
```

Update the delegate to accept two closures—`onCapture(Data)` and `onCleanup()`—so cached pixel data survives until `trySaveCombinedPhotoIfReady()` runs. This follows Apple’s recommendation to resume the continuation exactly once per `AVCapturePhotoCaptureDelegate` callback [6].

### 2.3 Multi-cam configuration selects unsupported formats and reads orientation off-actor
`DualLensPro/DualLensPro/Managers/DualCameraManager.swift:531-640` grabs whatever `AVCaptureDevice.default(.builtInWideAngleCamera, …)` returns, never checking `format.isMultiCamSupported`, and immediately calls `addInputWithNoConnections`. On real hardware, the default formats are often 4K/60 and **not** multi-cam compatible; `AVCaptureMultiCamSession` will throw `AVError.Code.multicamNotSupported` when you start the session [1][2][3]. The companion orientation helpers (`videoRotationAngle`/`currentVideoOrientation` at lines 1603-1638) use `MainActor.assumeIsolated` from a background queue, which is undefined behaviour unless you are already running on the main actor [3][4].

```swift
// Before — format picked blindly, orientation pulled off-main
guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else { … }
let input = try AVCaptureDeviceInput(device: camera)
multiCamSession.addInputWithNoConnections(input)
let angle = videoRotationAngle()             // uses MainActor.assumeIsolated { UIDevice.current.orientation }
```

```swift
// After (conceptual)
let discovery = AVCaptureDevice.DiscoverySession(
    deviceTypes: [.builtInWideAngleCamera, .builtInUltraWideCamera, .builtInTrueDepthCamera],
    mediaType: .video,
    position: position
)

guard let camera = discovery.devices.first else { throw CameraError.deviceNotFound(position) }

if useMultiCam {
    if let multiCamFormat = camera.formats
        .filter({ $0.isMultiCamSupported })
        .sorted(by: preferredFormatOrdering)[safe: 0] {
        try camera.lockForConfiguration()
        camera.activeFormat = multiCamFormat
        camera.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
        camera.unlockForConfiguration()
    }
}

let input = try AVCaptureDeviceInput(device: camera)
…
let rotationCoordinator = AVCaptureDevice.RotationCoordinator(device: camera, previewLayer: previewLayer)
let angle = rotationCoordinator.videoRotationAngleForInterfaceOrientation(interfaceOrientation)
```

Choose a multi-cam–compatible format capped at 1080p/30, and push orientation updates through `AVCaptureDeviceRotationCoordinator` on the main actor [1][2][3][4]. The existing `currentVideoTransform()` helper can then be removed or rewritten to consume the coordinator output.

### 2.4 `startRecording()` hides state races instead of throwing
`DualLensPro/DualLensPro/Managers/DualCameraManager.swift:1417-1510` early-exits when `recordingState != .idle`, but does not throw or update UI state. If the user double-taps record, the UI keeps flashing “Recording”, yet the writers never started and no asset is produced.

```swift
// Before
guard recordingState == .idle else {
    print("❌ Not idle, returning")
    return
}
```

```swift
// After
guard recordingState == .idle else {
    await MainActor.run { errorMessage = "Recording already in progress" }
    throw CameraError.alreadyRecording
}
```

Surfacing the error lets `CameraViewModel.toggleRecording()` display the failure banner and prevents the app from slipping into a bad state.

## 3. Functional gaps and reliability risks

- **Unsupported capture presets:** `RecordingQuality.ultra` (4K/20 Mbps) and `CaptureMode.action` (120 fps) exceed Apple’s documented multi-cam limits. Limit combined recording to 1080p and the device’s advertised 30 fps multi-cam max, and surface a warning when a user selects an unsupported combination [1][3].
- **Expensive session setup runs on the main actor:** `setupSession()` performs device discovery, I/O removal, and reconnection directly on the `MainActor`. Move all capture session mutation onto `sessionQueue` to avoid UI stalls, mirroring the `AVCam` sample’s pattern [5].
- **Orientation metadata not applied to writers:** `currentVideoTransform()` is never used; both front/back writers and the compositor output adopt identity transforms, so portrait recordings still land sideways even after rotation metadata is set.
- **Photos save flow runs in detached tasks:** `saveVideoToPhotos` / `savePhotoToLibrary` spawn `Task.detached` blocks that swallow thrown errors and re-enter `PHPhotoLibrary` APIs without hop back to the main actor. Replace these with `withCheckedThrowingContinuation` on a dedicated photo queue and surface failures to `CameraViewModel`.
- **Subscription & premium gating are stubbed:** `SubscriptionManager` forces `.premium`, `canRecord` always returns `true`, and UI still shows upgrade prompts. Align the UI with the actual model or reintroduce StoreKit gating before release.
- **Switch-screen mode mutates capture state:** In `CameraViewModel.handleCaptureModeChange()` `.switchScreen` toggles cameras and then silently flips back to `.video`, which breaks any preview-binding watchers in SwiftUI. Use a dedicated flag for “swapped preview order” so the selected mode stays stable.
- **Advanced controls lose state:** `AdvancedControlsView` initialises `exposureValue` at 0 each time; there is no binding back to `DualCameraManager.exposureValue`, so the slider jumps when reopened.
- **Analytics and device-monitor hooks comment out code paths:** Many `TODO` markers reference `DeviceMonitorService.shared` and `AnalyticsService.shared`. With the bugs above resolved, wire these services back to the manager so the app can deliver its “pro” diagnostics story.

## 4. UI / button audit

| View (path) | Primary controls | Observations & required fixes |
| --- | --- | --- |
| `DualLensPro/DualLensPro/Views/DualCameraView.swift:132-236` | Tap-to-hide overlay, stacked previews | Needs disabled state while `isCameraReady` is false; previews should subscribe to `AVCaptureDeviceRotationCoordinator` so they rotate with the UI [4]. |
| `.../Views/ControlPanel.swift:28-82` | Gallery, record, camera switch | Record button never disables during `.processing`, leading to accidental re-entry. Hook the disabled state to `cameraManager.recordingState`. |
| `.../Views/Components/TopToolbar.swift` & private version in `DualCameraView` | Flash, timer, grid, settings | Two separate implementations risk drift. Consolidate into one component so timer/flash share logic. |
| `.../Views/AdvancedControlsView.swift:10-166` | White balance chips, exposure slider, stabilization buttons | Slider uses local `@State` instead of `cameraManager.exposureValue`, so reopening the panel resets values. Bind to the published value and reflect hardware limits per camera. |
| `.../Views/PermissionView.swift:20-188` | Grant permissions, manual retry | The "Grant Permissions" button should disable itself after permissions are denied and deep-link to Settings on subsequent taps. Present an alert when `PHPhotoLibrary.requestAuthorization` returns `.denied`. |
| `.../Views/SettingsView.swift:16-336` | Recording quality, aspect ratio, subscription | Selecting `.ultra` should be conditionally disabled on devices where `cameraManager.useMultiCam` is true, preventing unsupported combos. |
| `.../Views/PremiumUpgradeView.swift` | Upgrade CTA | Currently still shown even though `SubscriptionManager` forces premium. Hide the sheet until real billing is integrated to avoid confusing users. |
| `.../Views/RecordingLimitWarningView.swift` | Upgrade, close actions | Warns about limits that no longer exist; either remove it or reintroduce free-tier enforcement. |
| `.../Views/TimerCountdownView.swift` | Cancel button | Works, but the countdown calls `onComplete()` without re-checking `cameraManager.recordingState`. Guard against the user leaving the screen mid-countdown. |

## 5. Testing & tooling gaps
- `DualLensProTests/SubscriptionManagerTests.swift` is the only test and only covers the premium default path. Add unit tests for formatting helpers, plus integration tests that simulate `CameraViewModel.toggleRecording()` with a mocked `DualCameraManager`.
- Add UI tests for permissions: launch with denied camera/audio permissions and assert that `PermissionView` renders the call-to-action.
- Introduce lightweight logging/metrics around `RecordingCoordinator` to detect dropped frames, and automate a pipeline test (two short recordings back-to-back) on physical hardware.

## 6. Suggested hardening backlog (in priority order)

1. Fix `DeviceMonitorService` recursion and reinstate monitoring in `CameraViewModel`.
2. Split `PhotoCaptureDelegate` into capture vs. cleanup closures so combined photos export correctly.
3. Rework `setupSession()` to pick multi-cam formats, cap resolutions/frame rates, and use `AVCaptureDeviceRotationCoordinator` for previews and metadata.
4. Refactor `startRecording()`/`stopRecording()` to throw meaningful errors and align UI state with capture state.
5. Move capture session mutation to `sessionQueue` and remove the ad-hoc `Task.sleep` polling loops.
6. Gate UI presets (quality, action mode) based on actual `AVCaptureDevice` capabilities and surface helper copy when hardware falls back.
7. Clean up the photos save path to avoid detached tasks, propagate errors, and refresh the gallery via a dedicated Combine publisher.
8. Fold the duplicate toolbar implementations together and bind advanced controls to camera state.
9. Restore subscription logic or strip the premium upgrade surfaces until StoreKit is wired.

## 7. Reference links
[1]: https://developer.apple.com/documentation/avfoundation/avcapturemulticamsession  
[2]: https://developer.apple.com/documentation/avfoundation/avcapturedevice/format/3181801-ismulticamsupported  
[3]: https://developer.apple.com/documentation/avfoundation/cameras_and_media_capture/capturing_from_multiple_cameras_simultaneously  
[4]: https://developer.apple.com/documentation/avfoundation/avcapturedevicerotationcoordinator  
[5]: https://developer.apple.com/documentation/avfoundation/cameras_and_media_capture/avcam_building_a_camera_app  
[6]: https://developer.apple.com/documentation/avfoundation/avcapturephotocapturedelegate
