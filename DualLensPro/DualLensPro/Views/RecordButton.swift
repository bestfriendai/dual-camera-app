
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
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: {
            action()
            triggerHaptic()
        }) {
            ZStack {
                // Recording pulse effect
                if isRecording {
                    Circle()
                        .fill(.red.opacity(0.3))
                        .frame(width: 72, height: 72)
                        .scaleEffect(pulseAnimation ? 1.3 : 1.0)
                        .opacity(pulseAnimation ? 0 : 0.6)
                }

                // Outer ring with recording color
                Circle()
                    .strokeBorder(isRecording ? .red : .white, lineWidth: 3)
                    .frame(width: 72, height: 72)

                // Inner button
                if isRecording {
                    // Recording state - rounded square with red fill
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.red)
                        .frame(width: 28, height: 28)
                } else {
                    // Ready state - circle
                    Circle()
                        .fill(.white)
                        .frame(width: 60, height: 60)
                }
            }
            .scaleEffect(isPressed ? 0.9 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .animation(reduceMotion ? nil : .spring(response: 0.2, dampingFraction: 0.7), value: isPressed)
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7), value: isRecording)
        .onChange(of: isRecording) { _, newValue in
            if newValue && !reduceMotion {
                startPulseAnimation()
            } else {
                pulseAnimation = false
            }
        }
        // Accessibility
        .accessibilityLabel(isRecording ? "Stop recording" : "Start recording")
        .accessibilityHint(isRecording ? "Double tap to stop recording" : "Double tap to start recording")
        .accessibilityAddTraits(isRecording ? .startsMediaSession : [])
        .accessibilityValue(isRecording ? "Recording in progress" : "Ready to record")
    }

    private func startPulseAnimation() {
        withAnimation(.easeOut(duration: 1.5).repeatForever(autoreverses: false)) {
            pulseAnimation = true
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
