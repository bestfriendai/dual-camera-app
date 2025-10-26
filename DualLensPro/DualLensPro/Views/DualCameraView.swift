
//
//  DualCameraView.swift
//  DualLensPro
//
//  Created by DualLens Pro Team on 10/24/25.
//

import SwiftUI

// MARK: - Top Toolbar Component
private struct TopToolbar: View {
    @EnvironmentObject var viewModel: CameraViewModel
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        HStack(spacing: 0) {
            // Flash Button
            Button(action: {
                HapticManager.shared.light()
                // Toggle flash (implement flash toggle in view model)
            }) {
                Image(systemName: "bolt.slash.fill")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
            }

            Divider()
                .background(.white.opacity(0.3))
                .frame(height: 20)

            // Timer Button
            Button(action: {
                HapticManager.shared.light()
                // Cycle through timer options (0, 3, 10 seconds)
                let timerOptions = [0, 3, 10]
                if let currentIndex = timerOptions.firstIndex(of: viewModel.timerDuration) {
                    let nextIndex = (currentIndex + 1) % timerOptions.count
                    viewModel.setTimer(timerOptions[nextIndex])
                }
            }) {
                ZStack {
                    if viewModel.timerDuration > 0 {
                        Image(systemName: "timer")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(.yellow)
                    } else {
                        Image(systemName: "timer")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 40, height: 40)
            }

            Divider()
                .background(.white.opacity(0.3))
                .frame(height: 20)

            // Grid/More Button
            Button(action: {
                HapticManager.shared.light()
                viewModel.toggleGrid()
            }) {
                Image(systemName: viewModel.showGrid ? "circle.grid.3x3.fill" : "circle.grid.3x3")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(viewModel.showGrid ? .yellow : .white)
                    .frame(width: 40, height: 40)
            }
        }
        .background {
            if !reduceTransparency {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Capsule()
                            .fill(.black.opacity(0.2))
                    }
            } else {
                Capsule()
                    .fill(.black.opacity(0.6))
            }
        }
        .frame(height: 40)
        .shadow(color: .black.opacity(0.2), radius: 8, y: 2)
    }
}

struct DualCameraView: View {
    @EnvironmentObject var viewModel: CameraViewModel
    @State private var frontCameraFrame: CGRect = .zero
    @State private var backCameraFrame: CGRect = .zero
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()

                // Show loading indicator while camera is initializing
                if !viewModel.isCameraReady {
                    VStack(spacing: 20) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.5)

                        Text("Initializing Camera...")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                } else if viewModel.cameraManager.isMultiCamSupported {
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
                            CameraLabel(text: "Back", zoom: viewModel.configuration.backZoomFactor)
                                .padding(.top, 8)
                                .padding(.leading, 12)
                        }
                        .overlay(alignment: .topTrailing) {
                            if viewModel.isRecording {
                                RecordingIndicator(duration: viewModel.recordingDuration)
                                    .padding(.top, 8)
                                    .padding(.trailing, 12)
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
                            CameraLabel(text: "Front", zoom: viewModel.configuration.frontZoomFactor)
                                .padding(.bottom, 8)
                                .padding(.leading, 12)
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
                                .padding(.top, 8)
                                .padding(.trailing, 12)
                        }
                    }
                }

                // Only show UI controls when camera is ready
                if viewModel.isCameraReady {
                    // Top Overlay - Toolbar and Timer
                    VStack(spacing: 12) {
                        HStack {
                            Spacer()

                            // Top Toolbar (right side)
                            TopToolbar()
                                .padding(.top, 8)
                                .padding(.trailing, 12)
                        }

                        // Timer Display - only show when recording
                        if viewModel.isRecording {
                            TimerDisplay(duration: viewModel.recordingDuration)
                        }

                        Spacer()
                    }

                    // Zoom Control - Above bottom controls
                    VStack {
                        Spacer()

                        ZoomControl(
                            currentZoom: viewModel.configuration.backZoomFactor,
                            availableZooms: [0.5, 1.0, 2.0],
                            onZoomChange: { factor in
                                viewModel.updateBackZoom(factor)
                            }
                        )
                        .padding(.bottom, 12)
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
