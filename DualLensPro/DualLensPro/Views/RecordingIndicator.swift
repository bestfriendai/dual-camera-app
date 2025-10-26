
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
        HStack(spacing: 8) {
            // Pulsing red dot
            Circle()
                .fill(.red)
                .frame(width: 8, height: 8)
                .opacity(isAnimating ? 0.4 : 1.0)
                .onAppear {
                    withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                        isAnimating = true
                    }
                }

            // Time
            Text(formatTime(duration))
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background {
            Capsule()
                .fill(.red.opacity(0.9))
        }
        .shadow(color: .black.opacity(0.3), radius: 4, y: 1)
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
