# Quick Fix Reference Card

## 🎯 TL;DR - What's Wrong

**Problem:** Camera videos are sideways and stretched because:
1. Camera hardware outputs landscape buffers (1920x1080)
2. FrameCompositor doesn't rotate them before compositing
3. Front camera isn't mirrored in the compositor
4. Result: Sideways, distorted videos

**Solution:** Apply CIImage orientation transforms in FrameCompositor before scaling/positioning.

---

## 📝 Code Changes Required

### File 1: `FrameCompositor.swift`

#### Change 1.1: Add orientation property to init
```swift
// FIND (line 32):
init(width: Int, height: Int) {

// REPLACE WITH:
private let deviceOrientation: UIDeviceOrientation
private let isPortrait: Bool

init(width: Int, height: Int, deviceOrientation: UIDeviceOrientation) {
    self.deviceOrientation = deviceOrientation
    self.isPortrait = (deviceOrientation == .portrait || 
                      deviceOrientation == .portraitUpsideDown ||
                      deviceOrientation == .unknown || 
                      deviceOrientation == .faceUp || 
                      deviceOrientation == .faceDown)
```

#### Change 1.2: Add orientImage() method
```swift
// ADD AFTER line 346 (before closing brace):
private func orientImage(_ image: CIImage, isFrontCamera: Bool) -> CIImage {
    var oriented = image
    
    // Rotate for portrait mode
    if isPortrait {
        oriented = oriented.oriented(.right)
    }
    
    // Mirror front camera
    if isFrontCamera {
        let transform = CGAffineTransform(scaleX: -1, y: 1)
            .translatedBy(x: -oriented.extent.width, y: 0)
        oriented = oriented.transformed(by: transform)
    }
    
    return oriented
}
```

#### Change 1.3: Use oriented images in stackedBuffers
```swift
// FIND (lines 186-197):
let frontImage = CIImage(cvPixelBuffer: front)
let backImage = CIImage(cvPixelBuffer: back)

// Calculate dimensions for stacking
let outputWidth = CGFloat(width)
let outputHeight = CGFloat(height)
let halfHeight = outputHeight / 2

// Scale images to fit half-height
let frontScaled = scaleToFit(image: frontImage, width: outputWidth, height: halfHeight)
let backScaled = scaleToFit(image: backImage, width: outputWidth, height: halfHeight)

// REPLACE WITH:
let frontImage = CIImage(cvPixelBuffer: front)
let backImage = CIImage(cvPixelBuffer: back)

// ✅ Orient images correctly
let frontOriented = orientImage(frontImage, isFrontCamera: true)
let backOriented = orientImage(backImage, isFrontCamera: false)

// Calculate dimensions for stacking
let outputWidth = CGFloat(width)
let outputHeight = CGFloat(height)
let halfHeight = outputHeight / 2

// Scale oriented images to fit half-height
let frontScaled = scaleToFit(image: frontOriented, width: outputWidth, height: halfHeight)
let backScaled = scaleToFit(image: backOriented, width: outputWidth, height: halfHeight)
```

---

### File 2: `RecordingCoordinator.swift`

#### Change 2.1: Add deviceOrientation parameter
```swift
// FIND (line 75):
func configure(
    frontURL: URL,
    backURL: URL,
    combinedURL: URL,
    dimensions: (width: Int, height: Int),
    combinedDimensions: (width: Int, height: Int),
    bitRate: Int,
    frameRate: Int,
    videoTransform: CGAffineTransform
) throws {

// REPLACE WITH:
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
```

#### Change 2.2: Pass orientation to compositor
```swift
// FIND (line 230):
compositor = FrameCompositor(width: combinedDimensions.width, height: combinedDimensions.height)

// REPLACE WITH:
compositor = FrameCompositor(
    width: combinedDimensions.width, 
    height: combinedDimensions.height,
    deviceOrientation: deviceOrientation  // ✅ ADD THIS
)
```

---

### File 3: `DualCameraManager.swift`

#### Change 3.1: Fix photo composition orientation

```swift
// FIND (around line 1223):
private func saveCombinedPhoto(frontData: Data, backData: Data) async throws {
    guard let frontImage = CIImage(data: frontData),
          let backImage = CIImage(data: backData) else {
        throw CameraError.photoOutputNotConfigured
    }

    // Calculate dimensions for stacking
    let frontExtent = frontImage.extent
    let backExtent = backImage.extent

// REPLACE WITH:
private func saveCombinedPhoto(frontData: Data, backData: Data) async throws {
    guard let frontImage = CIImage(data: frontData),
          let backImage = CIImage(data: backData) else {
        throw CameraError.photoOutputNotConfigured
    }

    // ✅ ADD: Apply orientation transforms
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
```

#### Change 3.2: Initialize zoom ranges during setup

```swift
// FIND (around line 530):
private func setupCamera(position: AVCaptureDevice.Position) async throws {
    guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else {
        throw CameraError.deviceNotFound(position)
    }

    // Configure camera device for optimal recording
    try camera.lockForConfiguration()

// ADD AFTER guard statement:
    // ✅ ADD: Update zoom ranges
    await MainActor.run {
        if position == .front {
            configuration.updateZoomRanges(frontCamera: camera, backCamera: nil)
        } else {
            configuration.updateZoomRanges(frontCamera: nil, backCamera: camera)
        }
    }

    // Configure camera device for optimal recording
    try camera.lockForConfiguration()
```

