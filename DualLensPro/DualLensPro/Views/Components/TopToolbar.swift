//
//  TopToolbar.swift
//  DualLensPro
//
//  Created by DualLens Pro Team on 10/24/25.
//

import SwiftUI

struct TopToolbar: View {
    @EnvironmentObject var viewModel: CameraViewModel
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
            .accessibilityLabel("Flash")
            .accessibilityHint("Double tap to toggle flash mode")
            .accessibilityValue({
                switch viewModel.flashMode {
                case .off: return "Off"
                case .on: return "On"
                case .auto: return "Auto"
                @unknown default: return "Off"
                }
            }())

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
            .accessibilityLabel("Self-timer")
            .accessibilityHint("Double tap to cycle through timer durations")
            .accessibilityValue(viewModel.timerDuration > 0 ? "\(viewModel.timerDuration) seconds" : "Off")

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
            .accessibilityLabel("Composition grid")
            .accessibilityHint("Double tap to toggle grid overlay")
            .accessibilityValue(viewModel.showGrid ? "On" : "Off")

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
            .accessibilityLabel("Settings")
            .accessibilityHint("Double tap to open settings")
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

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()

        VStack {
            TopToolbar()
                .padding()
            Spacer()
        }
    }
    .environmentObject(CameraViewModel())
}
