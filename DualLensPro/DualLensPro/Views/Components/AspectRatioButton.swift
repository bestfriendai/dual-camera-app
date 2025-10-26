//
//  AspectRatioButton.swift
//  DualLensPro
//
//  Created by DualLens Pro Team on 10/24/25.
//

import SwiftUI

extension AspectRatio {
    var icon: String {
        switch self {
        case .ratio16_9: return "rectangle"
        case .ratio4_3: return "rectangle.portrait"
        case .ratio1_1: return "square"
        }
    }
}

struct AspectRatioButton: View {
    @Binding var currentRatio: AspectRatio

    @State private var isPressed = false

    var body: some View {
        Button(action: {
            HapticManager.shared.selection()
            cycleAspectRatio()
        }) {
            VStack(spacing: 4) {
                Image(systemName: currentRatio.icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.white)

                Text(currentRatio.displayName)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))
            }
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
        .scaleEffect(isPressed ? 0.92 : 1.0)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPressed)
        .animation(.spring(response: 0.4, dampingFraction: 0.65), value: currentRatio)
    }

    private func cycleAspectRatio() {
        if let currentIndex = AspectRatio.allCases.firstIndex(of: currentRatio) {
            let nextIndex = (currentIndex + 1) % AspectRatio.allCases.count
            currentRatio = AspectRatio.allCases[nextIndex]
        }
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()

        VStack(spacing: 20) {
            AspectRatioButton(currentRatio: .constant(.ratio16_9))
            AspectRatioButton(currentRatio: .constant(.ratio4_3))
            AspectRatioButton(currentRatio: .constant(.ratio1_1))
        }
    }
}
