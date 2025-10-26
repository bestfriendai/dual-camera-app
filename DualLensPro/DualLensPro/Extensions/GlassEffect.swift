
//
//  GlassEffect.swift
//  DualLensPro
//
//  Created by DualLens Pro Team on 10/24/25.
//

import SwiftUI

// MARK: - Liquid Glass Effect Extension
extension View {
    /// Applies a liquid glass effect with backward compatibility for iOS 18-25
    func liquidGlass(
        tint: Color = .clear,
        opacity: Double = 0.2
    ) -> some View {
        self.modifier(LiquidGlassModifier(tint: tint, opacity: opacity))
    }
}

// MARK: - Liquid Glass Modifier
struct LiquidGlassModifier: ViewModifier {
    let tint: Color
    let opacity: Double
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    
    func body(content: Content) -> some View {
        content
            .background {
                if reduceTransparency {
                    // High contrast fallback
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.regularMaterial)
                        .opacity(0.8)
                } else {
                    // Liquid glass effect
                    ZStack {
                        // Base blur
                        RoundedRectangle(cornerRadius: 16)
                            .fill(.ultraThinMaterial)
                        
                        // Gradient overlay
                        LinearGradient(
                            colors: [
                                .white.opacity(0.25),
                                .white.opacity(0.05),
                                tint.opacity(opacity)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        
                        // Border highlight
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        .white.opacity(0.3),
                                        .white.opacity(0.1)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    }
                    .shadow(color: .black.opacity(0.15), radius: 10, y: 5)
                }
            }
    }
}

// MARK: - Capsule Glass
extension View {
    func capsuleGlass(tint: Color = .clear) -> some View {
        self.modifier(CapsuleGlassModifier(tint: tint))
    }
}

struct CapsuleGlassModifier: ViewModifier {
    let tint: Color
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    
    func body(content: Content) -> some View {
        content
            .background {
                if reduceTransparency {
                    Capsule()
                        .fill(.regularMaterial)
                        .opacity(0.8)
                } else {
                    ZStack {
                        Capsule()
                            .fill(.ultraThinMaterial)
                        
                        LinearGradient(
                            colors: [
                                .white.opacity(0.25),
                                .white.opacity(0.05),
                                tint.opacity(0.2)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .clipShape(Capsule())
                        
                        Capsule()
                            .strokeBorder(.white.opacity(0.2), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                }
            }
    }
}

// MARK: - Interactive Glass Button
extension View {
    func glassButton(
        tint: Color = .clear,
        isActive: Bool = false
    ) -> some View {
        self.modifier(GlassButtonModifier(tint: tint, isActive: isActive))
    }
}

struct GlassButtonModifier: ViewModifier {
    let tint: Color
    let isActive: Bool
    @State private var isPressed = false
    @State private var shimmerOffset: CGFloat = -1
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed ? 0.95 : 1.0)
            .background {
                if reduceTransparency {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.regularMaterial)
                        .opacity(isActive ? 0.9 : 0.7)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.ultraThinMaterial)

                        LinearGradient(
                            colors: [
                                isActive ? tint.opacity(0.4) : .white.opacity(0.25),
                                isActive ? tint.opacity(0.2) : .white.opacity(0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                        // Shimmer effect for active state
                        if isActive {
                            LinearGradient(
                                colors: [
                                    .clear,
                                    .white.opacity(0.15),
                                    .clear
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .offset(x: shimmerOffset * 200)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }

                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(
                                isActive ? tint.opacity(0.6) : .white.opacity(0.2),
                                lineWidth: isActive ? 2 : 1
                            )
                    }
                    .shadow(
                        color: isActive ? tint.opacity(0.4) : .black.opacity(0.1),
                        radius: isActive ? 12 : 5,
                        y: 3
                    )
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPressed)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isActive)
            .onAppear {
                if isActive {
                    startShimmerAnimation()
                }
            }
            .onChange(of: isActive) { _, newValue in
                if newValue {
                    startShimmerAnimation()
                }
            }
    }

    private func startShimmerAnimation() {
        withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)) {
            shimmerOffset = 1
        }
    }
}

// MARK: - Circle Glass
extension View {
    func circleGlass(tint: Color = .clear, size: CGFloat = 44) -> some View {
        self.modifier(CircleGlassModifier(tint: tint, size: size))
    }
}

struct CircleGlassModifier: ViewModifier {
    let tint: Color
    let size: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    
    func body(content: Content) -> some View {
        content
            .frame(width: size, height: size)
            .background {
                if reduceTransparency {
                    Circle()
                        .fill(.regularMaterial)
                        .opacity(0.8)
                } else {
                    ZStack {
                        Circle()
                            .fill(.ultraThinMaterial)
                        
                        RadialGradient(
                            colors: [
                                .white.opacity(0.3),
                                .white.opacity(0.05),
                                tint.opacity(0.2)
                            ],
                            center: .topLeading,
                            startRadius: 0,
                            endRadius: size
                        )
                        
                        Circle()
                            .strokeBorder(.white.opacity(0.2), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.15), radius: 8)
                }
            }
    }
}
