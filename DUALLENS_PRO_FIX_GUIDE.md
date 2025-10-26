# DualLensPro Fix Guide

A focused, repo‑specific plan to stabilize, finalize, and polish DualLensPro across UI/UX, functionality, concurrency, orientation, and monetization.

## Executive summary (priorities)
- Fix sideways media: set capture connection orientations and writer input transforms; keep them in sync with device rotation (videos + photos).
- Make “combined.mov” match preview (stacked dual view); add real-time compositor for combined video; optionally add a combined photo.
- Concurrency hardening: remove unsafe cross-thread state in DualCameraManager; use an internal actor or strict queue access; keep RecordingCoordinator as the sole writer owner.
- Photos save: retain Documents copy step; switch to async PHPhotoLibrary.performChanges; avoid blocking main thread.
- StoreKit 2: replace mocks with real products, purchase flow, and transaction listener; keep Configuration.storekit selected in the scheme for testing.
- UX: explicit single‑cam fallback labels; clearer 2:30 warning and 3:00 stop prompt; preview orientation updates.
- Tests: add a Unit Test target and include DualLensProTests/SubscriptionManagerTests.swift so tests actually execute.

---

## How the app works
- SwiftUI Views -> CameraViewModel (authorization, session lifecycle, capture mode, recording, premium gating)
- DualCameraManager (AVFoundation session setup and control; queues for session/video/audio/writer; saves to Photos)
- RecordingCoordinator actor (owns AVAssetWriters for front.mov, back.mov, combined.mov; HEVC video + AAC audio; starts at source time; thread-safe appends)
- SubscriptionManager (free vs premium gating; time limits; TODO: real StoreKit 2 entitlements)

---

## Sideways videos and photos: root cause and fixes
Symptoms
- Recorded videos appear rotated (e.g., sideways) compared to on-screen preview
- Photos show incorrect orientation

Root causes
- Preview layers are rotated via `videoRotationAngle = 90` (portrait) but recorded buffers are not guaranteed to carry the same orientation metadata or transform
- `AVCaptureConnection.videoOrientation` is not set for video data outputs and photo outputs
- `AVAssetWriterInput.transform` is not applied, so files may default to landscape

Reference (existing transform helper, not applied to writers):
```swift path=/Users/iamabillionaire/Downloads/Dual_Camera_App_Concept (3)/DualLensPro/DualLensPro/Managers/DualCameraManager.swift start=1080
    private func currentVideoTransform() -> CGAffineTransform {
        let orientation = UIDevice.current.orientation
        switch orientation {
        case .landscapeLeft:
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
```

Required fixes
1) Set connection orientation on creation and update on rotation
- For each created `AVCaptureConnection` (front/back video outputs and photo outputs), set `connection.videoOrientation = .portrait/.landscape...` based on current device orientation
- Observe `UIDevice.orientationDidChangeNotification` to update connections at runtime

Example helper:
```swift path=null start=null
func currentVideoOrientation() -> AVCaptureVideoOrientation {
  switch UIDevice.current.orientation {
  case .landscapeLeft: return .landscapeRight   // camera space vs UI space nuance
  case .landscapeRight: return .landscapeLeft
  case .portraitUpsideDown: return .portraitUpsideDown
  default: return .portrait
  }
}
```

Apply when wiring connections (multi-cam and single-cam paths):
```swift path=null start=null
if let connection = videoOutput.connection(with: .video) {
  connection.videoOrientation = currentVideoOrientation()
  if connection.isVideoStabilizationSupported { connection.preferredVideoStabilizationMode = .auto }
  if connection.isVideoMirroringSupported && position == .front { connection.isVideoMirrored = true }
}

// For photo connections you build manually, set:
photoConnection.videoOrientation = currentVideoOrientation()
```

2) Apply `AVAssetWriterInput.transform` at configuration
- Pass a `videoTransform` into `RecordingCoordinator.configure(…)` and set it on `frontVideoInput`, `backVideoInput`, and `combinedVideoInput`
- Update transform at the start of a recording if the device rotated since last configure

