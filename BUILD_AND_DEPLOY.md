# DualLensPro - Build and Deploy Instructions

This document contains the commands needed to build and deploy the DualLensPro app to a physical iPhone device in Release mode.

## Prerequisites

- Xcode installed on your Mac
- iPhone connected via USB or Wi-Fi
- Valid Apple Developer certificate and provisioning profile
- Device unlocked during installation and launch

## Device Information

- **Device Name**: Patrick's iPhone 17 Pro Max
- **Device ID**: `00008150-00023C861438401C`
- **Bundle Identifier**: `com.duallens.pro`

## Build and Deploy Commands

### 1. Navigate to Project Directory

```bash
cd "/Users/iamabillionaire/Downloads/Dual_Camera_App_Concept (3)/DualLensPro"
```

### 2. Build the App (Release Mode)

```bash
xcodebuild -scheme "DualLensPro" \
  -configuration Release \
  -destination 'id=00008150-00023C861438401C' \
  -allowProvisioningUpdates \
  clean build
```

**What this does:**
- Cleans previous build artifacts
- Builds the app in Release configuration (optimized)
- Targets the specific device by ID
- Automatically updates provisioning profiles if needed

### 3. Install the App on Device

```bash
xcrun devicectl device install app \
  --device 00008150-00023C861438401C \
  /Users/iamabillionaire/Library/Developer/Xcode/DerivedData/DualLensPro-agrfeonyhqayvrdbodkxodimyiqn/Build/Products/Release-iphoneos/DualLensPro.app
```

**What this does:**
- Installs the built app to the physical device
- Uses the device ID to target the correct iPhone

### 4. Launch the App on Device

```bash
xcrun devicectl device process launch \
  --device 00008150-00023C861438401C \
  com.duallens.pro
```

**What this does:**
- Launches the app on the device using its bundle identifier
- **Note**: Device must be unlocked for this to succeed

## Complete Workflow (All-in-One)

You can run all three commands sequentially:

```bash
cd "/Users/iamabillionaire/Downloads/Dual_Camera_App_Concept (3)/DualLensPro" && \
xcodebuild -scheme "DualLensPro" -configuration Release -destination 'id=00008150-00023C861438401C' -allowProvisioningUpdates clean build && \
xcrun devicectl device install app --device 00008150-00023C861438401C /Users/iamabillionaire/Library/Developer/Xcode/DerivedData/DualLensPro-agrfeonyhqayvrdbodkxodimyiqn/Build/Products/Release-iphoneos/DualLensPro.app && \
xcrun devicectl device process launch --device 00008150-00023C861438401C com.duallens.pro
```

## Troubleshooting

### Device Locked Error

If you see an error like:
```
ERROR: Unable to launch com.duallens.pro because the device was not, or could not be, unlocked.
```

**Solution**: Unlock your iPhone and either:
- Tap the DualLensPro app icon on your home screen to launch it manually, or
- Run the launch command again:
  ```bash
  xcrun devicectl device process launch --device 00008150-00023C861438401C com.duallens.pro
  ```

### Device Not Found

If the device is not found, list available devices:

```bash
instruments -s devices
```

Or use:

```bash
xcrun devicectl list devices
```

### Build Path Changed

If the DerivedData path changes, you can find the current build output location by checking the build log or using:

```bash
xcodebuild -scheme "DualLensPro" -configuration Release -showBuildSettings | grep BUILT_PRODUCTS_DIR
```

## Quick Reference

| Command | Purpose |
|---------|---------|
| `xcodebuild clean build` | Build the app |
| `xcrun devicectl device install app` | Install app to device |
| `xcrun devicectl device process launch` | Launch app on device |
| `instruments -s devices` | List available devices |

## Notes

- **Release Mode**: Builds with optimizations enabled (`-O -whole-module-optimization`)
- **Code Signing**: Automatically handled with "Apple Development: Patrick Francis (2849LY324P)"
- **Provisioning Profile**: "iOS Team Provisioning Profile: *"
- **Build Time**: Typically 1-2 minutes for a clean build
- **Device Connection**: Works over USB or Wi-Fi (if configured)

## Alternative: Using Xcode GUI

If you prefer using Xcode:

1. Open `DualLensPro.xcodeproj` in Xcode
2. Select "Patrick's iPhone 17 Pro Max" from the device selector
3. Go to **Product → Scheme → Edit Scheme**
4. Select "Run" on the left
5. Change "Build Configuration" to "Release"
6. Press **Cmd+R** or click the Play button

---

**Last Updated**: 2025-10-30

