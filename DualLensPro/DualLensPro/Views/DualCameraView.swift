
//
//  DualCameraView.swift
//  DualLensPro
//
//  Created by DualLens Pro Team on 10/24/25.
//

import SwiftUI

struct DualCameraView: View {
    @EnvironmentObject var viewModel: CameraViewModel
    @State private var frontCameraFrame: CGRect = .zero
    @State private var backCameraFrame: CGRect = .zero
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()

                if viewModel.cameraManager.isMultiCamSupported {
                    // Dual camera mode
                    VStack(spacing: 0) {
                        // Back Camera (Top)
                        ZStack {
                            CameraPreviewView(
                                previewLayer: viewModel.cameraManager.backPreviewLayer,
                                position: .back,
                                onZoomChange: { factor in
                                    viewModel.updateBackZoom(factor)
                                },
                                currentZoom: viewModel.configuration.backZoomFactor
                            )

                            // Grid overlay for back camera
                            if viewModel.showGrid {
                                GridOverlay()
                            }
                        }
                        .frame(height: geometry.size.height * 0.5)
                        .overlay(alignment: .topLeading) {
                            CameraLabel(text: "Back Camera", zoom: viewModel.configuration.backZoomFactor)
                                .padding()
                        }
                        .overlay(alignment: .topTrailing) {
                            if viewModel.isRecording {
                                RecordingIndicator(duration: viewModel.recordingDuration)
                                    .padding()
                            }
                        }

                        // Divider
                        Rectangle()
                            .fill(.white.opacity(0.3))
                            .frame(height: 2)

                        // Front Camera (Bottom)
                        ZStack {
                            CameraPreviewView(
                                previewLayer: viewModel.cameraManager.frontPreviewLayer,
                                position: .front,
                                onZoomChange: { factor in
                                    viewModel.updateFrontZoom(factor)
                                },
                                currentZoom: viewModel.configuration.frontZoomFactor
                            )

                            // Grid overlay for front camera
                            if viewModel.showGrid {
                                GridOverlay()
                            }
                        }
                        .frame(height: geometry.size.height * 0.5)
                        .overlay(alignment: .bottomLeading) {
                            CameraLabel(text: "Front Camera", zoom: viewModel.configuration.frontZoomFactor)
                                .padding()
                        }
                    }
                } else {
                    // Single camera mode (fallback for devices without multi-cam support)
                    ZStack {
                        CameraPreviewView(
                            previewLayer: viewModel.cameraManager.backPreviewLayer,
                            position: .back,
                            onZoomChange: { factor in
                                viewModel.updateBackZoom(factor)
                            },
                            currentZoom: viewModel.configuration.backZoomFactor
                        )

                        // Grid overlay
                        if viewModel.showGrid {
                            GridOverlay()
                        }

                        // Single-cam mode notice
                        VStack {
                            HStack {
                                Text("Single Camera Mode")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.7))
                                    .padding(8)
                                    .background(.black.opacity(0.5))
                                    .cornerRadius(8)
                                    .padding()
                                Spacer()
                            }
                            Spacer()
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        if viewModel.isRecording {
                            RecordingIndicator(duration: viewModel.recordingDuration)
                                .padding()
                        }
                    }
                }
                
                // Top Overlay - Timer and Premium Banner
                VStack(spacing: 16) {
                    // Timer Display at very top
                    TimerDisplay(duration: viewModel.recordingDuration)
                        .padding(.top, 12)

                    // Premium Upgrade Banner
                    if !viewModel.isRecording && !viewModel.isPremium {
                        PremiumUpgradeButton(maxDuration: "3 Minutes") {
                            viewModel.showPremiumUpgrade = true
                        }
                        .padding(.top, 4)
                    }

                    Spacer()
                }

                // Right Side - Zoom Control
                VStack {
                    Spacer()

                    HStack {
                        Spacer()

                        ZoomControl(
                            currentZoom: viewModel.configuration.backZoomFactor,
                            availableZooms: [0.5, 1.0, 2.0, 3.0],
                            onZoomChange: { factor in
                                viewModel.updateBackZoom(factor)
                            }
                        )
                        .padding(.trailing, 24)
                        .padding(.bottom, 220)
                    }
                }

                // Controls Overlay
                VStack {
                    Spacer()

                    if viewModel.controlsVisible {
                        ControlPanel()
                            .environmentObject(viewModel)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }

                // Timer Countdown Overlay
                if viewModel.showTimerCountdown {
                    TimerCountdownView(
                        duration: viewModel.timerCountdownDuration,
                        onComplete: {
                            viewModel.showTimerCountdown = false
                            viewModel.executePhotoCapture()
                        },
                        onCancel: {
                            viewModel.cancelTimerCountdown()
                        }
                    )
                    .transition(.opacity)
                    .zIndex(100)
                }
            }
            .onTapGesture {
                viewModel.toggleControlsVisibility()
            }
            .sheet(isPresented: $viewModel.showSettings) {
                SettingsView(viewModel: viewModel)
            }
            .sheet(isPresented: $viewModel.showPremiumUpgrade) {
                PremiumUpgradeView()
                    .environmentObject(viewModel)
            }
        }
        .ignoresSafeArea()
    }
}

#Preview {
    DualCameraView()
        .environmentObject(CameraViewModel())
}