Example (RecordingCoordinator):
```swift path=null start=null
func configure(..., videoTransform: CGAffineTransform) throws {
  // after creating inputs
  frontVideoInput?.transform = videoTransform
  backVideoInput?.transform = videoTransform
  combinedVideoInput?.transform = videoTransform
}
```

In DualCameraManager before `setupAssetWriters()`:
```swift path=null start=null
let transform = currentVideoTransform()
try await coordinator.configure(..., videoTransform: transform)
```

3) Photos orientation
- Ensure the `AVCaptureConnection` that feeds the photo output is set to `videoOrientation`
- Prefer `AVCapturePhoto`’s metadata (it typically carries correct EXIF orientation) but setting connection orientation avoids surprises when composing

---

## “Stacked dual” saved output: match the on-screen preview
Symptoms
- `combined.mov` is currently just the back stream (not a stacked or PiP view)
- Users expect the saved combined file to match the stacked dual preview

Fix: Real-time compositor for combined.mov
- In `RecordingCoordinator`, composite the front and back buffers into a single frame before appending to `combinedVideoInput`
- Use Core Image (CIImage + CIContext) or vImage to draw:
  - Stacked: scale each feed to half height and draw one above the other
  - PiP: render back full-screen and front scaled in a corner
- Maintain synchronization by pairing nearest timestamps or driving from the back camera timeline

Sketch (pseudocode; allocate a reusable pixel buffer for output to avoid churn):
```swift path=null start=null
final class FrameCompositor {
  private let context = CIContext(options: [.priorityRequestLow: true])
  private let width: Int
  private let height: Int
  init(width: Int, height: Int) { self.width = width; self.height = height }

  func stacked(front: CVPixelBuffer?, back: CVPixelBuffer?) -> CVPixelBuffer? {
    guard let back = back ?? front else { return nil }
    let W = width, H = height
    let halfH = H / 2

    guard let out = allocatePixelBuffer(width: W, height: H) else { return nil }

    let backImg = CIImage(cvPixelBuffer: back).scaledToFit(width: W, height: halfH)
    let frontImg = (front != nil ? CIImage(cvPixelBuffer: front!) : backImg).scaledToFit(width: W, height: halfH)

    // Stack: front on top, back on bottom
    let top = frontImg.transformed(by: .init(translationX: 0, y: CGFloat(halfH)))
    let bottom = backImg
    let composed = top.composited(over: bottom)

    context.render(composed, to: out)
    return out
  }
}
```

Integration pattern in RecordingCoordinator:
```swift path=null start=null
// Keep last-seen front buffer per timestamp bucket
var lastFront: (buf: CVPixelBuffer, time: CMTime)?

func appendFrontPixelBuffer(_ pb: CVPixelBuffer, time: CMTime) throws {
  lastFront = (pb, time)
  // append to front writer as-is
}

func appendBackPixelBuffer(_ pb: CVPixelBuffer, time: CMTime) throws {
  // append to back writer as-is
  if let composed = compositor.stacked(front: lastFront?.buf, back: pb) {
    // append composed to combined input at `time`
  }
}
```

Performance tips
- Reuse pixel buffers via a CVPixelBufferPool
- Use `.BiPlanarVideoRange` pixel format to match inputs
- Keep Core Image context alive; avoid creating it per frame

Optional: add audio to per-camera files (currently only combined has audio)
- If desired, add audio inputs to front/back writers and duplicate audio sample appends

---

## Combined photo (optional, to match preview)
- After capturing both photos, build a stacked composite image and save it as a third asset
- Use CIImage to scale and stack; write to Photos via `PHAssetCreationRequest`

Sketch:
```swift path=null start=null
func saveCombinedPhoto(frontData: Data, backData: Data) async throws {
  let f = CIImage(data: frontData)!
  let b = CIImage(data: backData)!
  let W = max(f.extent.width, b.extent.width)
  let H = f.extent.height + b.extent.height
  let top = f.transformed(by: .init(translationX: 0, y: b.extent.height))
  let composed = top.composited(over: b)

  let ctx = CIContext()
  let colorSpace = CGColorSpaceCreateDeviceRGB()
  guard let out = ctx.heifRepresentation(of: composed, format: .RGBA8, colorSpace: colorSpace) else { return }

  try await PHPhotoLibrary.shared().performChanges {
    let req = PHAssetCreationRequest.forAsset()
    req.addResource(with: .photo, data: out, options: nil)
  }
}
```

