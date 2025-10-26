
//
//  RecordingIndicator.swift
//  DualLensPro
//
//  Created by DualLens Pro Team on 10/24/25.
//

import SwiftUI

struct RecordingIndicator: View {
    let duration: TimeInterval
    @State private var isAnimating = false
    
    var body: some View {
        HStack(spacing: 10) {
            // Pulsing dot with glow
            ZStack {
                // Glow effect
                Circle()
                    .fill(.red.opacity(0.4))
                    .frame(width: 14, height: 14)
                    .scaleEffect(isAnimating ? 1.5 : 1.0)
                    .opacity(isAnimating ? 0 : 0.6)

                // Main dot
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [.red.opacity(0.9), .red],
                            center: .center,
                            startRadius: 0,
                            endRadius: 5
                        )
                    )
                    .frame(width: 10, height: 10)
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: false)) {
                    isAnimating = true
                }
            }

            // Time
            Text(formatTime(duration))
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .liquidGlass(tint: .red, opacity: 0.25)
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        RecordingIndicator(duration: 125.5)
    }
}
