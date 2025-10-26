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
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        HStack(spacing: 12) {
            ForEach(availableZooms, id: \.self) { zoom in
                ZoomLevelButton(
                    zoom: zoom,
                    isSelected: abs(currentZoom - zoom) < 0.01,
                    action: {
                        HapticManager.shared.zoomChange()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            onZoomChange(zoom)
                        }
                    }
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            if !reduceTransparency {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Capsule()
                            .fill(.black.opacity(0.2))
                    }
            } else {
                Capsule()
                    .fill(.black.opacity(0.6))
            }
        }
        .shadow(color: .black.opacity(0.2), radius: 8, y: 2)
    }
}

private struct ZoomLevelButton: View {
    let zoom: CGFloat
    let isSelected: Bool
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            Text(zoomText)
                .font(.system(size: 16, weight: isSelected ? .semibold : .regular, design: .rounded))
                .foregroundStyle(isSelected ? .yellow : .white)
                .frame(minWidth: 32)
                .scaleEffect(isPressed ? 0.9 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isPressed)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }

    private var zoomText: String {
        if zoom < 1.0 {
            return String(format: ".%.0f", zoom * 10)
        } else {
            return String(format: "%.0f", zoom)
        }
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