---

## Photos saving: keep sandbox fix, make it async
- Continue copying temp files to Documents before saving to Photos (required for sandbox access)
- Replace `performChangesAndWait` on main thread with async `performChanges`

Current (blocking) pattern:
```swift path=/Users/iamabillionaire/Downloads/Dual_Camera_App_Concept (3)/DualLensPro/DualLensPro/Managers/DualCameraManager.swift start=1268
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            ...
            try photoLibrary.performChangesAndWait {
                let creationRequest = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: permanentURL)
                ...
            }
            ...
        }
```

Replace with non-blocking changes completion:
```swift path=null start=null
try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
  PHPhotoLibrary.shared().performChanges({
    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: permanentURL)
  }) { success, error in
    defer { try? FileManager.default.removeItem(at: permanentURL) }
    if let error = error { cont.resume(throwing: error) }
    else if success { cont.resume() }
    else { cont.resume(throwing: CameraError.failedToSaveToPhotos) }
  }
}
```

---

## Concurrency and threading
Issues
- `DualCameraManager` is `@MainActor` but holds many `nonisolated(unsafe)` mutable properties accessed on multiple queues (session/video/audio/writer)
- Risk of data races on flags like `isWriting`, `recordingStartTime`, and first-frame markers

Remediation
- Keep UI state on MainActor (@Published)
- Move mutable capture/writer flags into a small actor (e.g., `CaptureSessionState`) and read/write them through async methods, or remove `@MainActor` from the manager and strictly gate all access through designated queues
- Keep all writer state changes (startWriting/append/stop) exclusively in `RecordingCoordinator`

Sketch:
```swift path=null start=null
actor CaptureSessionState {
  var isWriting = false
  var recordingStartTime: CMTime?
  func begin(at t: CMTime) { isWriting = true; recordingStartTime = t }
  func end() { isWriting = false; recordingStartTime = nil }
}
```

---

## Center Stage toggle (clarify UX)
Current code toggles UI state only (no device setting change) and most iPhones don’t expose Center Stage.

Reference:
```swift path=/Users/iamabillionaire/Downloads/Dual_Camera_App_Concept (3)/DualLensPro/DualLensPro/Managers/DualCameraManager.swift start=936
    func toggleCenterStage() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            guard let device = self.frontCameraInput?.device else { return }

            if #available(iOS 14.5, *) {
                do {
                    try device.lockForConfiguration()
                    defer { device.unlockForConfiguration() }

                    Task { @MainActor in
                        self.isCenterStageEnabled.toggle()
                    }

                    // Note: Center Stage control requires specific hardware; keep the UI disabled if unsupported.
                } catch { ... }
            }
        }
    }
```

Recommended UX
- Detect availability and disable the toggle with a short explanation if unsupported
- If adding real control later, set the device property (where available) and keep `isCenterStageEnabled` in sync with hardware state

---

## StoreKit 2 subscriptions
- Load products via `Product.products(for:)`
- Purchase via `product.purchase()`; handle `.success/.pending/.userCancelled`
- Listen to `Transaction.updates` and set entitlements on launch via `Transaction.currentEntitlements`
- Maintain `subscriptionTier` from verified transactions; UserDefaults can be kept for UI cache only

Skeleton:
```swift path=null start=null
@MainActor
final class SubscriptionManager: ObservableObject {
  @Published var subscriptionTier: SubscriptionTier = .free
  private var updatesTask: Task<Void, Never>?

  func start() {
    updatesTask = Task { await listenForTransactions() }
    Task { await refreshEntitlements() }
  }
}
```

Testing: select `DualLensPro/Configuration.storekit` in scheme.

---