#### Change 3.3: Pass orientation to coordinator
```swift
// FIND (around line 1857):
try await coordinator.configure(
    frontURL: frontURL,
    backURL: backURL,
    combinedURL: combinedURL,
    dimensions: dimensions,
    combinedDimensions: combinedDimensions,
    bitRate: bitRate,
    frameRate: frameRate,
    videoTransform: transform
)

// REPLACE WITH:
try await coordinator.configure(
    frontURL: frontURL,
    backURL: backURL,
    combinedURL: combinedURL,
    dimensions: dimensions,
    combinedDimensions: combinedDimensions,
    bitRate: bitRate,
    frameRate: frameRate,
    videoTransform: transform,
    deviceOrientation: orientation  // ✅ ADD THIS (already captured on line 1825)
)
```

---

## 🧪 Testing Commands

### Build and Deploy
```bash
cd DualLensPro
xcodebuild -project DualLensPro.xcodeproj \
  -scheme DualLensPro \
  -configuration Release \
  -destination 'platform=iOS,id=00008150-00023C861438401C' \
  clean build

xcrun devicectl device install app \
  --device 00008150-00023C861438401C \
  /Users/iamabillionaire/Library/Developer/Xcode/DerivedData/DualLensPro-*/Build/Products/Release-iphoneos/DualLensPro.app

xcrun devicectl device process launch \
  --device 00008150-00023C861438401C \
  com.duallens.pro
```

### Test Checklist

#### Video Tests
```
□ Record in portrait mode
□ Check front camera is upright + mirrored
□ Check back camera is upright
□ Check merged view has both upright
□ Save video and check in Photos app
□ Verify no stretching/distortion
□ Test landscape mode
□ Test all three output files (front.mov, back.mov, combined.mov)
```

#### Photo Tests
```
□ Take photo in portrait mode
□ Verify 3 photos saved to Photos library:
  □ Front camera photo (upright + mirrored)
  □ Back camera photo (upright)
  □ Combined photo (both stacked, both upright)
□ Check no stretching/distortion in photos
□ Test landscape mode photos
□ Verify combined photo matches preview layout
```

#### Zoom Tests
```
□ Test pinch zoom on front camera preview
□ Test pinch zoom on back camera preview
□ Verify zoom applies smoothly
□ Check zoom stays within device limits
□ Test zoom during recording
□ Test zoom during photo capture
```

---

## 🐛 Camera Buttons Disappearing

### Quick Diagnosis
```swift
// Check in DualCameraView.swift or ControlPanel.swift:

// Look for:
.opacity(controlsVisible ? 1 : 0)  // Should always be 1 during recording
.hidden(!controlsVisible)          // Should never hide during recording
.animation(.easeInOut)             // Might conflict with recording animations

// Fix: Ensure buttons have explicit z-index
.zIndex(100)  // Add to button container
```

### Common Causes
1. **State management bug** - `controlsVisible` being set to false
2. **Animation conflict** - Recording animation hiding buttons
3. **View hierarchy issue** - Buttons behind other views
4. **Gesture recognizer** - Blocking touch events

### Quick Fix
```swift
// In ControlPanel.swift or wherever buttons are defined:
VStack {
    // Your buttons
}
.zIndex(999)  // Force buttons to top
.allowsHitTesting(true)  // Ensure touch events work
```

---

## 📊 Expected Console Output (After Fix)

```
✅ FrameCompositor initialized: 1080x1920, orientation: 1, isPortrait: true
🔄 Rotated image 90° for portrait mode
🪞 Mirrored front camera image
🔄 Rotated image 90° for portrait mode
✅ FrameCompositor: Composed frame successfully
```

---

## ⚠️ Common Mistakes to Avoid

1. **Don't rotate pixel buffers physically** - Use CIImage.oriented()
2. **Don't forget to mirror front camera** - Users expect selfie mirror
3. **Don't test only in simulator** - Camera behavior differs on device
4. **Don't skip testing saved videos** - Preview might look OK but saved video wrong
5. **Don't forget to pass orientation** - Compositor needs to know device orientation

---

## 🎯 Success Criteria

### Videos
✅ Front camera video: Upright, mirrored, correct aspect ratio
✅ Back camera video: Upright, correct aspect ratio
✅ Merged video: Both cameras stacked vertically, both upright
✅ All 3 videos play correctly in Photos app
✅ No black bars or letterboxing
✅ No stretching or distortion

### Photos
✅ 3 photos saved: front, back, combined
✅ Front camera photo: Upright, mirrored, correct aspect ratio
✅ Back camera photo: Upright, correct aspect ratio
✅ Combined photo: Both stacked vertically, both upright
✅ Photos match preview layout

### UI/UX
✅ Pinch zoom works on both cameras
✅ Zoom is smooth and responsive
✅ Camera buttons always visible
✅ No gesture conflicts

---

## 📞 If Issues Persist

1. **Check console logs** - Look for orientation values
2. **Verify dimensions** - Print width/height at each step
3. **Test individual cameras** - Front and back separately
4. **Check CIImage extent** - Verify image dimensions after transforms
5. **Use Xcode debugger** - Set breakpoints in orientImage()

---

## 🔗 Related Files

- `FrameCompositor.swift` - Main compositor logic
- `RecordingCoordinator.swift` - Recording coordination
- `DualCameraManager.swift` - Camera management
- `ControlPanel.swift` - UI controls (for button issue)
- `CameraPreviewView.swift` - Preview rendering

---

## 💡 Pro Tips

1. **Use .oriented() not physical rotation** - 100x faster
2. **Test on real device** - Simulator doesn't have real cameras
3. **Check all 3 output files** - Front, back, AND combined
4. **Verify in Photos app** - Final test of saved videos
5. **Print orientation values** - Debug with console logs


