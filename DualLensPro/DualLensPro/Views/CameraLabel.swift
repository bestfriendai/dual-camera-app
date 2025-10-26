
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
        VStack(alignment: .leading, spacing: 4) {
            Text(text)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)

            Text(String(format: "%.1f×", zoom))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.9))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .liquidGlass(tint: .black, opacity: 0.35)
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        CameraLabel(text: "Front Camera", zoom: 2.5)
    }
}
