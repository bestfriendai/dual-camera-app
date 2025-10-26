//
//  ZoomControl.swift
//  DualLensPro
//
//  Created by DualLens Pro Team on 10/24/25.
//

import SwiftUI

struct ZoomControl: View {
    let currentZoom: CGFloat
    let availableZooms: [CGFloat]
    let onZoomChange: (CGFloat) -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: {
            HapticManager.shared.zoomChange()
            cycleZoom()
        }) {
            Text(zoomText)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 64, height: 64)
                .background {
                    ZStack {
                        Circle()
                            .fill(.ultraThinMaterial)

                        RadialGradient(
                            colors: [
                                .white.opacity(0.25),
                                .white.opacity(0.05)
                            ],
                            center: .topLeading,
                            startRadius: 0,
                            endRadius: 32
                        )

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
                                lineWidth: 2
                            )
                    }
                    .shadow(color: .black.opacity(0.25), radius: 10, y: 5)
                }
        }
        .scaleEffect(isPressed ? 0.92 : 1.0)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPressed)
        .animation(.spring(response: 0.4, dampingFraction: 0.65), value: currentZoom)
    }

    private var zoomText: String {
        if currentZoom < 1.0 {
            return String(format: "%.1fx", currentZoom)
        } else {
            return String(format: "%.0fx", currentZoom)
        }
    }

    private func cycleZoom() {
        guard let currentIndex = availableZooms.firstIndex(where: { abs($0 - currentZoom) < 0.01 }) else {
            onZoomChange(availableZooms.first ?? 1.0)
            return
        }

        let nextIndex = (currentIndex + 1) % availableZooms.count
        onZoomChange(availableZooms[nextIndex])
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()

        VStack(spacing: 20) {
            ZoomControl(currentZoom: 0.5, availableZooms: [0.5, 1.0, 2.0]) { _ in }
            ZoomControl(currentZoom: 1.0, availableZooms: [0.5, 1.0, 2.0]) { _ in }
            ZoomControl(currentZoom: 2.0, availableZooms: [0.5, 1.0, 2.0]) { _ in }
        }
    }
}
