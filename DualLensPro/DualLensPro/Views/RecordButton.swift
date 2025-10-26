
//
//  RecordButton.swift
//  DualLensPro
//
//  Created by DualLens Pro Team on 10/24/25.
//

import SwiftUI

struct RecordButton: View {
    let isRecording: Bool
    let action: () -> Void

    @State private var isPressed = false
    @State private var pulseAnimation = false
    @State private var glowAnimation = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Button(action: {
            action()
            triggerHaptic()
        }) {
            ZStack {
                // Outer glow ring for recording state
                if isRecording && !reduceTransparency {
                    Circle()
                        .fill(.red.opacity(0.2))
                        .frame(width: 100, height: 100)
                        .scaleEffect(glowAnimation ? 1.1 : 1.0)
                        .opacity(glowAnimation ? 0 : 0.4)
                }

                // Outer liquid glass ring
                Circle()
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.5),
                                .white.opacity(0.2)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 4
                    )
                    .frame(width: 88, height: 88)
                    .shadow(color: .black.opacity(0.3), radius: 10, y: 5)

                // Inner button with liquid glass background
                ZStack {
                    // Glass background
                    if !reduceTransparency {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 72, height: 72)
                    }

                    if isRecording {
                        // Recording state - rounded square
                        RoundedRectangle(cornerRadius: 10)
                            .fill(
                                RadialGradient(
                                    colors: [
                                        .red.opacity(0.9),
                                        .red
                                    ],
                                    center: .topLeading,
                                    startRadius: 0,
                                    endRadius: 40
                                )
                            )
                            .frame(width: 44, height: 44)
                            .shadow(color: .red.opacity(0.5), radius: 8)
                    } else {
                        // Ready state - circle
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [
                                        .red.opacity(0.9),
                                        .red
                                    ],
                                    center: .topLeading,
                                    startRadius: 0,
                                    endRadius: 36
                                )
                            )
                            .frame(width: 68, height: 68)
                            .overlay {
                                Circle()
                                    .strokeBorder(.white.opacity(0.2), lineWidth: 2)
                                    .frame(width: 68, height: 68)
                            }
                            .shadow(color: .red.opacity(0.4), radius: 12, y: 6)
                    }
                }
                .scaleEffect(isPressed ? 0.9 : 1.0)
                .scaleEffect(pulseAnimation && isRecording ? 1.05 : 1.0)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .onChange(of: isRecording) { _, newValue in
            if newValue {
                startPulseAnimation()
                startGlowAnimation()
            } else {
                pulseAnimation = false
                glowAnimation = false
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPressed)
        .animation(.spring(response: 0.4, dampingFraction: 0.6), value: isRecording)
    }

    private func startPulseAnimation() {
        withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
            pulseAnimation = true
        }
    }

    private func startGlowAnimation() {
        withAnimation(.easeOut(duration: 1.5).repeatForever(autoreverses: false)) {
            glowAnimation = true
        }
    }

    private func triggerHaptic() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        
        VStack(spacing: 40) {
            RecordButton(isRecording: false, action: {})
            RecordButton(isRecording: true, action: {})
        }
    }
}
