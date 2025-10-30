# Video Orientation System - Technical Documentation

## Overview

This document explains how the DualLensPro app handles video orientation for simultaneous front and back camera recording. The system ensures that all three output videos (front individual, back individual, and merged) are correctly oriented in portrait mode.

---

## The Problem

### Initial Issue
When recording videos in portrait mode, the **back camera individual video was consistently rotated 90° to the right (sideways)**, while the front camera video displayed correctly. After multiple attempts with different rotation combinations, the issue persisted for hours.

### Symptoms
1. ✅ **Front camera individual video**: Correct portrait orientation
2. ❌ **Back camera individual video**: Rotated 90° right (sideways/landscape)
3. ❌ **Merged video**: Back camera portion incorrectly oriented

### Secondary Issue (After Initial Fix)
After implementing physical buffer rotation, a new issue emerged:
1. ✅ **Merged video**: Both cameras correctly oriented
2. ❌ **Individual videos**: Correct orientation but **not stretched to full portrait screen** (squeezed/wrong aspect ratio)

---

## Root Cause Analysis

### Native Camera Orientations

The fundamental issue stems from the **opposite native orientations** of the front and back cameras on iOS devices:

- **Front-facing camera**: Native orientation is `AVCaptureVideoOrientationLandscapeLeft`
- **Back-facing camera**: Native orientation is `AVCaptureVideoOrientationLandscapeRight` (180° opposite!)

This means:
- Front camera delivers buffers in landscape-left orientation naturally
- Back camera delivers buffers in landscape-right orientation naturally
- They are **180° opposite** from each other

### Why Transform Metadata Alone Doesn't Work

The initial approach used `CGAffineTransform` metadata to tell video players how to rotate videos:
```swift
// ❌ INCORRECT APPROACH
frontTransform = CGAffineTransform(rotationAngle: 90°)  // For front camera
backTransform = CGAffineTransform(rotationAngle: 270°)  // For back camera
```

**Why this failed:**
- Transform metadata is just a "hint" to video players
- It doesn't physically rotate the pixel buffers
- Different players interpret transforms differently (QuickTime vs VLC vs Chrome)
- Doesn't account for the opposite native orientations properly

---

## The Solution

### Apple's Recommended Approach

Based on Apple documentation and Stack Overflow research, the correct approach for dual camera apps is:

1. **Set `videoRotationAngle` on the capture connection** to physically rotate buffers BEFORE writing to file
2. **Use identity transform** (no rotation) on `AVAssetWriterInput` since buffers are already rotated
3. **Swap width/height dimensions** for the AVAssetWriter to match the rotated buffers

### Implementation Strategy

```swift
// ✅ CORRECT APPROACH

// Step 1: Set videoRotationAngle on BOTH camera connections
frontVideoOutput.connection.videoRotationAngle = 90°  // Physically rotates buffers
backVideoOutput.connection.videoRotationAngle = 90°   // Physically rotates buffers

// Step 2: Use identity transform (no rotation metadata)
frontTransform = CGAffineTransform.identity  // 0° rotation
backTransform = CGAffineTransform.identity   // 0° rotation

// Step 3: Swap dimensions for portrait orientation
// Native: 1920x1080 (landscape)
// After rotation: buffers are 1080x1920 (portrait)
// AVAssetWriter must be configured with: 1080x1920
frontDimensions = (width: height, height: width)  // Swapped!
backDimensions = (width: height, height: width)   // Swapped!
```

---

## Technical Implementation

### 1. Video Output Connection Rotation (Lines 1825-1849)

```swift
let angle = self.videoRotationAngle()  // 90° for portrait

// Update front video output connection
if let frontOutput = self.frontVideoOutput,
   let connection = frontOutput.connection(with: .video) {
    if connection.isVideoRotationAngleSupported(angle) {
        connection.videoRotationAngle = angle  // Physically rotate to portrait
    }
    print("✅ Front video connection set to \(angle)° (physically rotates buffers)")
}

// Update back video output connection
if let backOutput = self.backVideoOutput,
   let connection = backOutput.connection(with: .video) {
    if connection.isVideoRotationAngleSupported(angle) {
        connection.videoRotationAngle = angle  // Physically rotate to portrait
    }
    print("✅ Back video connection set to \(angle)° (physically rotates buffers)")
}
```

**What this does:**
- Sets `videoRotationAngle = 90°` on BOTH camera connections
- Physically rotates pixel buffers from landscape to portrait BEFORE writing
- Handles the opposite native orientations automatically
- Works for both front (LandscapeLeft) and back (LandscapeRight) cameras

### 2. Transform Metadata (Lines 1922-1936)

```swift
// Buffers are now physically rotated by videoRotationAngle on connections
// No transform metadata needed - use identity transform
let frontTransformRotation = 0  // Identity transform
let backTransformRotation = 0   // Identity transform

let frontTransform = assetWriterTransform(for: frontTransformRotation, mirror: true)
let backTransform = assetWriterTransform(for: backTransformRotation, mirror: false)
```

