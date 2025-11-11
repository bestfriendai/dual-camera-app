//
//  SettingsView.swift
//  DualLensPro
//
//  Created by DualLens Pro Team on 10/24/25.
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: CameraViewModel
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            Form {
                // VIDEO QUALITY
                Section {
                    ForEach(RecordingQuality.allCases, id: \.self) { quality in
                        Button {
                            // ✅ FIX Issue #5: Warn about 4K limitation in multi-cam mode
                            if quality == .ultra && viewModel.cameraManager.useMultiCam {
                                HapticManager.shared.warning()
                                // Still allow setting, but will automatically downgrade to 1080p
                            } else {
                                HapticManager.shared.selection()
                            }
                            viewModel.setRecordingQuality(quality)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(quality.rawValue)
                                        .foregroundColor(.primary)

                                    // Show warning for unsupported combinations
                                    if quality == .ultra && viewModel.cameraManager.useMultiCam {
                                        Text("Dual camera limited to 1080p")
                                            .font(.caption)
                                            .foregroundColor(.orange)
                                    }
                                }
                                Spacer()
                                if viewModel.recordingQuality == quality {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                        .accessibilityHidden(true)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(quality.rawValue)
                        .accessibilityAddTraits(viewModel.recordingQuality == quality ? .isSelected : [])
                    }
                } header: {
                    Text("VIDEO QUALITY")
                } footer: {
                    if viewModel.cameraManager.useMultiCam {
                        Text("Multi-camera recording is limited to 1080p at 30fps per Apple hardware restrictions. Higher quality settings will be adjusted automatically.")
                    } else {
                        Text("Higher quality requires more storage space")
                    }
                }

                // ASPECT RATIO
                Section {
                    ForEach(AspectRatio.allCases, id: \.self) { ratio in
                        Button {
                            HapticManager.shared.selection()
                            viewModel.setAspectRatio(ratio)
                        } label: {
                            HStack {
                                Text(ratio.displayName)
                                    .foregroundColor(.primary)
                                Spacer()
                                if viewModel.aspectRatio == ratio {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                        .accessibilityHidden(true)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(ratio.displayName)
                        .accessibilityAddTraits(viewModel.aspectRatio == ratio ? .isSelected : [])
                    }
                } header: {
                    Text("ASPECT RATIO")
                }

                // VIDEO STABILIZATION
                Section {
                    ForEach(VideoStabilizationMode.allCases, id: \.self) { mode in
                        Button {
                            HapticManager.shared.selection()
                            viewModel.setVideoStabilization(mode)
                        } label: {
                            HStack {
                                Text(mode.displayName)
                                    .foregroundColor(.primary)
                                Spacer()
                                if viewModel.videoStabilization == mode {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("STABILIZATION")
                } footer: {
                    Text("Cinematic mode provides the smoothest footage")
                }

                // WHITE BALANCE
                Section {
                    ForEach(WhiteBalanceMode.allCases, id: \.self) { mode in
                        Button {
                            HapticManager.shared.selection()
                            viewModel.setWhiteBalance(mode)
                        } label: {
                            HStack {
                                Text(mode.displayName)
                                    .foregroundColor(.primary)
                                Spacer()
                                if viewModel.whiteBalanceMode == mode {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("WHITE BALANCE")
                }

                // TIMER
                Section {
                    ForEach([0, 3, 10], id: \.self) { duration in
                        Button {
                            HapticManager.shared.selection()
                            viewModel.setTimer(duration)
                        } label: {
                            HStack {
                                Text(duration == 0 ? "Off" : "\(duration) seconds")
                                    .foregroundColor(.primary)
                                Spacer()
                                if viewModel.timerDuration == duration {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("SELF-TIMER")
                }

                // CAMERA FEATURES
                Section {
                    Toggle("Grid Overlay", isOn: Binding(
                        get: { viewModel.showGrid },
                        set: { _ in
                            HapticManager.shared.light()
                            viewModel.toggleGrid()
                        }
                    ))
                    .accessibilityHint("Shows composition grid on camera preview")

                    Toggle("Center Stage", isOn: Binding(
                        get: { viewModel.isCenterStageEnabled },
                        set: { _ in
                            HapticManager.shared.light()
                            viewModel.toggleCenterStage()
                        }
                    ))
                    .accessibilityHint("Automatically keeps you centered in frame")
                } header: {
                    Text("CAMERA FEATURES")
                } footer: {
                    Text("Center Stage keeps you in frame on supported devices")
                }

                // EXPOSURE & FOCUS
                Section {
                    Toggle("Lock Focus", isOn: Binding(
                        get: { viewModel.cameraManager.isFocusLocked },
                        set: { _ in
                            HapticManager.shared.light()
                            viewModel.toggleFocusLock(for: .back)
                        }
                    ))
                    .accessibilityHint("Prevents automatic focus adjustment")

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Exposure Compensation")
                                .font(.subheadline)
                            Spacer()
                            Text(String(format: "%.1f", viewModel.cameraManager.exposureValue))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        HStack {
                            Text("-2")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Slider(
                                value: Binding(
                                    get: { Double(viewModel.cameraManager.exposureValue) },
                                    set: {
                                        HapticManager.shared.light()
                                        viewModel.setExposure(Float($0), for: .back)
                                    }
                                ),
                                in: -2.0...2.0,
                                step: 0.1
                            )
                            Text("+2")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("FOCUS & EXPOSURE")
                }

                // ADVANCED CONTROLS
                Section {
                    Button {
                        HapticManager.shared.medium()
                        dismiss()
                        // Delay to allow dismiss animation to complete
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            viewModel.showAdvancedControls = true
                        }
                    } label: {
                        HStack {
                            Image(systemName: "slider.horizontal.3")
                                .foregroundColor(.blue)
                                .frame(width: 24)
                            Text("Advanced Controls")
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .accessibilityLabel("Advanced Controls")
                    .accessibilityHint("Opens advanced camera controls panel")
                } header: {
                    Text("ADVANCED")
                } footer: {
                    Text("Access fine-tuned camera controls for professional recording")
                }

                // APP SETTINGS
                Section {
                    Toggle("Haptic Feedback", isOn: Binding(
                        get: { viewModel.settingsViewModel.hapticFeedbackEnabled },
                        set: { _ in
                            viewModel.settingsViewModel.hapticFeedbackEnabled.toggle()
                        }
                    ))

                    Toggle("Sound Effects", isOn: Binding(
                        get: { viewModel.settingsViewModel.soundEffectsEnabled },
                        set: { _ in
                            HapticManager.shared.light()
                            viewModel.settingsViewModel.soundEffectsEnabled.toggle()
                        }
                    ))

                    Toggle("Auto-Save to Library", isOn: Binding(
                        get: { viewModel.settingsViewModel.autoSaveToLibrary },
                        set: { _ in
                            HapticManager.shared.light()
                            viewModel.settingsViewModel.autoSaveToLibrary.toggle()
                        }
                    ))
                } header: {
                    Text("APP SETTINGS")
                }

                // DEFAULT MODE
                Section {
                    ForEach(CaptureMode.allCases, id: \.self) { mode in
                        Button {
                            // ✅ FIX Issue #5: Warn about 120fps limitation in multi-cam mode
                            if mode == .action && viewModel.cameraManager.useMultiCam {
                                HapticManager.shared.warning()
                            } else {
                                HapticManager.shared.selection()
                            }
                            viewModel.settingsViewModel.defaultCaptureMode = mode
                        } label: {
                            HStack {
                                Image(systemName: mode.systemIconName)
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(mode.displayName)
                                        .foregroundColor(.primary)

                                    // Show warning for unsupported combinations
                                    if mode == .action && viewModel.cameraManager.useMultiCam {
                                        Text("Not available in dual camera mode")
                                            .font(.caption)
                                            .foregroundColor(.orange)
                                    }
                                }
                                Spacer()
                                if viewModel.settingsViewModel.defaultCaptureMode == mode {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("DEFAULT CAPTURE MODE")
                } footer: {
                    if viewModel.cameraManager.useMultiCam {
                        Text("Action mode (120fps) requires single camera mode. Switch to single camera to use high frame rate recording.")
                    } else {
                        Text("The mode that will be selected when app launches")
                    }
                }

                // SUBSCRIPTION
                Section {
                    HStack {
                        Text("Status")
                        Spacer()
                        Text(viewModel.isPremium ? "Premium" : "Free")
                            .foregroundColor(viewModel.isPremium ? .green : .orange)
                            .fontWeight(.semibold)
                    }

                    if !viewModel.isPremium {
                        Button {
                            HapticManager.shared.medium()
                            viewModel.showPremiumPrompt()
                        } label: {
                            HStack {
                                Image(systemName: "crown.fill")
                                    .foregroundColor(.yellow)
                                Text("Upgrade to Premium")
                                    .foregroundColor(.blue)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        HapticManager.shared.light()
                        Task {
                            await viewModel.restorePurchases()
                        }
                    } label: {
                        HStack {
                            Text("Restore Purchases")
                                .foregroundColor(.blue)
                        }
                    }
                    .buttonStyle(.plain)
                } header: {
                    Text("SUBSCRIPTION")
                }

                // ABOUT
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(viewModel.settingsViewModel.appVersion)
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Build")
                        Spacer()
                        Text(viewModel.settingsViewModel.buildNumber)
                            .foregroundColor(.secondary)
                    }

                    Button {
                        HapticManager.shared.light()
                        viewModel.settingsViewModel.confirmReset()
                    } label: {
                        HStack {
                            Text("Reset All Settings")
                                .foregroundColor(.red)
                        }
                    }
                    .buttonStyle(.plain)
                } header: {
                    Text("ABOUT")
                } footer: {
                    Text("DualLensPro - Professional Dual Camera Recording")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        HapticManager.shared.light()
                        dismiss()
                    }
                }
            }
            .alert("Reset Settings", isPresented: $viewModel.settingsViewModel.showResetConfirmation) {
                Button("Cancel", role: .cancel) {
                    HapticManager.shared.light()
                }
                Button("Reset", role: .destructive) {
                    HapticManager.shared.medium()
                    viewModel.settingsViewModel.resetToDefaults()
                }
            } message: {
                Text("This will reset all settings to their default values. This cannot be undone.")
            }
        }
    }
}

#Preview {
    SettingsView(viewModel: CameraViewModel())
}
