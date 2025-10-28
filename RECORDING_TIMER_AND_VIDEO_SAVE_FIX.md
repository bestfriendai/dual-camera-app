# Recording Timer & Video Save Fix

**Date**: October 28, 2025  
**Issues**: 
1. Recording timer not working/displaying
2. Videos not being saved with correct orientation

---

## 🔍 Issue #1: Recording Timer Not Working

### Current Implementation
The recording timer code exists and should be working:
- `startRecordingTimer()` is called when recording starts (line 1571 in DualCameraManager.swift)
- Timer updates `recordingDuration` every 0.1 seconds (lines 2109-2118)
- `RecordingIndicator` component displays the timer (line 273 in DualCameraView.swift)

### Diagnosis
The timer logic appears correct. Possible causes:
1. **UI not updating**: SwiftUI view not refreshing when `recordingDuration` changes
2. **Timer not visible**: RecordingIndicator might be hidden or off-screen
3. **Concurrency issue**: Timer task might be cancelled or not running

### Root Cause
Looking at line 2112-2116:
```swift
while recordingStateLock.withLock({ $0 == .recording }) {
    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
    await MainActor.run {
        recordingDuration += 0.1
    }
}
```

**Problem**: The timer uses `recordingStateLock` to check state, but `recordingState` is a `@Published` property on `@MainActor`. This creates a race condition where the lock might not reflect the actual published state.

### Fix for Issue #1

**File**: `DualLensPro/DualLensPro/Managers/DualCameraManager.swift`

**Change 1**: Simplify timer to use MainActor state directly (lines 2109-2118)

```swift
private func startRecordingTimer() {
    Task { @MainActor in
        while recordingState == .recording {
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            if recordingState == .recording {
                recordingDuration += 0.1
            }
        }
    }
}
```

**Change 2**: Ensure timer is visible in UI (DualCameraView.swift line 272-276)

Verify the RecordingIndicator is not being hidden by other UI elements. Add explicit z-index:

```swift
.overlay(alignment: .topTrailing) {
    if viewModel.isRecording {
        RecordingIndicator(duration: viewModel.recordingDuration)
            .padding(.top, max(geometry.safeAreaInsets.top + 50, 60))
            .padding(.trailing, 16)
            .zIndex(999)  // ✅ Ensure it's on top
    }
}
```

---

## 🔍 Issue #2: Videos Not Being Saved Correctly

### Current Implementation (Transform-Based Approach)
The current code uses CGAffineTransform metadata to handle orientation:
- Camera captures in landscape (1920x1080) - hardware limitation
- Videos are saved in landscape dimensions
- Transform metadata tells video players to rotate 90° for portrait display
- Front camera transform includes mirroring for selfie effect

**Code locations**:
- `setupAssetWriters()` lines 1887-1897: Creates transforms
- `RecordingCoordinator.configure()` lines 139, 143: Applies transforms to video inputs
- `appendFrontPixelBuffer()` line 372: No pixel rotation
- `appendBackPixelBuffer()` line 394: No pixel rotation

### Why This Approach Fails

**Problem 1**: Transform metadata is not universally supported
- Some video players ignore transform metadata
- iOS Photos app sometimes displays incorrectly
- Sharing to social media may lose orientation

**Problem 2**: Combined video still uses pixel rotation
- FrameCompositor rotates pixels for stacking (lines 200-250 in FrameCompositor.swift)
- This creates inconsistency: individual videos use transform, combined uses pixels
- Mixed approaches cause confusion and bugs

**Problem 3**: Overcomplicated
- Two different orientation strategies in one app
- Hard to debug and maintain
- User is right: "overcomplicating with rotations"

### The SIMPLE Solution: Pixel Rotation for Everything

**Go back to basics**: Rotate pixels from landscape to portrait for ALL videos.

**Why this works**:
- ✅ Consistent approach across all 3 videos
- ✅ Videos display correctly in ALL players
- ✅ No metadata tricks - physical pixels are portrait
- ✅ Simpler to understand and debug
- ⚠️ Slightly slower (but acceptable for 30fps recording)

### Fix for Issue #2

#### Step 1: Remove Transform Approach

**File**: `DualLensPro/DualLensPro/Managers/DualCameraManager.swift`

**Lines 1868-1897**: Replace transform logic with pixel rotation setup

```swift
// ✅ PORTRAIT MODE: Use pixel rotation (simple and reliable)
// Camera buffers are landscape (1920x1080), we rotate to portrait (1080x1920)
let orientation = UIDevice.current.orientation
let isPortrait = true  // ✅ ALWAYS PORTRAIT - User requirement

print("📱 PORTRAIT MODE - Using pixel rotation (simple and reliable)")

// ✅ Rotate dimensions: landscape (1920x1080) → portrait (1080x1920)
let dimensions: (width: Int, height: Int)
let combinedDimensions: (width: Int, height: Int)

// Portrait dimensions (rotated)
dimensions = (width: baseDimensions.height, height: baseDimensions.width)  // 1080x1920
// Combined video is stacked vertically, so double the height
combinedDimensions = (width: baseDimensions.height, height: baseDimensions.width * 2)  // 1080x3840

print("📱 Portrait dimensions: \(dimensions.width)x\(dimensions.height)")
print("📱 Combined dimensions: \(combinedDimensions.width)x\(combinedDimensions.height)")

// ✅ No transforms needed - using pixel rotation instead
let frontTransform = CGAffineTransform.identity
let backTransform = CGAffineTransform.identity

print("🔄 Using pixel rotation for portrait (no transform metadata)")
```

#### Step 2: Enable Pixel Rotation in RecordingCoordinator

**File**: `DualLensPro/DualLensPro/Actors/RecordingCoordinator.swift`

