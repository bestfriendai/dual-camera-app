
//
//  CameraLabel.swift
//  DualLensPro
//
//  Created by DualLens Pro Team on 10/24/25.
//

import SwiftUI

struct CameraLabel: View {
    let text: String
    let zoom: CGFloat
    
    var body: some View {
        HStack(spacing: 6) {
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)

            Text(String(format: "%.1fx", zoom))
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
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
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        CameraLabel(text: "Front Camera", zoom: 2.5)
    }
}
