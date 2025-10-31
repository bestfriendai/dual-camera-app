//
//  FocusIndicator.swift
//  DualLensPro
//
//  Created by DualLens Pro Team on 10/30/25.
//

import SwiftUI

struct FocusIndicator: View {
    let position: CGPoint
    @Binding var isVisible: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var scale: CGFloat = 1.5
    @State private var opacity: Double = 1.0

    var body: some View {
        ZStack {
            // Outer square
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(Color.white, lineWidth: 2)
                .frame(width: 80, height: 80)

            // Inner square
            RoundedRectangle(cornerRadius: 2)
                .strokeBorder(Color.yellow, lineWidth: 2)
                .frame(width: 70, height: 70)
        }
        .scaleEffect(scale)
        .opacity(opacity)
        .position(position)
        .onAppear {
            // Trigger haptic feedback
            HapticManager.shared.light()

            if reduceMotion {
                // Simple animation for accessibility
                withAnimation(.easeOut(duration: 0.2)) {
                    scale = 1.0
                }

                // Auto-dismiss after 2 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    withAnimation(.easeOut(duration: 0.3)) {
                        opacity = 0.0
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        isVisible = false
                    }
                }
            } else {
                // Spring animation for scale
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    scale = 1.0
                }

                // Auto-dismiss after 2 seconds with fade
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    withAnimation(.easeOut(duration: 0.3)) {
                        opacity = 0.0
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        isVisible = false
                    }
                }
            }
        }
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()

        FocusIndicator(
            position: CGPoint(x: 200, y: 400),
            isVisible: .constant(true)
        )
    }
}
