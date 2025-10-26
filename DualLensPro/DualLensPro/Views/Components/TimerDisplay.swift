//
//  TimerDisplay.swift
//  DualLensPro
//
//  Created by DualLens Pro Team on 10/24/25.
//

import SwiftUI

struct TimerDisplay: View {
    let duration: TimeInterval
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Text(formattedTime)
            .font(.system(size: 20, weight: .semibold, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background {
                if !reduceTransparency {
                    ZStack {
                        Capsule()
                            .fill(.ultraThinMaterial)

                        LinearGradient(
                            colors: [
                                .black.opacity(0.4),
                                .black.opacity(0.2)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .clipShape(Capsule())

                        Capsule()
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        .white.opacity(0.3),
                                        .white.opacity(0.15)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    }
                    .shadow(color: .black.opacity(0.3), radius: 10, y: 5)
                } else {
                    Capsule()
                        .fill(.regularMaterial)
                        .opacity(0.9)
                }
            }
    }

    private var formattedTime: String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()

        VStack(spacing: 20) {
            TimerDisplay(duration: 0)
            TimerDisplay(duration: 125)
            TimerDisplay(duration: 3665)
        }
    }
}
