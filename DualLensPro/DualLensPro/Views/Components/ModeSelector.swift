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

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(CaptureMode.allCases) { mode in
                    Button(action: {
                        HapticManager.shared.modeChange()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selectedMode = mode
                        }
                    }) {
                        HStack(spacing: 4) {
                            Text(mode.displayName.uppercased())
                                .font(.system(size: 13, weight: selectedMode == mode ? .semibold : .regular))
                                .foregroundStyle(selectedMode == mode ? .yellow : .white)
                                .tracking(0.5)

                            // Premium badge
                            if mode.requiresPremium && !isPremium {
                                Image(systemName: "crown.fill")
                                    .font(.system(size: 8))
                                    .foregroundStyle(.yellow)
                            }
                        }
                        .padding(.horizontal, selectedMode == mode ? 16 : 8)
                        .padding(.vertical, 8)
                        .background {
                            if selectedMode == mode {
                                Capsule()
                                    .fill(.white.opacity(0.15))
                            }
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 20)
        }
        .frame(height: 44)
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
