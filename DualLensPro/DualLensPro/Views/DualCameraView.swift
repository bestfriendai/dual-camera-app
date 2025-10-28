
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
                viewModel.toggleFlash()
            }) {
                let iconName: String = {
                    switch viewModel.flashMode {
                    case .off: return "bolt.slash.fill"
                    case .on: return "bolt.fill"
                    case .auto: return "bolt.badge.automatic.fill"
                    @unknown default: return "bolt.slash.fill"
                    }
                }()

                Image(systemName: iconName)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(viewModel.flashMode == .off ? .white : .yellow)
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

            // Grid Button
            Button(action: {
                HapticManager.shared.light()
                viewModel.toggleGrid()
            }) {
                Image(systemName: viewModel.showGrid ? "circle.grid.3x3.fill" : "circle.grid.3x3")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(viewModel.showGrid ? .yellow : .white)
                    .frame(width: 40, height: 40)
            }

            Divider()
                .background(.white.opacity(0.3))
                .frame(height: 20)

            // Settings Button
            Button(action: {
                HapticManager.shared.light()
                viewModel.showSettings = true
            }) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.white)
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
                    // ✅ FIX: Dual camera mode with dynamic camera position switching
                    // Check isCamerasSwitched to determine which camera goes on top
                    VStack(spacing: 0) {
                        // Top Camera (switches based on isCamerasSwitched)
                        ZStack {
                            if viewModel.isCamerasSwitched {
                                // Front camera on top when switched
                                CameraPreviewView(
                                    previewLayer: viewModel.cameraManager.frontPreviewLayer,
                                    position: .front,
                                    onZoomChange: { factor in
                                        viewModel.updateFrontZoom(factor)
                                    },
                                    currentZoom: viewModel.configuration.frontZoomFactor,
                                    minZoom: viewModel.configuration.frontMinZoom,
                                    maxZoom: viewModel.configuration.frontMaxZoom
                                )
                            } else {
                                // Back camera on top by default
                                CameraPreviewView(
                                    previewLayer: viewModel.cameraManager.backPreviewLayer,
                                    position: .back,
                                    onZoomChange: { factor in
                                        viewModel.updateBackZoom(factor)
                                    },
                                    currentZoom: viewModel.configuration.backZoomFactor,
                                    minZoom: viewModel.configuration.backMinZoom,
                                    maxZoom: viewModel.configuration.backMaxZoom
                                )
                            }

                            // Grid overlay
                            if viewModel.showGrid {
                                GridOverlay()
                            }
                        }
                        .frame(height: geometry.size.height * 0.5)
                        .overlay(alignment: .topLeading) {
                            CameraLabel(
                                text: viewModel.isCamerasSwitched ? "Front" : "Back",
                                zoom: viewModel.isCamerasSwitched ? viewModel.configuration.frontZoomFactor : viewModel.configuration.backZoomFactor
                            )
                            .padding(.top, max(geometry.safeAreaInsets.top + 70, 80))
                            .padding(.leading, 20)
                        }
                        .overlay(alignment: .topTrailing) {
                            if viewModel.isRecording {
                                RecordingIndicator(duration: viewModel.recordingDuration)
                                    .padding(.top, max(geometry.safeAreaInsets.top + 70, 80))
                                    .padding(.trailing, 20)
                            }
                        }

                        // Divider
                        Rectangle()
                            .fill(.white.opacity(0.3))
                            .frame(height: 2)

                        // Bottom Camera (switches based on isCamerasSwitched)
                        ZStack {
                            if viewModel.isCamerasSwitched {
                                // Back camera on bottom when switched
                                CameraPreviewView(
                                    previewLayer: viewModel.cameraManager.backPreviewLayer,
                                    position: .back,
                                    onZoomChange: { factor in
                                        viewModel.updateBackZoom(factor)
                                    },
                                    currentZoom: viewModel.configuration.backZoomFactor,
                                    minZoom: viewModel.configuration.backMinZoom,
                                    maxZoom: viewModel.configuration.backMaxZoom
                                )
                            } else {
                                // Front camera on bottom by default
                                CameraPreviewView(
                                    previewLayer: viewModel.cameraManager.frontPreviewLayer,
                                    position: .front,
                                    onZoomChange: { factor in
                                        viewModel.updateFrontZoom(factor)
                                    },
                                    currentZoom: viewModel.configuration.frontZoomFactor,
                                    minZoom: viewModel.configuration.frontMinZoom,
                                    maxZoom: viewModel.configuration.frontMaxZoom
                                )
                            }

                            // Grid overlay
                            if viewModel.showGrid {
                                GridOverlay()
                            }
                        }
                        .frame(height: geometry.size.height * 0.5)
                        .overlay(alignment: .bottomLeading) {
                            CameraLabel(
                                text: viewModel.isCamerasSwitched ? "Back" : "Front",
                                zoom: viewModel.cameraManager.isCamerasSwitched ? viewModel.configuration.backZoomFactor : viewModel.configuration.frontZoomFactor
                            )
                            .padding(.bottom, 24)
                            .padding(.leading, 20)
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
                            currentZoom: viewModel.configuration.backZoomFactor,
                            minZoom: viewModel.configuration.backMinZoom,  // ✅ ZOOM FIX
                            maxZoom: viewModel.configuration.backMaxZoom
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
                                .padding(.top, max(geometry.safeAreaInsets.top + 50, 60))
                                .padding(.trailing, 16)
                        }
                    }
                }

                // Only show UI controls when camera is ready
                if viewModel.isCameraReady {
                    // Top Overlay - Toolbar and Timer
                    VStack(spacing: 12) {
                        HStack {
                            Spacer()

                            // Top Toolbar (right side) - with Dynamic Island clearance
                            TopToolbar()
                                .padding(.top, max(geometry.safeAreaInsets.top + 70, 80))
                                .padding(.trailing, 20)
                        }

                        // Timer Display - only show when recording
                        if viewModel.isRecording {
                            TimerDisplay(duration: viewModel.recordingDuration)
                        }

                        Spacer()
                    }

                    // Zoom Control - Positioned dynamically to avoid overlap
                    VStack {
                        Spacer()

                        ZoomControl(
                            currentZoom: viewModel.configuration.backZoomFactor,
                            availableZooms: [0.5, 1.0, 2.0],
                            onZoomChange: { factor in
                                viewModel.updateBackZoom(factor)
                            }
                        )
                        .padding(.bottom, calculateZoomControlPadding(geometry))
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
                                // ✅ FIX Issue #1: Call appropriate function based on capture mode
                                if viewModel.currentCaptureMode.isRecordingMode {
                                    viewModel.executeVideoRecording()
                                } else {
                                    viewModel.executePhotoCapture()
                                }
                            },
                            onCancel: {
                                viewModel.cancelTimerCountdown()
                            }
                        )
                        .transition(.opacity)
                        .zIndex(100)
                    }

                    // Success Toast
                    if viewModel.showSaveSuccessToast {
                        VStack {
                            Spacer()
                            HStack(spacing: 12) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundStyle(.green)

                                Text(viewModel.saveSuccessMessage)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.white)
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 14)
                            .background {
                                Capsule()
                                    .fill(.ultraThinMaterial)
                                    .overlay {
                                        Capsule()
                                            .fill(.black.opacity(0.3))
                                    }
                            }
                            .shadow(color: .black.opacity(0.3), radius: 15, y: 5)
                            .padding(.bottom, max(geometry.safeAreaInsets.bottom, 16) + 140)
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .zIndex(99)
                    }
                }
            }
            .onTapGesture {
                viewModel.toggleControlsVisibility()
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: viewModel.showSaveSuccessToast)
            .sheet(isPresented: $viewModel.showSettings) {
                SettingsView(viewModel: viewModel)
            }

        }
        .ignoresSafeArea()
    }

    // Calculate zoom control padding to prevent overlap with bottom controls
    private func calculateZoomControlPadding(_ geometry: GeometryProxy) -> CGFloat {
        // ModeSelector height: ~44pt
        // Bottom controls height: ~76pt (button container)
        // Bottom padding: safeArea + 16 + 16
        let controlPanelHeight: CGFloat = 44 + 76 + max(geometry.safeAreaInsets.bottom, 16) + 32
        return controlPanelHeight + 8 // 8pt gap between zoom and controls
    }
}

#Preview {
    DualCameraView()
        .environmentObject(CameraViewModel())
}
