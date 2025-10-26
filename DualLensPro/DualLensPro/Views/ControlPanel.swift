
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

    var body: some View {
        VStack(spacing: 20) {
            // Mode Selector - matching screenshot
            ModeSelector(selectedMode: $viewModel.currentCaptureMode)
                .padding(.bottom, 4)

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
                    if viewModel.currentCaptureMode == .photo || viewModel.currentCaptureMode == .groupPhoto {
                        viewModel.capturePhoto()
                    } else {
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
        .padding(.horizontal, 16)
        .padding(.bottom, 32)
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