## UI/UX polish
- Single‑cam fallback: show a small “Single Camera Mode” ribbon if multi-cam unsupported; hide front preview cleanly
- Time-limit: at 2:30 show non-modal warning; auto-stop at 3:00 with upgrade modal; ensure haptics fire exactly once (VM already tracks this; keep the guard)
- Orientation: update preview orientation on device rotation to match recorded result

---

## Tests
- Add a Unit Test target “DualLensProTests” and include `DualLensProTests/SubscriptionManagerTests.swift`
- Run all tests:
```bash path=null start=null
xcodebuild test \
  -project DualLensPro/DualLensPro.xcodeproj \
  -scheme DualLensPro \
  -destination 'platform=iOS Simulator,name=iPhone 15,OS=latest'
```
- Run a single test:
```bash path=null start=null
xcodebuild test \
  -project DualLensPro/DualLensPro.xcodeproj \
  -scheme DualLensPro \
  -destination 'platform=iOS Simulator,name=iPhone 15,OS=latest' \
  -only-testing:DualLensProTests/SubscriptionManagerTests/testFreeUserRecordingLimit
```

---

## Step-by-step implementation checklist
1) Orientation
- [ ] Add helper to compute `AVCaptureVideoOrientation`
- [ ] Set `videoOrientation` on video and photo connections when created
- [ ] Observe device orientation and update connections at runtime
- [ ] Pass `videoTransform` to `RecordingCoordinator.configure()` and set on inputs

2) Combined media
- [ ] Add `FrameCompositor` (CI-based)
- [ ] In `appendBackPixelBuffer`, create stacked buffer and append to combined writer
- [ ] Optional: create combined photo after dual capture

3) Concurrency
- [ ] Introduce `CaptureSessionState` actor (or unify queue access)
- [ ] Remove/replace `nonisolated(unsafe)` mutable state

4) Photos save pipeline
- [ ] Keep Documents copy; switch to async `performChanges`

5) StoreKit 2
- [ ] Load products; implement purchase flow
- [ ] Add transaction listener; set entitlements on launch

6) UX
- [ ] Single-cam fallback label; preview rotation update; refine time-limit prompts

7) Tests
- [ ] Add Xcode unit test target; include existing tests; run in CI/local

---

## Useful build commands
- List schemes
```bash path=null start=null
xcodebuild -list -project DualLensPro/DualLensPro.xcodeproj
```
- Build (simulator)
```bash path=null start=null
xcodebuild build \
  -project DualLensPro/DualLensPro.xcodeproj \
  -scheme DualLensPro \
  -destination 'platform=iOS Simulator,name=iPhone 15,OS=latest'
```
- Open in Xcode
```bash path=null start=null
open DualLensPro/DualLensPro.xcodeproj
```

---

## Final notes
- Keep writer work off capture delegate threads; never block `writerQueue`
- Test orientation changes mid-recording (rotate device) and verify saved outputs remain correct
- Validate Photos permissions and space checks before long recordings

---

## Combined photo (stacked) – implement now
Photos already save with correct orientation, but the merged (stacked) photo isn’t produced. Implement a combined photo pipeline that mirrors the combined video behavior.

Implementation plan
- Capture both photos as data (front and back) in memory alongside individual saves.
- Compose a stacked CIImage (front on top, back on bottom) and save it as a third asset.
- Gate with a setting (e.g., “Save Combined Photo”) if you want to make it optional.

Required changes in DualCameraManager
1) Modify PhotoCaptureDelegate to hand back Data
- Add a completion closure carrying the JPEG data so the manager can aggregate both sides.

2) Aggregate both sides and save composed result
- When both front/back complete, call a `saveCombinedPhoto(frontData:backData:)` helper.

