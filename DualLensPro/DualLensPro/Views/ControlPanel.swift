
//
//  ControlPanel.swift
//  DualLensPro
//
//  Created by DualLens Pro Team on 10/24/25.
//

import SwiftUI

struct ControlPanel: View {
    @EnvironmentObject var viewModel: CameraViewModel
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    // Get safe area bottom for proper padding
    private var safeAreaBottom: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?
            .safeAreaInsets.bottom ?? 0
    }

    var body: some View {
        VStack(spacing: 28) {
            // Mode Selector - matching screenshot
            ModeSelector(selectedMode: $viewModel.currentCaptureMode)

            // Bottom Control Bar - matching Apple Camera layout
            HStack(spacing: 0) {
                // Gallery Thumbnail (left)
                GalleryThumbnail {
                    viewModel.openGallery()
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer()

                // Record Button (Center - Large)
                RecordButton(isRecording: viewModel.isRecording) {
                    print("🔘 Record button tapped - mode: \(viewModel.currentCaptureMode)")
                    print("🔘 isPhotoMode: \(viewModel.currentCaptureMode.isPhotoMode)")
                    print("🔘 isRecordingMode: \(viewModel.currentCaptureMode.isRecordingMode)")
                    print("🔘 isCameraReady: \(viewModel.isCameraReady)")

                    // Safety check - camera must be ready
                    guard viewModel.isCameraReady else {
                        print("❌ Camera not ready - ignoring button tap")
                        return
                    }

                    // Use the mode's properties instead of hardcoded checks
                    if viewModel.currentCaptureMode.isPhotoMode {
                        print("📸 Calling capturePhoto()")
                        viewModel.capturePhoto()
                    } else if viewModel.currentCaptureMode.isRecordingMode {
                        print("🎥 Calling toggleRecording()")
                        viewModel.toggleRecording()
                    } else {
                        print("⚠️ Unknown mode - defaulting to toggleRecording()")
                        viewModel.toggleRecording()
                    }
                }

                Spacer()

                // Camera Flip Button (right)
                Button(action: {
                    HapticManager.shared.medium()
                    viewModel.switchCameras()
                }) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 24, weight: .regular))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, max(safeAreaBottom, 24) + 32)
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        
        VStack {
            Spacer()
            ControlPanel()
        }
    }
    .environmentObject(CameraViewModel())
}
