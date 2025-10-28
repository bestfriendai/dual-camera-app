# Dual Camera Orientation & Aspect Ratio Fix Guide

## 🔴 Critical Issues Identified

Based on the screenshot and code analysis, there are **4 critical issues**:

1. **Front camera saved with weird proportions** - Stretched/distorted aspect ratio
2. **Back camera records sideways** - Incorrect orientation in saved video
3. **Merged screen front camera sideways** - Front camera rotated incorrectly in both preview and saved video
4. **Camera buttons disappearing** - UI controls vanishing during recording

---

## 🔍 Root Cause Analysis

### Issue 1-3: Orientation & Aspect Ratio Problems

**The Problem:**
The `FrameCompositor` receives pixel buffers that are **always in landscape orientation** (1920x1080) from the camera hardware, but it doesn't apply any orientation transforms before compositing them. This causes:

- Front camera appears sideways because it's not rotated
- Back camera appears sideways for the same reason  
- Aspect ratios are wrong because landscape buffers are being scaled to portrait dimensions without rotation

**Code Evidence:**

```swift
// FrameCompositor.swift lines 186-209
private func stackedBuffers(front: CVPixelBuffer, back: CVPixelBuffer) -> CVPixelBuffer? {
    // Create CIImages from pixel buffers
    let frontImage = CIImage(cvPixelBuffer: front)  // ❌ No orientation applied
    let backImage = CIImage(cvPixelBuffer: back)    // ❌ No orientation applied
    
    // Scale images to fit half-height
    let frontScaled = scaleToFit(image: frontImage, width: outputWidth, height: halfHeight)
    let backScaled = scaleToFit(image: backImage, width: outputWidth, height: halfHeight)
    // ...
}
```

**Why This Happens:**
1. Camera hardware captures in **landscape** (1920x1080) regardless of device orientation
2. `AVCaptureConnection.videoRotationAngle` only sets **metadata**, not physical rotation
3. `FrameCompositor` doesn't know device orientation or that it needs to rotate images
4. Front camera mirroring is applied at connection level but not in compositor

---

## ✅ The Fix: Step-by-Step

### Step 1: Pass Device Orientation to FrameCompositor

**File:** `DualLensPro/DualLensPro/FrameCompositor.swift`

Add orientation tracking to the compositor:

```swift
final class FrameCompositor: Sendable {
    private let context: CIContext
    private let width: Int
    private let height: Int
    
    // ✅ ADD: Track device orientation
    private let deviceOrientation: UIDeviceOrientation
    private let isPortrait: Bool
    
    // ✅ MODIFY: Add orientation parameter
    init(width: Int, height: Int, deviceOrientation: UIDeviceOrientation) {
        self.width = width
        self.height = height
        self.deviceOrientation = deviceOrientation
        
        // Determine if we're in portrait mode
        self.isPortrait = (deviceOrientation == .portrait || 
                          deviceOrientation == .portraitUpsideDown ||
                          deviceOrientation == .unknown || 
                          deviceOrientation == .faceUp || 
                          deviceOrientation == .faceDown)
        
        // ... rest of init
        print("✅ FrameCompositor initialized: \(width)x\(height), orientation: \(deviceOrientation.rawValue), isPortrait: \(isPortrait)")
    }
}
```

### Step 2: Apply Orientation Transforms in Compositor

**File:** `DualLensPro/DualLensPro/FrameCompositor.swift`

Add a helper method to orient CIImages correctly:

```swift
// ✅ ADD: New helper method to apply proper orientation
private func orientImage(_ image: CIImage, isFrontCamera: Bool) -> CIImage {
    var oriented = image
    
    // Step 1: Rotate based on device orientation
    // Camera buffers are always landscape (1920x1080), we need to rotate for portrait
    if isPortrait {
        // Rotate 90° clockwise to convert landscape → portrait
        oriented = oriented.oriented(.right)
        print("🔄 Rotated image 90° for portrait mode")
    }
    
    // Step 2: Mirror front camera horizontally (selfie mirror effect)
    if isFrontCamera {
        // Mirror horizontally by flipping X axis
        let transform = CGAffineTransform(scaleX: -1, y: 1)
            .translatedBy(x: -oriented.extent.width, y: 0)
        oriented = oriented.transformed(by: transform)
        print("🪞 Mirrored front camera image")
    }
    
    return oriented
}
```

