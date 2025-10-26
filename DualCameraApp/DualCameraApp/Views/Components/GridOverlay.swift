
//
//  GridOverlay.swift
//  DualCam Pro
//
//  Camera grid overlays
//

import SwiftUI

struct GridOverlay: View {
    let gridType: GridType
    
    var body: some View {
        GeometryReader { geometry in
            switch gridType {
            case .none:
                EmptyView()
            case .ruleOfThirds:
                RuleOfThirdsGrid()
            case .center:
                CenterGrid()
            case .golden:
                GoldenRatioGrid()
            }
        }
        .allowsHitTesting(false)
    }
}

struct RuleOfThirdsGrid: View {
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            
            Path { path in
                // Vertical lines
                path.move(to: CGPoint(x: width / 3, y: 0))
                path.addLine(to: CGPoint(x: width / 3, y: height))
                
                path.move(to: CGPoint(x: width * 2 / 3, y: 0))
                path.addLine(to: CGPoint(x: width * 2 / 3, y: height))
                
                // Horizontal lines
                path.move(to: CGPoint(x: 0, y: height / 3))
                path.addLine(to: CGPoint(x: width, y: height / 3))
                
                path.move(to: CGPoint(x: 0, y: height * 2 / 3))
                path.addLine(to: CGPoint(x: width, y: height * 2 / 3))
            }
            .stroke(.white.opacity(0.5), lineWidth: 1)
        }
    }
}

struct CenterGrid: View {
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let centerX = width / 2
            let centerY = height / 2
            
            Path { path in
                // Vertical center line
                path.move(to: CGPoint(x: centerX, y: 0))
                path.addLine(to: CGPoint(x: centerX, y: height))
                
                // Horizontal center line
                path.move(to: CGPoint(x: 0, y: centerY))
                path.addLine(to: CGPoint(x: width, y: centerY))
            }
            .stroke(.white.opacity(0.5), lineWidth: 1)
            
            // Center circle
            Circle()
                .stroke(.white.opacity(0.5), lineWidth: 1)
                .frame(width: 40, height: 40)
                .position(x: centerX, y: centerY)
        }
    }
}

struct GoldenRatioGrid: View {
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let phi: CGFloat = 1.618
            
            Path { path in
                // Vertical lines
                path.move(to: CGPoint(x: width / phi, y: 0))
                path.addLine(to: CGPoint(x: width / phi, y: height))
                
                path.move(to: CGPoint(x: width - (width / phi), y: 0))
                path.addLine(to: CGPoint(x: width - (width / phi), y: height))
                
                // Horizontal lines
                path.move(to: CGPoint(x: 0, y: height / phi))
                path.addLine(to: CGPoint(x: width, y: height / phi))
                
                path.move(to: CGPoint(x: 0, y: height - (height / phi)))
                path.addLine(to: CGPoint(x: width, y: height - (height / phi)))
            }
            .stroke(.white.opacity(0.5), lineWidth: 1)
        }
    }
}
