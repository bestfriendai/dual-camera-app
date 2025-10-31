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
            .font(.system(size: 16, weight: .medium, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Capsule()
                            .fill(.black.opacity(0.3))
                    }
            }
            .shadow(color: .black.opacity(0.2), radius: 4, y: 1)
            .accessibilityLabel("Recording time")
            .accessibilityValue(formattedAccessibilityTime)
    }

    private var formattedTime: String {
        let totalSeconds = Int(duration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        // Use MM:SS for recordings under 1 hour, HH:MM:SS for 1 hour or more
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }

    private var formattedAccessibilityTime: String {
        let totalSeconds = Int(duration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        var components: [String] = []
        if hours > 0 {
            components.append("\(hours) hour\(hours == 1 ? "" : "s")")
        }
        if minutes > 0 {
            components.append("\(minutes) minute\(minutes == 1 ? "" : "s")")
        }
        if seconds > 0 || components.isEmpty {
            components.append("\(seconds) second\(seconds == 1 ? "" : "s")")
        }

        return components.joined(separator: ", ")
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