### Step 3: Use Oriented Images in Stacking

**File:** `DualLensPro/DualLensPro/FrameCompositor.swift`

Modify `stackedBuffers` to use oriented images:

```swift
private func stackedBuffers(front: CVPixelBuffer, back: CVPixelBuffer) -> CVPixelBuffer? {
    guard let outputBuffer = allocatePixelBuffer() else {
        print("❌ FrameCompositor: Failed to allocate output buffer")
        return nil
    }

    // ✅ MODIFY: Apply orientation before creating CIImages
    let frontImage = CIImage(cvPixelBuffer: front)
    let backImage = CIImage(cvPixelBuffer: back)
    
    // ✅ NEW: Orient images correctly
    let frontOriented = orientImage(frontImage, isFrontCamera: true)
    let backOriented = orientImage(backImage, isFrontCamera: false)
    
    // Calculate dimensions for stacking
    let outputWidth = CGFloat(width)
    let outputHeight = CGFloat(height)
    let halfHeight = outputHeight / 2
    
    // ✅ MODIFY: Use oriented images
    let frontScaled = scaleToFit(image: frontOriented, width: outputWidth, height: halfHeight)
    let backScaled = scaleToFit(image: backOriented, width: outputWidth, height: halfHeight)
    
    // Position front on top, back on bottom
    let frontPositioned = frontScaled.transformed(by: CGAffineTransform(translationX: 0, y: halfHeight))
    let backPositioned = backScaled
    
    // Composite: front over back
    let composed = frontPositioned.composited(over: backPositioned)
    
    // Render to output buffer
    context.render(composed, to: outputBuffer)
    
    return outputBuffer
}
```

### Step 4: Update RecordingCoordinator to Pass Orientation

**File:** `DualLensPro/DualLensPro/Actors/RecordingCoordinator.swift`

Modify the `configure` method:

```swift
// ✅ MODIFY: Add deviceOrientation parameter
func configure(
    frontURL: URL,
    backURL: URL,
    combinedURL: URL,
    dimensions: (width: Int, height: Int),
    combinedDimensions: (width: Int, height: Int),
    bitRate: Int,
    frameRate: Int,
    videoTransform: CGAffineTransform,
    deviceOrientation: UIDeviceOrientation  // ✅ ADD THIS
) throws {
    // ... existing code ...
    
    // ✅ MODIFY: Pass orientation to compositor
    compositor = FrameCompositor(
        width: combinedDimensions.width, 
        height: combinedDimensions.height,
        deviceOrientation: deviceOrientation  // ✅ ADD THIS
    )
    print("✅ FrameCompositor initialized with orientation: \(deviceOrientation.rawValue)")
}
```

### Step 5: Update DualCameraManager to Pass Orientation

**File:** `DualLensPro/DualLensPro/Managers/DualCameraManager.swift`

Find the `setupRecordingWriters` method (around line 1857) and modify:

```swift
// ✅ MODIFY: Pass device orientation to coordinator
try await coordinator.configure(
    frontURL: frontURL,
    backURL: backURL,
    combinedURL: combinedURL,
    dimensions: dimensions,
    combinedDimensions: combinedDimensions,
    bitRate: bitRate,
    frameRate: frameRate,
    videoTransform: transform,
    deviceOrientation: orientation  // ✅ ADD THIS (orientation is already captured on line 1825)
)
```

---

## 🐛 Issue 4: Pinch Zoom Not Working on Both Cameras

**Root Cause:** The pinch zoom gesture is working correctly in the code, but there might be a gesture conflict or the zoom ranges aren't being properly initialized.

**Current Implementation Status:**
✅ Gesture recognizer is set up correctly in `CameraPreviewView.swift`
✅ Zoom clamping uses device capabilities (lines 98-100)
✅ Simultaneous gesture recognition enabled (line 113)
✅ Zoom ranges are queried from device (CameraConfiguration.swift lines 73-92)

**Potential Issues:**

1. **Zoom ranges not initialized** - `updateZoomRanges()` might not be called during camera setup
2. **Gesture conflicts** - Other gestures might be blocking pinch
3. **Session not running** - Zoom can't be applied if session isn't active

**Fix Steps:**

### Step 1: Ensure Zoom Ranges Are Initialized

**File:** `DualLensPro/DualLensPro/Managers/DualCameraManager.swift`

