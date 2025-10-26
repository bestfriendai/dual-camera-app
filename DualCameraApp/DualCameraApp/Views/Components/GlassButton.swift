
//
//  GlassButton.swift
//  DualCam Pro
//
//  Liquid glass button component
//

import SwiftUI

struct GlassButton: View {
    let icon: String
    let action: () -> Void
    var size: CGFloat = 44
    var iconSize: CGFloat = 20
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay(
                            Circle()
                                .stroke(.white.opacity(0.3), lineWidth: 1)
                        )
                )
                .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
        }
    }
}

struct GlassButtonLarge: View {
    let icon: String
    let action: () -> Void
    var size: CGFloat = 74
    var iconSize: CGFloat = 32
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay(
                            Circle()
                                .stroke(.white.opacity(0.4), lineWidth: 2)
                        )
                )
                .shadow(color: .black.opacity(0.3), radius: 12, y: 6)
        }
    }
}

struct RecordButton: View {
    @Binding var isRecording: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 84, height: 84)
                
                Circle()
                    .stroke(.white, lineWidth: 4)
                    .frame(width: 74, height: 74)
                
                if isRecording {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.red)
                        .frame(width: 28, height: 28)
                } else {
                    Circle()
                        .fill(.red)
                        .frame(width: 64, height: 64)
                }
            }
            .shadow(color: .black.opacity(0.3), radius: 12, y: 6)
        }
    }
}
