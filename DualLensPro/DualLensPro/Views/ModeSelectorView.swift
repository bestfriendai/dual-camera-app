//
//  ModeSelectorView.swift
//  DualLensPro
//
//  Created by DualLens Pro Team on 10/24/25.
//

import SwiftUI

struct ModeSelectorView: View {
    @EnvironmentObject var viewModel: CameraViewModel
    @State private var selectedMode: CaptureMode = .video

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(CaptureMode.allCases) { mode in
                    ModeButton(
                        mode: mode,
                        isSelected: selectedMode == mode,
                        isPremium: viewModel.isPremium,
                        action: {
                            selectMode(mode)
                        }
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .liquidGlass(tint: .black, opacity: 0.3)
        .onAppear {
            selectedMode = viewModel.currentCaptureMode
        }
    }

    private func selectMode(_ mode: CaptureMode) {
        // Check if mode requires premium
        if mode.requiresPremium && !viewModel.isPremium {
            viewModel.showPremiumPrompt()
            return
        }

        selectedMode = mode
        viewModel.setCaptureMode(mode)
    }
}

struct ModeButton: View {
    let mode: CaptureMode
    let isSelected: Bool
    let isPremium: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: mode.systemIconName)
                        .font(.title2)
                        .foregroundStyle(isSelected ? (mode == .video ? .black : .white) : .white.opacity(0.6))

                    // Premium badge
                    if mode.requiresPremium && !isPremium {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.yellow)
                            .offset(x: 6, y: -6)
                    }
                }

                Text(mode.displayName)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(isSelected ? (mode == .video ? .black : .white) : .white.opacity(0.6))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: 70)
            }
            .frame(width: 80, height: 70)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? (mode == .video ? Color.yellow : Color.white.opacity(0.2)) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? (mode == .video ? Color.yellow.opacity(0.6) : Color.white.opacity(0.4)) : Color.clear, lineWidth: 2)
            )
        }
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()

        VStack {
            Spacer()
            ModeSelectorView()
        }
    }
    .environmentObject(CameraViewModel())
}