Find the camera setup method (around line 530) and ensure zoom ranges are updated:

```swift
private func setupCamera(position: AVCaptureDevice.Position) async throws {
    guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else {
        throw CameraError.deviceNotFound(position)
    }

    // ✅ ADD: Update zoom ranges after getting camera device
    await MainActor.run {
        if position == .front {
            configuration.updateZoomRanges(frontCamera: camera, backCamera: nil)
        } else {
            configuration.updateZoomRanges(frontCamera: nil, backCamera: camera)
        }
    }

    // ... rest of setup
}
```

### Step 2: Verify Gesture Priority

**File:** `DualLensPro/DualLensPro/Views/CameraPreviewView.swift`

Ensure pinch gesture has priority (already implemented, but verify):

```swift
// Line 53 - Already correct
pinchGesture.delegate = context.coordinator
```

### Step 3: Add Debug Logging

Add logging to verify zoom is being applied:

```swift
// In CameraPreviewView.swift Coordinator.handlePinch (line 102)
onZoomChange(clampedZoom)
print("🔍 Zoom changed: \(clampedZoom)x (min: \(minZoom), max: \(maxZoom))")
```

### Step 4: Check Session State

**File:** `DualLensPro/DualLensPro/Managers/DualCameraManager.swift`

Verify zoom is only applied when session is running (line 1098):

```swift
guard isRunning else {
    print("⚠️ Cannot update zoom - session not running")
    return
}
```

---

## 🐛 Issue 5: Camera Buttons Disappearing

**Root Cause:** This is likely a SwiftUI state management issue where the UI is being redrawn incorrectly during recording state changes.

**Quick Fix Options:**

1. **Check ControlPanel visibility logic** - Ensure `controlsVisible` state isn't being toggled unexpectedly
2. **Add explicit z-index** - Make sure buttons are always on top layer
3. **Check for animation conflicts** - Recording animations might be hiding buttons

**File to Check:** `DualLensPro/DualLensPro/Views/ControlPanel.swift`

Look for:
- `.opacity()` modifiers that might be set to 0
- `.hidden()` calls
- Animation timing conflicts
- State changes that trigger view rebuilds

---

## 📸 Issue 6: Photo Capture Should Save 3 Photos (Front, Back, Merged)

**Current Behavior:**
- Photos are saved individually (front and back)
- A combined/merged photo is created and saved
- ✅ This is already working correctly!

**How It Works:**

1. **Individual Photos Saved** (lines 2556-2558 in DualCameraManager.swift):
   - Front camera photo saved to Photos library
   - Back camera photo saved to Photos library

2. **Combined Photo Created** (lines 1223-1273 in DualCameraManager.swift):
   - Both photos are captured concurrently
   - Photo data is cached (`lastFrontPhotoData`, `lastBackPhotoData`)
   - `trySaveCombinedPhotoIfReady()` is called after each photo completes
   - When both are ready, `saveCombinedPhoto()` creates a stacked composition
   - Front camera on top, back camera on bottom (same as video preview)
   - Saved as HEIF format to Photos library

**Expected Result:**
✅ **3 photos saved to Photos library:**
1. Front camera photo (individual)
2. Back camera photo (individual)
3. Combined/merged photo (stacked: front on top, back on bottom)

**Issue:** The combined photo composition doesn't apply orientation transforms!

**Fix Required:**

**File:** `DualLensPro/DualLensPro/Managers/DualCameraManager.swift`

Modify `saveCombinedPhoto()` method (around line 1223) to apply orientation:

```swift
private func saveCombinedPhoto(frontData: Data, backData: Data) async throws {
    guard let frontImage = CIImage(data: frontData),
          let backImage = CIImage(data: backData) else {
        throw CameraError.photoOutputNotConfigured
    }

    // ✅ ADD: Apply orientation transforms (same as video)
    let orientation = UIDevice.current.orientation
    let isPortrait = (orientation == .portrait ||
                     orientation == .portraitUpsideDown ||
                     orientation == .unknown ||
                     orientation == .faceUp ||
                     orientation == .faceDown)

    var frontOriented = frontImage
    var backOriented = backImage

    // Rotate for portrait mode
    if isPortrait {
        frontOriented = frontOriented.oriented(.right)
        backOriented = backOriented.oriented(.right)
    }

    // Mirror front camera
    let mirrorTransform = CGAffineTransform(scaleX: -1, y: 1)
        .translatedBy(x: -frontOriented.extent.width, y: 0)
    frontOriented = frontOriented.transformed(by: mirrorTransform)

    // Calculate dimensions for stacking
    let frontExtent = frontOriented.extent
    let backExtent = backOriented.extent
    let maxWidth = max(frontExtent.width, backExtent.width)
    let totalHeight = frontExtent.height + backExtent.height

    // Position front on top, back on bottom
    let frontPositioned = frontOriented.transformed(by: CGAffineTransform(translationX: 0, y: backExtent.height))
    let backPositioned = backOriented

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
```