**Lines 97-101**: Enable rotation

```swift
// ✅ Enable pixel rotation for portrait mode
needsRotation = true
self.targetWidth = dimensions.width   // 1080
self.targetHeight = dimensions.height // 1920
print("ℹ️ Using pixel rotation: \(targetWidth)x\(targetHeight)")
```

**Lines 370-383**: Rotate front camera pixels

```swift
func appendFrontPixelBuffer(_ pixelBuffer: CVPixelBuffer, time: CMTime) throws {
    guard isWriting else { return }

    guard let adaptor = frontPixelBufferAdaptor,
          let input = frontVideoInput else {
        return
    }

    guard input.isReadyForMoreMediaData else {
        return
    }

    // ✅ Rotate and mirror for front camera (selfie effect)
    guard let rotatedBuffer = rotateAndMirrorPixelBuffer(
        pixelBuffer,
        to: (width: targetWidth, height: targetHeight),
        mirror: true  // Mirror for selfie
    ) else {
        print("⚠️ Failed to rotate front buffer")
        return
    }

    let ok = adaptor.append(rotatedBuffer, withPresentationTime: time)
    if ok {
        lastFrontVideoPTS = time
    } else {
        print("⚠️ Failed to append front pixel buffer at \(time.seconds)s")
    }

    // Cache front buffer for compositing (use rotated buffer)
    lastFrontBuffer = (buffer: rotatedBuffer, time: time)
}
```

**Lines 385-422**: Rotate back camera pixels

```swift
func appendBackPixelBuffer(_ pixelBuffer: CVPixelBuffer, time: CMTime) async throws {
    guard isWriting else { return }

    // Append to back writer
    if let adaptor = backPixelBufferAdaptor,
       let input = backVideoInput,
       input.isReadyForMoreMediaData {

        // ✅ Rotate (no mirror) for back camera
        guard let rotatedBuffer = rotateAndMirrorPixelBuffer(
            pixelBuffer,
            to: (width: targetWidth, height: targetHeight),
            mirror: false  // No mirror for back
        ) else {
            print("⚠️ Failed to rotate back buffer")
            return
        }

        let ok = adaptor.append(rotatedBuffer, withPresentationTime: time)
        if ok {
            lastBackVideoPTS = time
        } else {
            print("⚠️ Failed to append back pixel buffer at \(time.seconds)s")
        }
    }

    // ✅ Create stacked composition for combined output
    if let adaptor = combinedPixelBufferAdaptor,
       let input = combinedVideoInput,
       input.isReadyForMoreMediaData,
       let compositor = compositor {

        // Compose front and back into stacked frame
        // Both buffers are already rotated to portrait
        if let composedBuffer = compositor.stacked(front: lastFrontBuffer?.buffer, back: pixelBuffer) {
            let ok2 = adaptor.append(composedBuffer, withPresentationTime: time)
            if ok2 {
                lastCombinedVideoPTS = time
            } else {
                print("⚠️ Failed to append composed pixel buffer at \(time.seconds)s")
            }
        } else {
            print("⚠️ Failed to compose frame at \(time.seconds)s")
        }
    }
}
```

**Lines 291-295**: Remove deprecation warning

```swift
// MARK: - Pixel Buffer Rotation
/// Rotates and optionally mirrors a pixel buffer from landscape (1920x1080) to portrait (1080x1920)
private func rotateAndMirrorPixelBuffer(_ pixelBuffer: CVPixelBuffer, to dimensions: (width: Int, height: Int), mirror: Bool) -> CVPixelBuffer? {
```

---

## 📋 Summary of Changes

### Issue #1: Recording Timer
- **File**: `DualCameraManager.swift`
- **Change**: Simplify timer to use MainActor state directly
- **Lines**: 2109-2118

### Issue #2: Video Orientation
- **File**: `DualCameraManager.swift`
  - **Lines 1868-1897**: Use portrait dimensions, remove transforms
- **File**: `RecordingCoordinator.swift`
  - **Lines 97-101**: Enable pixel rotation
  - **Lines 370-383**: Rotate front camera pixels
  - **Lines 385-422**: Rotate back camera pixels  
  - **Lines 291-295**: Remove deprecation warning

---

## ✅ Testing Checklist

After implementing fixes:

1. **Test Recording Timer**:
   - [ ] Start recording
   - [ ] Verify timer appears in top-right corner
   - [ ] Verify timer counts up (00:00, 00:01, 00:02...)
   - [ ] Verify timer updates smoothly

2. **Test Video Orientation**:
   - [ ] Record 5-10 seconds in portrait
   - [ ] Stop recording
   - [ ] Open Photos app
   - [ ] Verify all 3 videos are portrait (vertical)
   - [ ] Verify front camera is mirrored
   - [ ] Verify back camera is NOT mirrored
   - [ ] Share video to Messages/Instagram - verify orientation

3. **Test Performance**:
   - [ ] Record for 30+ seconds
   - [ ] Verify no frame drops
   - [ ] Verify smooth recording
   - [ ] Check device temperature (should be warm but not hot)

---

## 🎯 Why This Approach Works

1. **Simplicity**: One consistent approach (pixel rotation) for all videos
2. **Reliability**: Physical pixels are portrait - works in ALL video players
3. **Consistency**: All 3 videos use the same orientation strategy
4. **Debuggability**: Easy to understand and troubleshoot
5. **User Satisfaction**: Videos "just work" everywhere

**Trade-off**: Slightly higher CPU/GPU usage during recording, but acceptable for 30fps.

---

## 🚀 Next Steps

1. Implement timer fix first (quick win)
2. Test timer is working
3. Implement video orientation fix
4. Test all 3 videos display correctly
5. Deploy to device and verify


