import AVFoundation

print("iPhone Multi-Cam Support Check")
print("Multi-Cam Supported: \(AVCaptureMultiCamSession.isMultiCamSupported)")

if AVCaptureMultiCamSession.isMultiCamSupported {
    print("✅ This device supports simultaneous dual camera recording")
} else {
    print("❌ This device does NOT support multi-cam")
    print("Multi-cam requires iPhone XS or later")
}
