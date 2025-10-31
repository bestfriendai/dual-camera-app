//
//  ModeSelector.swift
//  DualLensPro
//
//  Created by DualLens Pro Team on 10/24/25.
//

import SwiftUI

struct ModeSelector: View {
    @Binding var selectedMode: CaptureMode
    var isPremium: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private func accessibilityTraitsFor(mode: CaptureMode) -> AccessibilityTraits {
        selectedMode == mode ? .isSelected : []
    }

    private func accessibilityValueFor(mode: CaptureMode) -> String {
        if mode.requiresPremium && !isPremium {
            return "Requires premium"
        } else if selectedMode == mode {
            return "Selected"
        } else {
            return "Not selected"
        }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 20) {
                ForEach(CaptureMode.allCases) { mode in
                    Button(action: {
                        HapticManager.shared.modeChange()
                        if reduceMotion {
                            selectedMode = mode
                        } else {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                selectedMode = mode
                            }
                        }
                    }) {
                        HStack(spacing: 6) {
                            Text(mode.displayName.uppercased())
                                .font(.system(size: 12, weight: selectedMode == mode ? .bold : .medium))
                                .foregroundStyle(selectedMode == mode ? .yellow : .white)
                                .tracking(0.2)
                                .lineLimit(1)
                                .fixedSize()

                            // Premium badge
                            if mode.requiresPremium && !isPremium {
                                Image(systemName: "crown.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.yellow)
                            }
                        }
                        .padding(.horizontal, selectedMode == mode ? 16 : 10)
                        .padding(.vertical, 8)
                        .background {
                            if selectedMode == mode {
                                Capsule()
                                    .fill(.white.opacity(0.2))
                            }
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                    .accessibilityLabel("\(mode.displayName) mode")
                    .accessibilityHint("Double tap to select \(mode.displayName) capture mode")
                    .accessibilityAddTraits(accessibilityTraitsFor(mode: mode))
                    .accessibilityValue(accessibilityValueFor(mode: mode))
                }
            }
            .padding(.horizontal, 24)
        }
        .frame(height: 50)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Capture mode selector")
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()

        VStack {
            Spacer()
            ModeSelector(selectedMode: .constant(.video))
                .padding(.bottom, 20)
        }
    }
}
