
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

            // Bottom Control Bar - matching screenshot layout
            HStack(spacing: 12) {
                // Gallery Thumbnail (left)
                GalleryThumbnail {
                    viewModel.openGallery()
                }

                // Settings Button
                Button(action: {
                    HapticManager.shared.light()
                    viewModel.showSettings = true
                }) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(.ultraThinMaterial)

                                LinearGradient(
                                    colors: [
                                        .white.opacity(0.2),
                                        .white.opacity(0.05)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 12))

                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(
                                        LinearGradient(
                                            colors: [
                                                .white.opacity(0.4),
                                                .white.opacity(0.2)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1.5
                                    )
                            }
                            .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                        }
                }

                Spacer()

                // Record Button (Center - Large, Red)
                RecordButton(isRecording: viewModel.isRecording) {
                    if viewModel.currentCaptureMode == .photo || viewModel.currentCaptureMode == .groupPhoto {
                        viewModel.capturePhoto()
                    } else {
                        viewModel.toggleRecording()
                    }
                }

                Spacer()

                // Aspect Ratio Button
                AspectRatioButton(currentRatio: Binding(
                    get: { viewModel.aspectRatio },
                    set: { viewModel.setAspectRatio($0) }
                ))

                // Camera Flip Button (right)
                Button(action: {
                    HapticManager.shared.medium()
                    viewModel.switchCameras()
                }) {
                    Image(systemName: "arrow.triangle.2.circlepath.camera.fill")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(.ultraThinMaterial)

                                LinearGradient(
                                    colors: [
                                        .white.opacity(0.2),
                                        .white.opacity(0.05)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 12))

                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(
                                        LinearGradient(
                                            colors: [
                                                .white.opacity(0.4),
                                                .white.opacity(0.2)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1.5
                                    )
                            }
                            .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                        }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
            .background {
                if !reduceTransparency {
                    ZStack {
                        RoundedRectangle(cornerRadius: 24)
                            .fill(.ultraThinMaterial)

                        LinearGradient(
                            colors: [
                                .black.opacity(0.3),
                                .black.opacity(0.1),
                                .black.opacity(0.2)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 24))

                        RoundedRectangle(cornerRadius: 24)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        .white.opacity(0.3),
                                        .white.opacity(0.1)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 1
                            )
                    }
                    .shadow(color: .black.opacity(0.4), radius: 20, y: 10)
                } else {
                    RoundedRectangle(cornerRadius: 24)
                        .fill(.regularMaterial)
                        .opacity(0.9)
                }
            }
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
