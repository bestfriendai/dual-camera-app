//
//  TimerCountdownView.swift
//  DualLensPro
//
//  Created by DualLens Pro Team on 10/24/25.
//

import SwiftUI

/// Full-screen countdown overlay for self-timer
struct TimerCountdownView: View {
    let duration: Int
    let onComplete: () -> Void
    let onCancel: () -> Void

    @State private var currentCount: Int
    @State private var scale: CGFloat = 0.3
    @State private var opacity: Double = 0
    @State private var ringProgress: CGFloat = 0

    init(duration: Int, onComplete: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.duration = duration
        self.onComplete = onComplete
        self.onCancel = onCancel
        self._currentCount = State(initialValue: duration)
    }

    var body: some View {
        ZStack {
            // Semi-transparent background
            Color.black.opacity(0.7)
                .ignoresSafeArea()

            VStack(spacing: 40) {
                Spacer()

                // Countdown display
                ZStack {
                    // Animated ring
                    Circle()
                        .stroke(Color.white.opacity(0.2), lineWidth: 8)
                        .frame(width: 200, height: 200)

                    Circle()
                        .trim(from: 0, to: ringProgress)
                        .stroke(
                            currentCount <= 3 ? Color.red : Color.white,
                            style: StrokeStyle(lineWidth: 8, lineCap: .round)
                        )
                        .frame(width: 200, height: 200)
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 1.0), value: ringProgress)

                    // Countdown number
                    Text("\(currentCount)")
                        .font(.system(size: 120, weight: .bold, design: .rounded))
                        .foregroundStyle(currentCount <= 3 ? .red : .white)
                        .scaleEffect(scale)
                        .opacity(opacity)
                }

                // Instruction text
                Text(currentCount > 3 ? "Get ready..." : "Smile!")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.white)
                    .opacity(opacity)

                Spacer()

                // Cancel button
                Button(action: {
                    HapticManager.shared.medium()
                    onCancel()
                }) {
                    Text("Cancel")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 120, height: 50)
                }
                .capsuleGlass(tint: .red)
                .padding(.bottom, 60)
            }
        }
        .onAppear {
            startCountdown()
        }
    }

    private func startCountdown() {
        // Initial animation
        withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
            scale = 1.0
            opacity = 1.0
            ringProgress = 1.0 / CGFloat(duration)
        }

        // Play initial haptic
        HapticManager.shared.timerTick()

        // Start countdown timer
        Task {
            for count in (1...duration).reversed() {
                if count != currentCount {
                    // Update count
                    await MainActor.run {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            currentCount = count
                            scale = 0.3
                            opacity = 0
                        }
                    }

                    // Small delay for scale down
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

                    // Scale up with new number
                    await MainActor.run {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                            scale = 1.0
                            opacity = 1.0
                        }
                    }

                    // Update ring progress
                    await MainActor.run {
                        withAnimation(.linear(duration: 1.0)) {
                            ringProgress = CGFloat(duration - count + 1) / CGFloat(duration)
                        }
                    }

                    // Play haptic
                    if count <= 3 {
                        HapticManager.shared.timerFinal()
                    } else {
                        HapticManager.shared.timerTick()
                    }
                }

                // Wait 1 second
                if count > 1 {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
            }

            // Final delay before capture
            try? await Task.sleep(nanoseconds: 900_000_000) // 0.9 seconds

            // Trigger capture
            await MainActor.run {
                HapticManager.shared.photoCapture()
                onComplete()
            }
        }
    }
}

#Preview {
    ZStack {
        Color.gray.ignoresSafeArea()

        TimerCountdownView(duration: 3, onComplete: {
            print("Timer completed!")
        }, onCancel: {
            print("Timer cancelled!")
        })
    }
}
