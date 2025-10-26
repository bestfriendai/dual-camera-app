//
//  ZoomControlView.swift
//  DualLensPro
//
//  Created by DualLens Pro Team on 10/24/25.
//

import SwiftUI

struct ZoomControlView: View {
    @EnvironmentObject var viewModel: CameraViewModel
    let availableZoomLevels: [CGFloat] = [0.5, 1.0, 2.0, 5.0]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(availableZoomLevels, id: \.self) { zoomLevel in
                ZoomButton(
                    zoomLevel: zoomLevel,
                    isSelected: isSelectedZoom(zoomLevel),
                    action: {
                        viewModel.setZoomPreset(zoomLevel)
                    }
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .liquidGlass(tint: .black, opacity: 0.3)
    }

    private func isSelectedZoom(_ level: CGFloat) -> Bool {
        abs(viewModel.selectedZoomPreset - level) < 0.1
    }
}

struct ZoomButton: View {
    let zoomLevel: CGFloat
    let isSelected: Bool
    let action: () -> Void

    var displayText: String {
        if zoomLevel < 1 {
            return "0.5x"
        } else if zoomLevel == 1 {
            return "1x"
        } else {
            return String(format: "%.0fx", zoomLevel)
        }
    }

    var body: some View {
        Button(action: action) {
            Text(displayText)
                .font(.system(size: 14, weight: isSelected ? .bold : .medium))
                .foregroundColor(isSelected ? .white : .white.opacity(0.6))
                .frame(width: 50, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(isSelected ? Color.white.opacity(0.25) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(isSelected ? Color.white.opacity(0.4) : Color.clear, lineWidth: 1.5)
                )
        }
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()

        VStack {
            Spacer()
            ZoomControlView()
        }
    }
    .environmentObject(CameraViewModel())
}