**What this does:**
- Sets transform rotation to 0° (identity transform)
- No rotation metadata applied to video files
- Videos play correctly in all players (QuickTime, VLC, Chrome, etc.)

### 3. Dimension Swapping (Lines 1949-1960)

```swift
let frontDimensions = activeDimensions(for: frontCameraInput)  // e.g., 1920x1080
let backDimensions = activeDimensions(for: backCameraInput)    // e.g., 1920x1080

// ✅ CRITICAL: Swap width/height for portrait orientation
// When videoRotationAngle = 90°, buffers are rotated from 1920x1080 to 1080x1920
// AVAssetWriter must be configured with swapped dimensions to match!
let frontDimensionsRotated = isPortraitOrientation ? 
    (width: frontDimensions.height, height: frontDimensions.width) : frontDimensions
let backDimensionsRotated = isPortraitOrientation ? 
    (width: backDimensions.height, height: backDimensions.width) : backDimensions

// Pass swapped dimensions to RecordingCoordinator
try await coordinator.configure(
    frontDimensions: frontDimensionsRotated,  // 1080x1920 for portrait
    backDimensions: backDimensionsRotated,    // 1080x1920 for portrait
    ...
)
```

**What this does:**
- Gets native sensor dimensions (1920x1080 landscape)
- Swaps width/height for portrait orientation (1080x1920)
- Configures AVAssetWriter with correct portrait dimensions
- Ensures videos fill the full portrait screen properly

---

## How It Works: Step-by-Step

### Recording Flow

1. **Camera Setup**
   - Front camera: Native orientation `LandscapeLeft` (1920x1080)
   - Back camera: Native orientation `LandscapeRight` (1920x1080)

2. **Connection Configuration**
   - Set `videoRotationAngle = 90°` on both connections
   - This tells AVFoundation to physically rotate buffers before output

3. **Buffer Capture**
   - Front camera: Buffers rotated from LandscapeLeft → Portrait (1080x1920)
   - Back camera: Buffers rotated from LandscapeRight → Portrait (1080x1920)
   - Both cameras now deliver portrait-oriented buffers!

4. **AVAssetWriter Configuration**
   - Front writer: Configured with 1080x1920 dimensions (swapped)
   - Back writer: Configured with 1080x1920 dimensions (swapped)
   - Combined writer: Configured with 1080x2160 dimensions (stacked)

5. **Video Writing**
   - Buffers are already in portrait orientation (1080x1920)
   - AVAssetWriter dimensions match buffer dimensions (1080x1920)
   - No transform metadata needed (identity transform)
   - Videos written correctly to files

6. **Playback**
   - Videos play correctly in all players
   - Full portrait screen coverage
   - No rotation or aspect ratio issues

---

## Key Benefits

### ✅ Correct Orientation
- All three videos (front, back, merged) display in correct portrait orientation
- No sideways or upside-down videos

### ✅ Full Screen Coverage
- Individual videos fill the full portrait screen
- No squeezing or wrong aspect ratios
- Proper 9:16 portrait aspect ratio

### ✅ Universal Compatibility
- Works correctly in all video players (QuickTime, VLC, Chrome, Photos app)
- No player-specific quirks or issues

### ✅ Handles Both Cameras
- Automatically handles opposite native orientations
- Same rotation angle (90°) works for both cameras
- No special cases needed

---

## Code Locations

### DualCameraManager.swift

- **Lines 1825-1849**: Video output connection rotation setup
- **Lines 1885-1997**: `setupAssetWriters()` function
- **Lines 1922-1936**: Transform metadata calculation
- **Lines 1949-1960**: Dimension swapping logic
- **Lines 1806-1870**: `deviceOrientationDidChange()` - handles orientation changes

### RecordingCoordinator.swift

- Receives rotated dimensions from DualCameraManager
- Configures AVAssetWriter instances with correct dimensions
- Handles buffer writing for all three video files

---

## Testing & Verification

### Test Checklist

1. ✅ **Front camera individual video**: Correct portrait orientation, full screen
2. ✅ **Back camera individual video**: Correct portrait orientation, full screen
3. ✅ **Merged video**: Both cameras correctly oriented in portrait, stacked vertically
4. ✅ **Playback in Photos app**: All videos display correctly
5. ✅ **Playback in QuickTime**: All videos display correctly
6. ✅ **Playback in VLC**: All videos display correctly

### Expected Results

- **Individual videos**: 1080x1920 portrait orientation, full screen coverage
- **Merged video**: 1080x2160 portrait orientation, both cameras stacked vertically
- **No rotation issues**: Videos play correctly without manual rotation
- **No aspect ratio issues**: Videos fill the screen properly

---

## Conclusion

The video orientation system now correctly handles the opposite native orientations of front and back cameras by:

1. **Physically rotating buffers** at capture time using `videoRotationAngle`
2. **Using identity transform** (no rotation metadata)
3. **Swapping dimensions** to match rotated buffers

This approach follows Apple's best practices and ensures universal compatibility across all video players.

**Result**: All three videos (front individual, back individual, and merged) display correctly in portrait orientation with full screen coverage! 🎉