Sketch
```swift path=null start=null
private var lastFrontPhotoData: Data?
private var lastBackPhotoData: Data?

private func captureFrontPhoto() async throws {
  ...
  let delegate = PhotoCaptureDelegate(camera: "front") { [weak self] result in
    guard let self else { return }
    switch result {
    case .success(let data):
      self.lastFrontPhotoData = data
      Task { await self.trySaveCombinedPhotoIfReady() }
    case .failure(let error):
      // handle
    }
  }
  ...
}

private func captureBackPhoto() async throws { /* same, assign lastBackPhotoData */ }

@MainActor
private func trySaveCombinedPhotoIfReady() async {
  guard let f = lastFrontPhotoData, let b = lastBackPhotoData else { return }
  do {
    try await saveCombinedPhoto(frontData: f, backData: b)
  } catch {
    errorMessage = "Failed to save combined photo: \(error.localizedDescription)"
  }
  lastFrontPhotoData = nil
  lastBackPhotoData = nil
}

private func saveCombinedPhoto(frontData: Data, backData: Data) async throws {
  let f = CIImage(data: frontData)!
  let b = CIImage(data: backData)!
  let W = max(f.extent.width, b.extent.width)
  let H = f.extent.height + b.extent.height
  let top = f.transformed(by: .init(translationX: 0, y: b.extent.height))
  let composed = top.composited(over: b)
  let ctx = CIContext()
  let cs = CGColorSpaceCreateDeviceRGB()
  guard let heif = ctx.heifRepresentation(of: composed, format: .RGBA8, colorSpace: cs) else { throw CameraError.photoOutputNotConfigured }

  try await PHPhotoLibrary.shared().performChanges {
    let req = PHAssetCreationRequest.forAsset()
    req.addResource(with: .photo, data: heif, options: nil)
  }

  NotificationCenter.default.post(name: .init("RefreshGalleryThumbnail"), object: nil)
}
```

Notes
- Keep saving the two individual photos (existing behavior) so users get all three assets.
- If you prefer PiP instead of stacked, scale front and place into a corner.

---

## Additional production issues and fixes

- Privacy manifest inclusion
  - Ensure `DualLensPro/PrivacyInfo.xcprivacy` is added to the app target’s Copy Bundle Resources so it ships in the app; otherwise App Store submission will fail.

- Color range mismatch (video output vs writer adaptors)
  - VideoDataOutput uses `kCVPixelFormatType_420YpCbCr8BiPlanarFullRange` (420f) while RecordingCoordinator’s adaptors use `kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange` (420v). Align both to the same format (prefer 420v for hardware paths) to avoid subtle gamma/levels shifts.

- Writer expected frame rate hard-coded to 30
  - In `RecordingCoordinator.configure`, `AVVideoExpectedSourceFrameRateKey` is set to 30 regardless of mode. Set this to the active capture frame rate (e.g., from `CaptureMode.frameRate`) so 60fps exports are correctly hinted.

- Capture device format vs frame rate
  - `DualCameraManager` sets min/max frame durations against the current `activeFormat` but does not ensure the format supports the requested frame rate. Pick a compatible `AVCaptureDevice.Format` that matches the selected frame rate (and, if desired, recording quality dimensions) before setting durations.

- Zoom update guard uses published `isSessionRunning`
  - `updateZoom` checks the `isSessionRunning` @Published property from a background queue. Instead, read `activeSession.isRunning` on `sessionQueue` to avoid cross-actor state reads.

- Multi-cam connection cleanup
  - When clearing connections for a reconfigure, only call `removeConnection` on `AVCaptureMultiCamSession` (cast and guard) to avoid undefined behavior on single-cam `AVCaptureSession`.

- Front mirroring behavior
  - You mirror the front preview and output. Confirm whether exported front/back files and combined output should be mirrored; many apps mirror preview only, not files. Make this behavior a setting.

- Thermal management
  - Re-add a lightweight thermal observer (e.g., `ProcessInfo.thermalStateDidChangeNotification`) to drop quality or warn users when the device overheats in long dual-cam sessions.

- Logging hygiene
  - Wrap verbose prints in `#if DEBUG` and switch to `os.Logger` categories for production diagnostics.

- StoreKit product IDs sanity
  - Ensure `com.duallens.premium.monthly/yearly` match App Store Connect exactly; mismatches cause product load failures.

- Album organization (optional)
  - Use `PhotoLibraryService.createDualLensProAlbum()` and add created assets to keep the user’s library tidy.

---