---

## 🧪 Testing the Fix

### Test 1: Portrait Recording
1. Hold phone in portrait mode
2. Start recording
3. **Expected:** Both cameras should be upright in merged view
4. **Expected:** Front camera should be mirrored (selfie mode)
5. Save and check video in Photos app

### Test 2: Landscape Recording  
1. Hold phone in landscape mode
2. Start recording
3. **Expected:** Both cameras should be in landscape orientation
4. **Expected:** No rotation artifacts or black bars

### Test 3: Aspect Ratios
1. Record in portrait mode
2. Check saved videos:
   - Front camera video should be 1080x1920 (portrait)
   - Back camera video should be 1080x1920 (portrait)
   - Merged video should be 1080x1920 (portrait)
3. **Expected:** No stretching or distortion

---

## 📋 Implementation Checklist

### Video Orientation Fixes
- [ ] Add `deviceOrientation` parameter to `FrameCompositor.init()`
- [ ] Add `orientImage()` helper method to `FrameCompositor`
- [ ] Modify `stackedBuffers()` to use oriented images
- [ ] Add `deviceOrientation` parameter to `RecordingCoordinator.configure()`
- [ ] Update `DualCameraManager.setupRecordingWriters()` to pass orientation

### Photo Orientation Fixes
- [ ] Modify `saveCombinedPhoto()` to apply orientation transforms
- [ ] Add portrait mode rotation to photo composition
- [ ] Add front camera mirroring to photo composition

### Pinch Zoom Fixes
- [ ] Ensure `updateZoomRanges()` is called during camera setup
- [ ] Add debug logging to verify zoom values
- [ ] Test pinch zoom on both front and back cameras

### UI Fixes
- [ ] Fix camera buttons disappearing issue
- [ ] Add z-index to ensure buttons stay on top

### Testing
- [ ] Test portrait video recording
- [ ] Test landscape video recording
- [ ] Test front camera mirroring in videos
- [ ] Test portrait photo capture (3 photos saved)
- [ ] Test landscape photo capture (3 photos saved)
- [ ] Test front camera mirroring in photos
- [ ] Test pinch zoom on front camera
- [ ] Test pinch zoom on back camera
- [ ] Test on real device (iPhone 17)

---

## 🎯 Expected Results After Fix

### Videos
✅ **Front camera video:** Upright, mirrored, correct aspect ratio
✅ **Back camera video:** Upright, correct aspect ratio
✅ **Merged video:** Both cameras stacked vertically, both upright
✅ **Video metadata:** Correct orientation for all 3 videos

### Photos
✅ **Front camera photo:** Upright, mirrored, correct aspect ratio
✅ **Back camera photo:** Upright, correct aspect ratio
✅ **Merged photo:** Both cameras stacked vertically, both upright
✅ **3 photos saved:** Individual front, individual back, combined/merged

### UI
✅ **Pinch zoom:** Works on both front and back cameras
✅ **Camera buttons:** Always visible and responsive
✅ **Preview:** Matches saved output orientation

---

## 🚨 Common Pitfalls to Avoid

1. **Don't rotate pixel buffers physically** - Use CIImage transforms (GPU-accelerated)
2. **Don't forget front camera mirroring** - Users expect selfie mirror effect
3. **Test on real device** - Simulator doesn't accurately represent camera behavior
4. **Check all three outputs** - Front, back, AND merged videos must all be correct
5. **Verify orientation metadata** - Use QuickTime Player to check video metadata

---

## 📞 Next Steps

1. Implement the fixes in order (Steps 1-5)
2. Build and deploy to iPhone 17
3. Test all scenarios
4. If buttons still disappear, investigate ControlPanel.swift separately
5. Report back with results


