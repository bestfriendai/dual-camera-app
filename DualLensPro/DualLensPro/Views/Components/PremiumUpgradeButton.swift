//
//  PremiumUpgradeButton.swift
//  DualLensPro
//
//  Created by DualLens Pro Team on 10/24/25.
//

import SwiftUI

struct PremiumUpgradeButton: View {
    let maxDuration: String
    let onUpgrade: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: {
            onUpgrade()
            triggerHaptic()
        }) {
            HStack(spacing: 6) {
                Image(systemName: "star.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.yellow)

                Text("\(maxDuration) Max")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)

                Text("-")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))

                Text("Upgrade")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.blue)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background {
                ZStack {
                    Capsule()
                        .fill(.ultraThinMaterial)

                    LinearGradient(
                        colors: [
                            .blue.opacity(0.35),
                            .blue.opacity(0.15),
                            .blue.opacity(0.25)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .clipShape(Capsule())

                    Capsule()
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    .blue.opacity(0.7),
                                    .blue.opacity(0.4),
                                    .blue.opacity(0.6)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )
                }
                .shadow(color: .blue.opacity(0.4), radius: 12, y: 6)
            }
        }
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPressed)
    }

    private func triggerHaptic() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()

        VStack(spacing: 20) {
            PremiumUpgradeButton(maxDuration: "3 Minutes") {}
            PremiumUpgradeButton(maxDuration: "5 Minutes") {}
        }
    }
}
