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
