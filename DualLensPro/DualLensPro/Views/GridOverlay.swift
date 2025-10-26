//
//  GridOverlay.swift
//  DualLensPro
//
//  Created by DualLens Pro Team on 10/24/25.
//

import SwiftUI

struct GridOverlay: View {
    var body: some View {
        GeometryReader { geometry in
            Path { path in
                let width = geometry.size.width
                let height = geometry.size.height
                
                // Vertical lines
                let verticalSpacing = width / 3
                path.move(to: CGPoint(x: verticalSpacing, y: 0))
                path.addLine(to: CGPoint(x: verticalSpacing, y: height))
                path.move(to: CGPoint(x: verticalSpacing * 2, y: 0))
                path.addLine(to: CGPoint(x: verticalSpacing * 2, y: height))
                
                // Horizontal lines
                let horizontalSpacing = height / 3
                path.move(to: CGPoint(x: 0, y: horizontalSpacing))
                path.addLine(to: CGPoint(x: width, y: horizontalSpacing))
                path.move(to: CGPoint(x: 0, y: horizontalSpacing * 2))
                path.addLine(to: CGPoint(x: width, y: horizontalSpacing * 2))
            }
            .stroke(Color.white.opacity(0.5), lineWidth: 0.5)
        }
        .allowsHitTesting(false)
    }
}

#Preview {
    GridOverlay()
        .frame(width: 300, height: 400)
        .background(Color.black)
}
