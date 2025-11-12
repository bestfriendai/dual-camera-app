//
//  AdvancedControlsView.swift
//  DualLensPro
//
//  Created by DualLens Pro Team on 10/24/25.
//

import SwiftUI

struct AdvancedControlsView: View {
    @EnvironmentObject var viewModel: CameraViewModel
    @State private var exposureValue: Float = 0.0
    @State private var selectedCamera: CameraPosition = .back

    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Text("Advanced Controls")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)

                Spacer()

                Button(action: {
                    viewModel.toggleAdvancedControls()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)

            ScrollView {
                VStack(spacing: 24) {
                    // Camera Selection
                    CameraSelector(selectedCamera: $selectedCamera)

                    // White Balance
                    ControlSection(title: "White Balance") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(WhiteBalanceMode.allCases) { mode in
                                    WhiteBalanceButton(
                                        mode: mode,
                                        isSelected: viewModel.whiteBalanceMode == mode
                                    ) {
                                        viewModel.setWhiteBalance(mode)
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }

                    // Exposure Compensation
                    ControlSection(title: "Exposure") {
                        VStack(spacing: 8) {
                            HStack {
                                Text("-2")
                                    .font(.system(size: 12))
                                    .foregroundColor(.white.opacity(0.6))

                                Slider(value: $exposureValue, in: -2...2, step: 0.1)
                                    .tint(.white)
                                    .onChange(of: exposureValue) { _, newValue in
                                        viewModel.setExposure(newValue, for: selectedCamera)
                                    }

                                Text("+2")
                                    .font(.system(size: 12))
                                    .foregroundColor(.white.opacity(0.6))
                            }

                            Text(String(format: "%.1f EV", exposureValue))
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 20)
                    }

                    // Video Stabilization
                    ControlSection(title: "Video Stabilization") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(VideoStabilizationMode.allCases) { mode in
                                    StabilizationButton(
                                        mode: mode,
                                        isSelected: viewModel.videoStabilization == mode
                                    ) {
                                        viewModel.setVideoStabilization(mode)
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }

                    // Recording Quality
                    ControlSection(title: "Recording Quality") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(RecordingQuality.allCases, id: \.rawValue) { quality in
                                    QualityButton(
                                        quality: quality,
                                        isSelected: viewModel.recordingQuality == quality
                                    ) {
                                        viewModel.setRecordingQuality(quality)
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }

                    // Focus Lock Toggle
                    ControlSection(title: "Focus") {
                        HStack {
                            Text("Focus Lock")
                                .font(.system(size: 16))
                                .foregroundColor(.white)

                            Spacer()

                            Toggle("", isOn: Binding(
                                get: { viewModel.cameraManager.isFocusLocked },
                                set: { _ in
                                    viewModel.toggleFocusLock(for: selectedCamera)
                                }
                            ))
                            .tint(.blue)
                        }
                        .padding(.horizontal, 20)
                    }
                }
                .padding(.bottom, 20)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(.black.opacity(0.95))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(.white.opacity(0.1), lineWidth: 1)
        )
        // ✅ FIX Issue #8: Initialize state from camera manager when view appears
        .onAppear {
            // Load current exposure value from camera manager
            exposureValue = viewModel.cameraManager.exposureValue
        }
    }
}

struct CameraSelector: View {
    @Binding var selectedCamera: CameraPosition

    var body: some View {
        HStack(spacing: 12) {
            ForEach([CameraPosition.front, CameraPosition.back], id: \.self) { position in
                Button(action: {
                    selectedCamera = position
                }) {
                    Text(position == .front ? "Front" : "Back")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(selectedCamera == position ? .white : .white.opacity(0.6))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(selectedCamera == position ? .blue : .white.opacity(0.1))
                        )
                }
            }
        }
        .padding(.horizontal, 20)
    }
}

struct ControlSection<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white.opacity(0.8))
                .padding(.horizontal, 20)

            content
        }
    }
}

struct WhiteBalanceButton: View {
    let mode: WhiteBalanceMode
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(mode.displayName)
                .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? .white : .white.opacity(0.6))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(isSelected ? .blue : .white.opacity(0.1))
                )
        }
    }
}

struct StabilizationButton: View {
    let mode: VideoStabilizationMode
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(mode.displayName)
                .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? .white : .white.opacity(0.6))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(isSelected ? .blue : .white.opacity(0.1))
                )
        }
    }
}

struct QualityButton: View {
    let quality: RecordingQuality
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(quality.rawValue)
                .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? .white : .white.opacity(0.6))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(isSelected ? .blue : .white.opacity(0.1))
                )
        }
    }
}

#Preview {
    ZStack {
        Color.gray.ignoresSafeArea()

        AdvancedControlsView()
            .environmentObject(CameraViewModel())
            .padding()
    }
}
