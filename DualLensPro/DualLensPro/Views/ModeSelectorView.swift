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

    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(mode.displayName.uppercased())
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular, design: .default))
                    .foregroundStyle(isSelected ? .yellow : .white)
                    .tracking(0.5)

                // Premium badge
                if mode.requiresPremium && !isPremium {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(.yellow)
                }
            }
            .padding(.horizontal, isSelected ? 16 : 8)
            .padding(.vertical, 8)
            .background {
                if isSelected {
                    Capsule()
                        .fill(.white.opacity(0.15))
                }
            }
            .scaleEffect(isPressed ? 0.95 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isPressed)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
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
